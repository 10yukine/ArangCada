"""Regenerate apps/web/public/terms.html and policy.html from the reviewed
markdown source in apps/web/legal/. Run this whenever TERMS_OF_SERVICE.md or
PRIVACY_POLICY.md changes, so the publicly served pages never drift from the
document that was actually reviewed.

The shared public-site stylesheet controls presentation; Markdown remains
the source of truth for every legal paragraph and draft notice. The only
restructuring done here is presentational: the metadata paragraphs under the
status notice (Applies to, Prepared by, Last updated/Effective date,
Published at) are lifted into the document header.
"""
import html
import pathlib
import re

import markdown

ROOT = pathlib.Path(__file__).resolve().parents[1]
LEGAL_DIR = ROOT / "apps" / "web" / "legal"
OUT_DIR = ROOT / "apps" / "web" / "public"

HTML_TEMPLATE = """<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title>
<meta name="description" content="{description}">
<meta name="theme-color" content="#1262D0">
<link rel="canonical" href="{canonical_url}">
<link rel="icon" href="/favicon.ico" sizes="any">
<link rel="icon" href="/favicon.svg" type="image/svg+xml">
<link rel="apple-touch-icon" href="/apple-touch-icon.png">
<link rel="stylesheet" href="/site.css?v=20260928">

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
<script src="/mobile-nav.js" defer></script>
</head><body class="legal-page">
<a class="skip" href="#document">Skip to document</a>
<header class="site-header"><div class="wrap header-row">
<a class="brand" href="/ph"><span class="brand-mark"><img src="/assets/mark.svg" alt="" width="30" height="30"></span>ArangCada</a>
<nav class="site-nav" aria-label="Main navigation"><a href="/ph">Home</a><a href="/terms"{terms_current}>Terms</a><a href="/policy"{policy_current}>Privacy</a></nav>
<label class="appearance" data-mode="system"><svg data-mode-icon="system" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m9.5 3-.6 2.4-2 .9-2.2-.7-2.5 4.3 1.7 1.7v2.3l-1.7 1.7 2.5 4.3 2.3-.7 2 .9.5 2.4h5l.6-2.4 2-.9 2.2.7 2.5-4.3-1.7-1.7v-2.3l1.7-1.7-2.5-4.3-2.3.7-2-.9L14.5 3z"/><circle cx="12" cy="12" r="3"/></svg><svg data-mode-icon="light" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="12" cy="12" r="4"/><path d="M12 2v2m0 16v2M2 12h2m16 0h2M5 5l1.5 1.5m11 11L19 19M5 19l1.5-1.5m11-11L19 5"/></svg><svg data-mode-icon="dark" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M20.5 13A8.5 8.5 0 0 1 11 3.5 8.5 8.5 0 1 0 20.5 13Z"/></svg><select data-appearance aria-label="Appearance" title="Appearance"><option value="system">System</option><option value="light">Light</option><option value="dark">Dark</option></select></label>
</div></header>
<main id="main">
<div class="legal-layout wrap">
<aside><details class="legal-nav" open><summary>On this page</summary>{toc}</details></aside>
<div class="legal-document">
<section class="legal-hero">
<p class="eyebrow">{kind}</p>
<h1>{heading}</h1>
<p class="legal-summary">{summary}</p>
<dl class="legal-meta">{meta}</dl>
<div class="legal-actions"><button type="button" class="legal-print" data-print>Print or save as PDF</button><a class="text-link" href="{other_href}">{other_label} <span aria-hidden="true">&rarr;</span></a></div>
</section>
<article class="legal-content" id="document">{body}<p class="legal-end"><a href="#main">Back to top <span aria-hidden="true">&uarr;</span></a></p></article></div></div></main>
<footer class="site-footer"><div class="wrap footer-row"><a class="brand" href="/ph"><span class="brand-mark"><img src="/assets/mark.svg" alt="" width="30" height="30"></span>ArangCada</a><p>Made for the everyday ride.</p><nav class="footer-nav" aria-label="Footer"><a href="/terms">Terms of Service</a><a href="/policy">Privacy Policy</a></nav></div><p class="wrap footer-meta">Academic capstone &middot; National University Laguna &middot; Beta testing</p></footer>
</body></html>
"""

