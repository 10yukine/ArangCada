# ArangCada

A localized tricycle hailing and dispatch system for Calamba City, Philippines — a TODA- and LGU-centered capstone project, not a generic ride-hailing clone.

The system digitizes the manual tricycle *pila* process through mobile booking, TODA-based dispatching, LGU fare computation, driver verification, real-time tracking, trip records, and emergency reporting.

## Status

The Flutter mobile app, Flutter Web admin console, static tracking page, and Supabase backend are implemented. Work is in internal testing and verification; this is not a production-readiness claim.

## Repository map

- `apps/mobile`: commuter and driver Flutter app; owns its dependencies, lint rules, and tests.
- `apps/admin_web`: Flutter Web console. Feature screens live in `lib/screens`; `lib/screens.dart` preserves existing imports.
- `apps/track_web`: static HTML/CSS/JavaScript tracking page with Node tests.
- `apps/web`: static public information and legal pages.
- `supabase/functions`: Edge Functions; shared HTTP and invitation transport lives in `_shared`.
- `supabase/migrations` and `supabase/tests`: ordered SQL migrations and pgTAP coverage.

## Local verification

Run `flutter analyze` and the relevant `flutter test` paths from the affected Flutter app directory. Run `npm test` from `apps/track_web`. Edge transport tests use Deno with mocked provider requests:

```sh
deno test --allow-env --allow-read=supabase/functions supabase/functions/_shared/transport_test.ts supabase/functions/admin-onboard-driver/lib_test.ts supabase/functions/send-sms-hook/index_test.ts
```

The database test runner rebuilds its target database. Inspect `scripts/run_db_tests.sh` and explicitly select a disposable local database before using it. Live schema changes are not part of local verification.

Deployment configuration lives in each site's `wrangler.jsonc` and in `supabase/config.toml`. No GitHub Actions workflow files are committed in this repository.

## Stack (3-month internal MVP)

- **Mobile app:** Flutter + Dart (Android-first), Riverpod, go_router
- **Admin dashboard:** Flutter Web, hosted on Cloudflare Pages
- **Backend:** Supabase Free tier — Auth, PostgreSQL + PostGIS (+RLS), Realtime, Storage, Edge Functions
- **Maps/routing:** MapLibre + MapTiler Free + OpenStreetMap, openrouteservice
- **Location:** geolocator (Android fused location provider)
- **Local cache:** Hive (read-only, session/profile/fare-matrix/trip-history)
- **Dispatch logic:** Point-in-polygon TODA geofencing via PostGIS spatial containment queries, Haversine distance, LGU fare matrix (Calamba City Ordinance No. 743, s. 2022 — see [docs/LGU_FARE_MATRIX.md](docs/LGU_FARE_MATRIX.md))

See [docs/TECH_STACK_DECISIONS.md](docs/TECH_STACK_DECISIONS.md) for rationale.

## Key documents

- [CLAUDE.md](CLAUDE.md) / [AGENTS.md](AGENTS.md) — build rules for AI coding agents
- [SAFETY.md](SAFETY.md) — agent sandbox policy
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — system architecture
- [docs/TECH_STACK_DECISIONS.md](docs/TECH_STACK_DECISIONS.md) — stack decisions and migration path

## Scope guardrails

Calamba City only. Internal testing only — no production deployment, no app store release. Bookable ride type: `special` (Espesyal na Byahe), 1-4 passengers; `pooling` is retained in the schema as the ordinance record of Regular na Byahe but is not offered to commuters. Dispatch matches the nearest available driver city-wide with a staged 1 km -> 3 km search radius. Commuters can share a live ride-tracking link. Payments: cash, GCash record, QR transfer record. No surge pricing.
