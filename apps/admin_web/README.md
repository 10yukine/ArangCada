# ArangCada Admin

Standalone Flutter Web console for LGU/TODA internal MVP evaluation. Connected mode reads live, row-level-security-protected Supabase dispatch, driver, SOS, and driver app-feedback records. Without Supabase configuration, an explicitly labeled local demo remains available. This target does not import or depend on `apps/mobile`.

## Run locally

```powershell
E:\Dev\flutter\bin\flutter.bat run -d chrome
```

For the connected console, copy `env.json.example` to the ignored `env.json` file and supply the approved project's Supabase URL, public anonymous key, and optional restricted MapTiler public key. Never commit `env.json`, a service-role key, or any API secret.

```powershell
E:\Dev\flutter\bin\flutter.bat run -d chrome --web-port 58080 --dart-define-from-file=env.json
```

Real sign-in uses Supabase Auth, then verifies the administrator profile and server-assigned LGU/TODA scope. The role selector appears only in the explicit local demo. LGU administrators can manage SOS status and the global completed-trip feedback interval; TODA administrators can review only their own assigned jurisdiction and cannot change either setting. Driver app-feedback participation and formal ISO/IEC 25010 results are labeled separately within the merged Evaluation section.

Without a MapTiler key, the MapLibre canvas uses OpenStreetMap raster tiles.

## Verify

```powershell
E:\Dev\flutter\bin\flutter.bat analyze
E:\Dev\flutter\bin\flutter.bat test
E:\Dev\flutter\bin\flutter.bat build web --release
```