# Order and display names for the header metadata strip.
META_FIELDS = [
    ("Effective date", "Effective"),
    ("Last updated", "Last updated"),
    ("Applies to", "Applies to"),
    ("Prepared by", "Prepared by"),
]


def split_metadata(text: str) -> tuple[str, dict[str, str]]:
    """Lift the **Label:** paragraphs between the status notice and the first
    horizontal rule out of the body. Returns (body markdown, fields)."""
    lines = text.split("\n")
    start = next(i for i, line in enumerate(lines) if line.startswith("**Applies to:**"))
    end = next(i for i in range(start, len(lines)) if lines[i].strip() == "---")
    chunk = " ".join(line.strip() for line in lines[start:end] if line.strip())
    fields: dict[str, str] = {}
    for match in re.finditer(r"\*\*([^*:]+):\*\*\s*(.*?)(?=\s*(?:·\s*)?\*\*[^*:]+:\*\*|$)", chunk):
        fields[match.group(1).strip()] = match.group(2).strip()
    body = "\n".join(lines[:start] + lines[end + 1:])
    return body, fields


def inline(md: str) -> str:
    rendered = markdown.markdown(md)
    return re.sub(r"^<p>|</p>$", "", rendered.strip())


def convert(
    md_path: pathlib.Path,
    out_name: str,
    title: str,
    description: str,
    canonical_url: str,
    heading: str,
    summary: str,
    kind: str,
    other_href: str,
    other_label: str,
) -> pathlib.Path:
    body_md, fields = split_metadata(md_path.read_text(encoding="utf-8"))
    renderer = markdown.Markdown(
        extensions=["tables", "fenced_code", "toc"],
        extension_configs={"toc": {
            "toc_depth": "2-2",
            "permalink": "#",
            "permalink_class": "anchor",
            "permalink_title": "Link to this section",
        }},
    )
    body_html = renderer.convert(body_md)
    meta = "".join(
        f"<div><dt>{label}</dt><dd>{inline(fields[key][:1].upper() + fields[key][1:])}</dd></div>"
        for key, label in META_FIELDS
        if key in fields
    )
    page = HTML_TEMPLATE.format(
        title=title,
        description=description,
        canonical_url=canonical_url,
        toc=renderer.toc,
        body=body_html,
        heading=heading,
        summary=summary,
        kind=kind,
        meta=meta,
        other_href=other_href,
        other_label=html.escape(other_label),
        terms_current=' aria-current="page"' if out_name == "terms.html" else "",
        policy_current=' aria-current="page"' if out_name == "policy.html" else "",
    )
    out_path = OUT_DIR / out_name
    out_path.write_bytes(page.encode("utf-8"))  # LF endings on every OS
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
            "Terms of Service",
            "The rules for using ArangCada as a commuter, driver, or administrator during the Calamba City academic pilot.",
            "Legal · Terms and conditions",
            "/policy",
            "Read the Privacy Policy",
        ),
        (
            LEGAL_DIR / "PRIVACY_POLICY.md",
            "policy.html",
            "ArangCada — Privacy Policy",
            "Official privacy policy and data protection practices for ArangCada in accordance with Philippine Republic Act 10173.",
            "https://arangcada.app/policy",
            "Privacy Policy",
            "What ArangCada collects, why, who can see it, and the rights you have under the Data Privacy Act of 2012.",
            "Legal · Data Privacy Act of 2012",
            "/terms",
            "Read the Terms of Service",
        ),
    ]
    for target in targets:
        out = convert(*target)
        print(f"OK  {out}  ({out.stat().st_size:,} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
