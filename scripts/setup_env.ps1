<#
.SYNOPSIS
    Interactively collects the four client-safe credentials ArangCada's
    Flutter app needs and writes them to apps/mobile/env.json.

.DESCRIPTION
    Run this yourself, in your own terminal. No agent tool call reads this
    script's input or output -- that is the point of it. Values are entered
    with masked input (Read-Host -AsSecureString) and never echoed back,
    logged, or printed by this script.

    apps/mobile/env.json is already covered by the repo's .gitignore
    (see the "env.json" entry). This script does not change that; it only
    writes the file.

    DO NOT enter a Supabase *service role* key here. This file only ever
    holds the four values below, all of which are safe to ship inside a
    compiled client per SECURITY.md ("Supabase URL and anon key are the only
    Supabase values allowed in Flutter or public web code"). The service
    role key must never exist in apps/mobile, in any form.

.PARAMETER Force
    Overwrite an existing env.json without asking first.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\setup_env.ps1
#>

[CmdletBinding()]
param(
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$repoRoot  = Split-Path -Parent $PSScriptRoot
$targetDir = Join-Path $repoRoot 'apps\mobile'
$targetFile = Join-Path $targetDir 'env.json'

if (-not (Test-Path $targetDir)) {
    Write-Error "apps/mobile does not exist at '$targetDir'. Run this from a checkout of the repo, or re-scaffold the Flutter app first."
    exit 1
}

if ((Test-Path $targetFile) -and (-not $Force)) {
    $answer = Read-Host "env.json already exists at $targetFile. Overwrite? [y/N]"
    if ($answer -notmatch '^[Yy]') {
        Write-Host "Left the existing file untouched." -ForegroundColor Yellow
        exit 0
    }
}

function Read-SecretValue {
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string]$Hint
    )
    while ($true) {
        Write-Host ""
        Write-Host "$Label" -ForegroundColor Cyan
        Write-Host "  $Hint" -ForegroundColor DarkGray
        $secure = Read-Host -AsSecureString -Prompt "  Paste value (input hidden)"
        # NetworkCredential is the simplest cross-version way to unwrap a
        # SecureString back to plaintext; PowerShell has no built-in that
        # avoids this entirely, and the value must end up as plaintext JSON
        # anyway since --dart-define-from-file reads it as plaintext.
        $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        )
        if ([string]::IsNullOrWhiteSpace($plain)) {
            Write-Host "  Empty value -- try again, or Ctrl+C to abort." -ForegroundColor Red
            continue
        }
        return $plain
    }
}

Write-Host "ArangCada client config" -ForegroundColor Green
Write-Host "Values are hidden as you type and are never printed by this script." -ForegroundColor DarkGray
Write-Host "Never paste a Supabase SERVICE ROLE key here -- only the anon/publishable key." -ForegroundColor Yellow

$supabaseUrl     = Read-SecretValue -Label "SUPABASE_URL"     -Hint "Project Settings -> API -> Project URL"
$supabaseAnonKey = Read-SecretValue -Label "SUPABASE_ANON_KEY" -Hint "Project Settings -> API -> anon / publishable key (NOT service_role)"
$mapTilerKey     = Read-SecretValue -Label "MAPTILER_KEY"     -Hint "MapTiler Cloud dashboard -> Keys"
$orsApiKey       = Read-SecretValue -Label "ORS_API_KEY"      -Hint "openrouteservice / HeiGIT dashboard -> API keys"

$config = [ordered]@{
    SUPABASE_URL      = $supabaseUrl
    SUPABASE_ANON_KEY = $supabaseAnonKey
    MAPTILER_KEY      = $mapTilerKey
    ORS_API_KEY       = $orsApiKey
}

$json = $config | ConvertTo-Json -Depth 2

# Write without a BOM. Windows PowerShell 5.1's -Encoding utf8 adds one,
# which some JSON readers tolerate and some don't -- avoid the question.
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($targetFile, $json, $utf8NoBom)

# Clear the plaintext variables from this session now that they're on disk.
Remove-Variable supabaseUrl, supabaseAnonKey, mapTilerKey, orsApiKey, config, json -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "Wrote $targetFile (4 values set)." -ForegroundColor Green
Write-Host "Confirming it is gitignored..." -ForegroundColor DarkGray

Push-Location $repoRoot
try {
    $ignoreCheck = git check-ignore -v 'apps/mobile/env.json' 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  OK: git ignores this file ($ignoreCheck)" -ForegroundColor Green
    } else {
        Write-Host "  WARNING: git does NOT report this file as ignored. Do not run 'git add' near it until this is fixed." -ForegroundColor Red
    }
} finally {
    Pop-Location
}

Write-Host ""
Write-Host "Next: from apps\mobile, run:" -ForegroundColor Cyan
Write-Host "  flutter run --dart-define-from-file=env.json"
Write-Host "or for a build:" -ForegroundColor Cyan
Write-Host "  flutter build apk --dart-define-from-file=env.json --debug"
