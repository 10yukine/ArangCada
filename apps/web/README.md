# `apps/web` — ArangCada root/marketing site

Serves `arangcada.app` and `www.arangcada.app`. Split off `apps/track_web`
on 4 September 2026 so the apex domain can be the public marketing/legal
site instead of the ride-tracking tool — see `.pipeline/specs.md` "Split
arangcada.app" and `docs/DOMAIN_DNS_RUNBOOK.md`'s "Part 8" addendum.

```
https://arangcada.app          -> redirects to /ph
https://arangcada.app/ph       -> main webpage
https://arangcada.app/terms    -> Terms of Service
https://arangcada.app/policy   -> Privacy Policy
```

**No page design yet.** The owner's instruction for this pass was "page
design not required as of now, just the handles" — every page here is a
plain, unstyled-beyond-legibility placeholder or a rendered legal document,
not a themed site. Do not treat this as the final look.

## Why this is not Flutter, and not one project with `apps/track_web`

Same reasoning as `apps/track_web/README.md`: this is a public, no-account
surface, so it should stay small and framework-free rather than shipping
Flutter Web's ~2 MB CanvasKit payload for three static pages. It is a
**separate** Cloudflare project from `apps/track_web` on purpose — the two
now live on different (sub)domains (`arangcada.app` vs
`track.arangcada.app`) and have different jobs; folding them into one
project would recouple two things that were just deliberately split apart.

## Files

| File | Purpose |
|---|---|
| `public/_redirects` | Root -> `/ph` only. An earlier draft also had a legacy `/t/<token>` -> `track.arangcada.app` redirect; removed 4 Sep 2026 since no real tracking link had been shared yet (still in dev) — see `.pipeline/changes.md` if that ever needs to come back |
| `public/ph.html` | Main webpage placeholder |
| `public/terms.html` | Terms of Service — **generated**, not hand-authored |
| `public/policy.html` | Privacy Policy — **generated**, not hand-authored |
| `wrangler.jsonc` | Workers static-assets deploy config, `arangcada.app` + `www` custom domains |

## Keeping the legal pages in sync

`terms.html` and `policy.html` are rendered from `docs/legal/*.md` by
`scripts/render_legal_html.py` (run from the repo root). **Never hand-edit
either HTML file** — edit the markdown source, then re-run:

```bash
python scripts/render_legal_html.py
```

Both markdown files are still marked `DRAFT — internal capstone review
only` with open `[⚠️ LEGAL REVIEW REQUIRED]` items as of this writing (see
`CLAUDE.md`'s "Legal and Compliance Docs" section). Publishing this site
does not resolve that status — the rendered HTML carries the same draft
banner and warning callouts the markdown has.

## Deploying

See `docs/DOMAIN_DNS_RUNBOOK.md` Part 8: deploy this as a new Workers
project (`arangcada-web`), which claims `arangcada.app` / `www.arangcada.app`
once `arangcada-track` has released them by redeploying with its updated
config, then attach `track.arangcada.app` to `arangcada-track`. Also update
the MapTiler key's allowed-origin restriction to `track.arangcada.app/*`
once the move happens — the tracking page's map tiles will silently stop
loading until that dashboard setting is updated, since a code change cannot
do it.
