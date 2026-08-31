# `apps/track_web` — public ride-tracking page

The page a family member opens when a commuter shares a tracking link.

```
https://arangcada.app/t/<token>
```

**Spec:** `.pipeline/spec-ride-share-page.md`
**Server side:** `supabase/migrations/20260831120000_ride_share_links.sql`

---

## Why this is not Flutter

The rest of this project is Flutter. This page is not, deliberately, and the
reason is the audience: **a worried parent on a low-end Android phone, on mobile
data, who has never used ArangCada and never will.** They tap a link in
Messenger to see where a tricycle is.

A Flutter Web build ships CanvasKit — roughly 2 MB before anything renders.
That is a poor trade for a map and one line of status text, and it fails
CLAUDE.md rule 11 (Android first, slow mobile data) on exactly the device class
this project targets.

Three static files and one CDN script tag come to roughly 200 KB gzipped.

**This does not open the door to non-Flutter code elsewhere.** `apps/mobile` and
`apps/admin_web` stay 100% Flutter. There is no npm install, no bundler, and no
framework here — the whole page is HTML, CSS, and two ES modules.

## Files

**`public/` is the only directory that gets published.** Everything else is
source and tooling, and is never served — pointing the deploy at the parent
would have published the tests and this README at `arangcada.app/README.md`.

| File | Purpose |
|---|---|
| `public/index.html` | Markup for the four states: landing, loading, active, expired |
| `public/render.js` | **Pure logic** — token parsing, view model, wording. No DOM, no network |
| `public/track.js` | Fetch, poll, and DOM updates |
| `public/style.css` | Styling, using the app's colour tokens and the system font |
| `public/config.js` | **Generated, gitignored.** Written by `build-config.js` |
| `render.test.js` | 22 tests, `node --test`, no browser needed |
| `build-config.js` | Writes `public/config.js` from env vars at deploy time |
| `wrangler.jsonc` | Workers deploy config: served directory and SPA routing |

The split between `render.js` and `track.js` exists so the logic is testable
without a headless browser. This page is public and unauthenticated, so its
failure behaviour deserves real coverage — and coverage that needed a browser
would never actually get run.

## Test

```bash
node --test apps/track_web/render.test.js
```

Covers token parsing, the four initial states, expiry, unknown statuses,
staleness wording, clock skew, missing driver positions, and two privacy
assertions: that the view model carries no rider identity or fare even if the
payload grows, and that the page sets `no-referrer` and `noindex`.

## Configure

`public/config.js` is generated, never hand-written and never committed:

```bash
SUPABASE_URL=https://<ref>.supabase.co SUPABASE_ANON_KEY=<anon key> MAPTILER_STYLE_URL='https://api.maptiler.com/maps/streets-v2/style.json?key=<key>' node apps/track_web/build-config.js
```

Same command, same three variables, locally and in CI — one mechanism rather
than a checked-in example file that drifts out of date.

**None of the three is a secret**; all ship to the browser. The anon key is
designed for clients and RLS protects the data — `ride_share_links` denies
`anon` outright, and the only function `anon` can execute is
`ride_share_view()`. The MapTiler key is client-side by design.

> ⚠️ **Restrict the MapTiler key to `arangcada.app`** in the MapTiler dashboard.
> The control is the domain restriction, not secrecy — a public web page is more
> exposed than an APK. Do this before sharing any link.

`build-config.js` fails rather than writing a partial config, and refuses a key
containing `service_role`.

## Deploy — Cloudflare Workers

Cloudflare merged Pages into Workers, so this deploys with `wrangler deploy`
rather than a dashboard "output directory" setting. A separate project from the
admin console.

| Setting | Value |
|---|---|
| Build command | `node apps/track_web/build-config.js` |
| Deploy command | `npx wrangler deploy --config apps/track_web/wrangler.jsonc` |
| Custom domain | `arangcada.app` |

`/t/<token>` works because `wrangler.jsonc` sets
`not_found_handling: "single-page-application"` — any path that is not a real
file serves `index.html`, and `track.js` reads the token from the URL. No
`_redirects` file is needed.

Step-by-step, including which variables screen to use, is in
`docs/DOMAIN_DNS_RUNBOOK.md` Part 2.

**`config.js` is gitignored**, so it is not in the repo Pages clones. The build
command generates it from environment variables set in the Pages project:

| Env var | Example |
|---|---|
| `SUPABASE_URL` | `https://<ref>.supabase.co` |
| `SUPABASE_ANON_KEY` | the anon / publishable key |
| `MAPTILER_STYLE_URL` | `https://api.maptiler.com/maps/streets-v2/style.json?key=...` |

`build-config.js` **fails the build** on a missing variable rather than emitting
a broken config — a deploy that silently shows every visitor "this tracking link
has expired" is worse than one that stops and names the problem. It also refuses
to run if the anon key looks like a service-role key.

Never solve this by committing the real `config.js`.

## Behaviour

- Polls `ride_share_view()` every 10 s while the tab is visible.
- **Stops polling when the tab is hidden**, resumes on return. A phone in a
  pocket must not poll all afternoon.
- Backs off to 30 s after repeated failures.
- Stops permanently once the link expires.
- A failed poll **keeps the last good render** and shows a quiet "Reconnecting"
  note rather than blanking the map.
- Unknown token, revoked link, and finished trip all show the **same** message.
  Distinguishing them would confirm to a stranger that a guessed token was once
  real.

## What this page deliberately does not show

Trip status, vehicle position, pickup and destination **labels**, driver name,
body number, and TODA. That is all.

No rider name, phone, email, or address. No fare. No chat. No trip history. No
location trail — one current point only. No cookies, no `localStorage`, no
analytics.

This matches `docs/legal/PRIVACY_POLICY.md` §6a, which is already written and
discloses exactly this payload. **Do not widen it without a spec and a council
review** — `ride_share_view()` is the only `anon`-callable read path in the
entire system.

## Not done

- **No Share button exists in the mobile app yet.** This page renders a link;
  nothing generates one. `create_ride_share_link()` is built and tested but is
  not called from anywhere.
- Never opened on a real device against a real trip.
- Council review of `ride_share_links` still outstanding.
