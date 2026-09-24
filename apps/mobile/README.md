# ArangCada — Flutter client

TODA-aware tricycle booking and dispatch for Calamba City. Academic capstone
prototype, National University Laguna. Android-first.

---

## What is real and what is simulated

This is the single most important table in this file. Do not blur it.

| Capability | Status |
|---|---|
| **Supabase Auth** | **Live.** URL and publishable key are wired; `Supabase.initialize` runs at startup when configured. |
| **MapLibre renderer** | **Live.** Real vector map, verified on a physical SM-A325F. |
| **MapTiler tiles / styles** | **Live.** `streets-v2` style, attribution always visible. |
| **MapTiler geocoding** | **Live.** Forward search and reverse lookup, scoped to Calamba. |
| **openrouteservice Directions** | **Live.** Road geometry, distance and duration, drawn on the map. |
| **Device GPS (geolocator)** | **Live.** While-in-use only. |
| Dispatch / driver matching | **Live for authenticated accounts.** Guarded Supabase RPC assigns an approved same-TODA driver; hidden demo accounts retain simulation. |
| Driver availability and positions | **Live for authenticated accounts.** Foreground device GPS is scoped to the assigned ride and authorized administrators. |
| Trip persistence | **Live for authenticated accounts.** Server-owned trip transitions, locked ordinance fare, and a 30-second driver offer. |
| Chat transport | **Live for authenticated accounts.** Private realtime text chat; completed trips remain read-only for 30 days. |
| Safety reports | **Live for authenticated accounts.** Three-second hold, issue selection, then delivery to scoped LGU/TODA administrators. No emergency service is contacted. |
| Driver app evaluation | **Live for authenticated drivers.** Required bilingual five-point feedback after the configured completed-trip interval; passenger ratings remain separate. |
| Wallet balance and payments | Sandbox. No provider connected, no money moves. |
| Driver payouts / settlement | Sandbox. |
| Predictive ETA | Mock range. |

`lib/data/providers/repository_providers.dart` selects connected repositories
only for a matching authenticated Supabase account. Hidden `@arangcada.demo`
accounts remain explicitly local.

---

## Configuration

Values are compile-time, supplied with `--dart-define-from-file`. Nothing is
read from a bundled asset, so the JSON never ships inside the APK.

```
MAPTILER_KEY
ORS_API_KEY
SUPABASE_URL
SUPABASE_ANON_KEY
```

Copy `env.json.example` to `env.json` and fill it in. `env.json` is gitignored
and must never be committed. **The Supabase service-role key has no variable
reserved here and must never be added.**

Place this Android app's `google-services.json` from the team Firebase project
at `android/app/google-services.json`. It is also gitignored. Ask a project
maintainer for the client configuration; do not put either file in a commit.

Each integration reports readiness on its own (`AppConfig.isMapTilerConfigured`
and friends), so a missing map key costs the map, not authentication.

## Run

```bash
flutter run --dart-define-from-file=env.json
```

## Build

```bash
flutter build apk --release --split-per-abi --dart-define-from-file=env.json
```

Install `app-arm64-v8a-release.apk` on a modern device. Release is signed with
the debug key: internal testing only. Uninstall any differently-signed build
first to avoid `INSTALL_FAILED_UPDATE_INCOMPATIBLE`.

## Test

```bash
flutter analyze
flutter test
```

---

## Fare rules (do not "simplify" these)

- Billable distance is the **Haversine** straight line between the fixed pickup
  and destination. openrouteservice road distance and duration are display-only
  and structurally cannot reach the fare engine.
- The predictive ETA never influences fare.
- Amounts come from `docs/LGU_FARE_MATRIX.md` (Calamba City Ordinance No. 743,
  s. 2022), transcribed verbatim as integer centavos — all 76 published values.
  The discount column is **not** a flat 20%: Regular 4 km prints ₱15.50 and
  16 km prints ₱34.00. Never compute the discount.
- Everything at or under 2 km is the base bracket; past that every started
  kilometre bills in full. Past the printed 20 km table the ordinance's own
  per-kilometre rule extrapolates.
- Fare locks at booking confirmation. Driver movement, rerouting, GPS jitter
  and ETA changes must never reprice a confirmed booking.
- Pooling is priced **per passenger** (Regular na Byahe). Special is **per trip**
  (Espesyal na Byahe). Pooling is never a Special fare divided among riders.

---

