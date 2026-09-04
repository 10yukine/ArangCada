"""Regenerate apps/web/public/terms.html and policy.html from the reviewed
markdown source in docs/legal/. Run this whenever TERMS_OF_SERVICE.md or
PRIVACY_POLICY.md changes, so the publicly served pages never drift from the
document that was actually reviewed.

No page design here on purpose (owner: "page design not required as of now,
just the handles") -- this is the same plain, legible CSS already used by
scripts/md_to_pdf.py, not a themed page.
"""
import pathlib

import markdown

ROOT = pathlib.Path(__file__).resolve().parents[1]
LEGAL_DIR = ROOT / "docs" / "legal"
OUT_DIR = ROOT / "apps" / "web" / "public"

CSS = """
body { font-family: Georgia, 'Times New Roman', serif; max-width: 800px;
       margin: 40px auto; line-height: 1.55; color: #1a1a1a; padding: 0 20px; }
h1 { font-size: 26px; border-bottom: 3px solid #1262d0; padding-bottom: 8px; }
h2 { font-size: 19px; margin-top: 34px; color: #0e4ea6; }
h3 { font-size: 15px; margin-top: 22px; }
blockquote { background: #fff3cd; border-left: 5px solid #e0a800; margin: 16px 0;
             padding: 10px 16px; font-size: 14px; }
table { border-collapse: collapse; width: 100%; margin: 14px 0; font-size: 13px; }
th, td { border: 1px solid #ccc; padding: 6px 10px; text-align: left; vertical-align: top; }
th { background: #f0f4fa; }
code { background: #f2f2f2; padding: 1px 5px; border-radius: 3px; font-size: 13px; }
hr { border: none; border-top: 1px solid #ddd; margin: 24px 0; }
p, li { font-size: 14.5px; }
a { color: #1262d0; }
"""

HTML_TEMPLATE = """<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title>
<style>{css}</style></head><body>{body}</body></html>
"""


def convert(md_path: pathlib.Path, out_name: str, title: str) -> pathlib.Path:
    text = md_path.read_text(encoding="utf-8")
    body_html = markdown.markdown(text, extensions=["tables", "fenced_code"])
    html = HTML_TEMPLATE.format(title=title, css=CSS, body=body_html)
    out_path = OUT_DIR / out_name
    out_path.write_text(html, encoding="utf-8")
    return out_path


def main() -> int:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    targets = [
        (LEGAL_DIR / "TERMS_OF_SERVICE.md", "terms.html", "ArangCada — Terms of Service"),
        (LEGAL_DIR / "PRIVACY_POLICY.md", "policy.html", "ArangCada — Privacy Policy"),
    ]
    for md_path, out_name, title in targets:
        out = convert(md_path, out_name, title)
        print(f"OK  {out}  ({out.stat().st_size:,} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
