# ArangCada

A localized tricycle hailing and dispatch system for Calamba City, Philippines — a TODA- and LGU-centered capstone project, not a generic ride-hailing clone.

The system digitizes the manual tricycle *pila* process through mobile booking, TODA-based dispatching, LGU fare computation, driver verification, real-time tracking, trip records, and emergency reporting.

## Status

**Pre-implementation.** The design phase (Figma mockups) is complete/ongoing in a separate local planning workspace. This repository holds the project documentation and will hold the Flutter application once implementation mode starts.

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