## API behaviour under failure

| Service | Failure | Behaviour |
|---|---|---|
| MapTiler tiles | style not loaded within 15 s | Quiet "Map unavailable" card. Booking continues. |
| MapTiler geocoding | 401 / 403 / 429 / timeout | Message plus saved and popular places; Pin on map still works. |
| openrouteservice | **429** (per-minute limit) | Cooldown started, cached route served, no retry loop. |
| openrouteservice | **403** (authorization invalid or daily allowance spent) | Automatic requests disabled for the session, straight-line fallback. |
| openrouteservice | 401 / timeout / bad body | Straight-line fallback marked `isFallback`, drawn fainter, captioned honestly, **no routing attribution**. |
| GPS | denied / denied-forever / disabled / timeout / coarse | Typed reason and a "Choose pickup" path. Never blocks booking. |
| Supabase Auth | network failure | Auth error surfaced. A real account is never silently swapped for a mock one. |

### openrouteservice request discipline

HeiGIT provides the Collaborative plan for **non-commercial academic use** and
asked that unnecessary requests not be sent. `OpenRouteServiceRoutingRepository`
therefore enforces: one request per materially-changed endpoint pair, a single
in-flight request, a 30-minute coordinate-keyed cache, a 40 m jitter threshold,
and no automatic retry after 429 or 403. Requests are never issued from
`build()`, from a map gesture, or on a timer.

The key travels in an `Authorization` header, never a query string, so it
cannot land in provider access logs or a crash report.

### ORS host

`api.openrouteservice.org`. A `*.heigit.org` API host was investigated and does
not exist — `api.openrouteservice.heigit.org`, `ors.heigit.org` and
`api.ors.heigit.org` do not resolve, and `openrouteservice.heigit.org` is a 301
to an information page. Do not "migrate" this constant without checking DNS
first; doing so silently disables routing.

---

## Attribution

Required and always visible, never hidden behind a control:

- Map data © OpenStreetMap contributors (ODbL)
- Tiles by MapTiler
- Routing by openrouteservice (HeiGIT)

Routing attribution appears **only** when a real ORS route is displayed. A
straight-line fallback shows none, because nothing was routed. No endorsement
by HeiGIT, MapTiler or the OpenStreetMap Foundation is implied.

---

## Authentication

Email and password only.

- **No Apple Sign-In.** No button, no icon, no dependency, no code path. The
  original HTML prototype had one; it was deliberately not ported.
- **No Google Sign-In button.** Rather than ship a dead or half-configured
  social control, it is absent.
- Drivers do not self-register; enrolment is administered.
- Connected mobile roles and developer-only Cabuyao access come from the
  authoritative `profiles` row, never user-editable account metadata.
- Cabuyao/SJVTODA is synthetic, provisional, and restricted to trusted internal
  tester accounts; Calamba remains the permanent service area.

---

## Payments

No payment provider is selected or connected. The wallet is a sandbox: top-up,
ride debit, refund, transaction history and settlement state all run locally.
Balances are labelled `SANDBOX` and every payment surface states that no funds
move. ArangCada does not custody customer funds; in production a digital
balance is provider-held. `PaymentRepository` is the single replacement point.

---

## Development backend prerequisite

Connected trips, chat, SOS, and evaluation require the reviewed live-connected
Supabase migration chain to exist on the configured development project. When a
hidden demo account is chosen, the previous on-device walkthrough remains
available without remote ride data. This is internal testing only.

---

## Architecture

```
lib/
  app/        router (go_router + role guards), shells, theme tokens
  core/       format, geo (Haversine), network, widgets (owned components, map)
  domain/     models, fare (matrix + calculator), state machines
  data/       repositories (interfaces), remote (live), mock (simulated), local
  features/   auth home search booking trip chat wallet profile driver ...
  demo/       seed data and simulation
```

Widgets never call HTTP directly. Every integration sits behind an interface in
`data/repositories/`, bound in one place, so replacing a mock with a real
implementation touches no screen.

`core/widgets/arang_ui.dart` holds the owned component primitives. They follow
shadcn/ui's *discipline* — components live in this repository rather than a
package, every value comes from `app/theme`, variants are explicit — but are
written in Dart, because shadcn itself is React and Tailwind and cannot produce
Flutter widgets.

Commuter tabs: Home · Chat · Trips · Wallet · Profile.
Driver tabs: Home · Chat · Earnings · Profile.
