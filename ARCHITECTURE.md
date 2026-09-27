# ARCHITECTURE.md — ArangCada System Architecture
*Single reference for system shape, trust boundaries, and data flow. Update only when the architecture actually changes, not per feature. Feature-level detail belongs in `.pipeline/specs.md`, not here.*

---

## 1. High-Level Shape

Three clients talk to one Supabase backend. There is no custom server in the MVP.

```text
[Commuter App]     [Driver App]      [Admin Web]
      |                  |                |
      +------- Flutter + supabase_flutter client -------+
                          |
                          v
   Supabase Free: Auth | Postgres + PostGIS + RLS | Realtime | Storage | Edge Functions/RPC
                          |
                          v
 MapLibre renderer -> MapTiler/OSM tiles -> openrouteservice route lookups
```

Commuter and Driver run on the same Flutter codebase, split by role-gated routes (`go_router`). Admin runs as Flutter Web against the same Supabase project. Nothing here needs a separate backend service — Supabase's Auth, Postgres+RLS, Realtime, Storage, and Edge Functions already cover every layer this app needs.

---

## 2. Layer Responsibilities

| Layer | Owns | Must never do |
|---|---|---|
| Flutter mobile (commuter/driver) | UI, local form validation, fare *preview*, map rendering, sending action RPCs | Compute final fare, assign drivers, hold service role key |
| Flutter Web (admin) | Driver review UI, zone/fare viewers, audit log viewer | Approve drivers via a client-only check with no RLS/RPC backing |
| Supabase Postgres + PostGIS + RLS | Source of truth for every table, row-level access control, and TODA boundary/driver-position geometry (PostGIS containment queries) | Trust a role claim the client sent without server-side verification |
| Supabase Edge Functions / RPC | Final fare, driver assignment, approvals, SOS creation, cancellation rules | Skip status preconditions (see `CONCURRENCY_AND_STATE.md`) |
| Supabase Realtime | Ride status, driver availability, location pushes | Broadcast fields a subscriber isn't authorized to see |
| Supabase Storage | Driver documents, payment proof | Serve from a public bucket |
| MapLibre | Client-side map rendering, markers, TODA polygon display | Own ride, fare, dispatch, or authorization decisions |
| MapTiler Free / OpenStreetMap data | Development map styles and tiles | Receive Supabase records or private user data |
| openrouteservice | Route preview and distance/duration lookup | Decide TODA eligibility or final LGU fare |
| geolocator (client-side) | Android fused-location access feeding position to Realtime/RPC calls | Decide TODA eligibility or compute final fare |
| Hive (client-side) | Read-only local cache of session/profile/fare-matrix/trip-history for display | Cache secrets, tokens, driver documents, or act as an offline write queue |
| Cloudflare Workers | Static hosting/CDN for the Flutter Web admin build | Hold Supabase service-role credentials or execute trusted logic |

---

## 3. Trust Boundary

CLAUDE.md already has the authoritative **Trusted Logic Placement** table — don't duplicate it here, just remember the rule it encodes: *the client may preview, the server decides.* The two flows below are where that boundary actually gets exercised, and where a panel is most likely to poke.

---

## 4. Special Ride Data Flow (sequence)

```text
1. Commuter: preview fare (client-side Haversine + local fare_matrix read)
2. Commuter: request_ride(pickup, dropoff, type, idempotency_key)  -> RPC
3. Server: validate Calamba/TODA boundary, insert row, status=requested
4. Server: dispatch RPC/Edge Function finds eligible driver
            (approved + online + in-zone + no active ride), atomic assign
5. Realtime: pending request pushed to candidate driver
6. Driver: accept_ride(ride_id) -> RPC, first valid write wins (see
            CONCURRENCY_AND_STATE.md), status=accepted
7. Realtime: assignment pushed to rider
8. Driver: location pings written to trip_locations while assigned/active
9. Commuter: subscribes to trip + trip_locations for that trip only
10. Driver: mark_arrived -> start_trip -> complete_trip (RPC chain)
11. Server: final fare computed server-side, immutable trip ledger row written
```

Anything in steps 3, 4, 6, 10, 11 is a hard "no client-only authority" zone.

---

## 5. Internal Testing Topology

Use one hosted Supabase Free project for development and internal capstone testing. A second isolated demo project is optional only if the free-tier allowance and schedule permit; it is not a production environment.

| Project | Purpose | Notes |
|---|---|---|
| Development/Internal Test | Daily build, physical Android tests, evaluator sessions | Seeded with sanitized data; never publicly deployed |
| Optional Demo/Capstone | Panel demonstration if quotas permit | Migrations replayed cleanly and seeded with the Minimum Demo Data set from `TOOLS.md` |

There is no production deployment, App Store release, or Play Store release in the three-month plan.

---

## 6. Why Not Microservices or a Custom Backend

Supabase already gives you Auth, Postgres+PostGIS+RLS, Realtime, Storage, Edge Functions, and SQL RPC in one managed platform. Adding Node/Fastify, Redis, or Socket.io would mean standing up and securing a second system for no panel-relevant benefit, and it breaks the "beginner-maintainable" rule in CLAUDE.md. A three-month capstone with a small student team does not need service boundaries a single Supabase project cannot already enforce through RLS.

The map/routing provider is isolated behind an adapter. A future funded pilot may substitute Google Maps, HERE, or Mapbox without changing Supabase data ownership, ride state, TODA geofencing, or fare rules.

---

## 7. Related Files

- `CLAUDE.md` — stack, execution rules, Trusted Logic Placement table
- `SECURITY.md` — RLS baseline, storage policies, manual security tests
- `CONCURRENCY_AND_STATE.md` — why action-based RPCs, not full-row overwrites
- `.pipeline/SPEC_TEMPLATE.md` — where feature-level architecture decisions actually get written
