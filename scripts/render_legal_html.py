"""Regenerate apps/web/public/terms.html and policy.html from the reviewed
markdown source in docs/legal/. Run this whenever TERMS_OF_SERVICE.md or
PRIVACY_POLICY.md changes, so the publicly served pages never drift from the
document that was actually reviewed.

The shared public-site stylesheet controls presentation; Markdown remains
the source of truth for every legal paragraph and draft notice.
"""
import pathlib

import markdown

ROOT = pathlib.Path(__file__).resolve().parents[1]
LEGAL_DIR = ROOT / "docs" / "legal"
OUT_DIR = ROOT / "apps" / "web" / "public"

HTML_TEMPLATE = """<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title>
<meta name="description" content="{description}">
<meta name="theme-color" content="#1262D0">
<link rel="canonical" href="{canonical_url}">
<link rel="icon" href="/assets/mark.svg" type="image/svg+xml">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Fredoka:wght@300..700&display=swap" rel="stylesheet">
<link rel="stylesheet" href="/site.css">

<!-- Open Graph / Facebook / Messenger -->
<meta property="og:type" content="article">
<meta property="og:site_name" content="ArangCada">
<meta property="og:url" content="{canonical_url}">
<meta property="og:title" content="{title}">
<meta property="og:description" content="{description}">
<meta property="og:image" content="https://arangcada.app/assets/og-banner.png">
<meta property="og:image:secure_url" content="https://arangcada.app/assets/og-banner.png">
<meta property="og:image:type" content="image/png">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta property="og:image:alt" content="ArangCada Calamba Logo Banner">

<!-- Twitter -->
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:url" content="{canonical_url}">
<meta name="twitter:title" content="{title}">
<meta name="twitter:description" content="{description}">
<meta name="twitter:image" content="https://arangcada.app/assets/og-banner.png">

<script src="/appearance.js"></script>
</head><body>
<a class="skip" href="#main">Skip to content</a>
<header class="site-header wrap">
<a class="brand" href="/ph"><img src="/assets/mark.svg" alt="" width="40" height="40">ArangCada</a>
<nav aria-label="Main navigation"><a href="/ph">Home</a><a href="/terms">Terms</a><a href="/policy">Privacy</a></nav>
<label class="appearance"><span class="sr-only">Appearance</span><select data-appearance aria-label="Appearance"><option value="system">System</option><option value="light">Light</option><option value="dark">Dark</option></select></label>
</header>
<main id="main" class="legal-layout wrap">
<aside class="legal-nav"><details open><summary>On this page</summary>{toc}</details></aside>
<article class="legal-content">{body}</article></main>
<footer class="site-footer wrap"><a class="brand" href="/ph">ArangCada</a><p>Made for the everyday ride.</p><nav aria-label="Footer"><a href="/terms">Terms of Service</a><a href="/policy">Privacy Policy</a></nav><span class="small">Academic capstone · Beta testing</span></footer>
</body></html>
"""


def convert(
    md_path: pathlib.Path,
    out_name: str,
    title: str,
    description: str,
    canonical_url: str,
) -> pathlib.Path:
    text = md_path.read_text(encoding="utf-8")
    renderer = markdown.Markdown(
        extensions=["tables", "fenced_code", "toc"],
        extension_configs={"toc": {"toc_depth": "2-2"}},
    )
    body_html = renderer.convert(text)
    html = HTML_TEMPLATE.format(
        title=title,
        description=description,
        canonical_url=canonical_url,
        toc=renderer.toc,
        body=body_html,
    )
    out_path = OUT_DIR / out_name
    out_path.write_text(html, encoding="utf-8")
    return out_path


def main() -> int:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    targets = [
        (
            LEGAL_DIR / "TERMS_OF_SERVICE.md",
            "terms.html",
            "ArangCada — Terms of Service",
            "Official terms, conditions, and user rights for ArangCada tricycle booking and dispatch in Calamba City.",
            "https://arangcada.app/terms",
        ),
        (
            LEGAL_DIR / "PRIVACY_POLICY.md",
            "policy.html",
            "ArangCada — Privacy Policy",
            "Official privacy policy and data protection practices for ArangCada in accordance with Philippine Republic Act 10173.",
            "https://arangcada.app/policy",
        ),
    ]
    for md_path, out_name, title, description, canonical_url in targets:
        out = convert(md_path, out_name, title, description, canonical_url)
        print(f"OK  {out}  ({out.stat().st_size:,} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
