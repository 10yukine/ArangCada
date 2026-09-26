# ArangCada

**Tricycle booking and dispatch for Calamba City, Philippines.**

ArangCada connects commuters, tricycle drivers, and local transport administrators
in one booking workflow—from choosing a pickup point to completing a trip.
It is an Android-first academic capstone developed at National University Laguna,
with a web administration console and a browser-based ride-tracking page.

> **Beta / internal testing.** This is a self-funded project intended for donation
> to Calamba City. It is not presented as a City Hall-sponsored or production-ready service.

## What it does

| For | Capabilities |
| --- | --- |
| Commuters | Pickup and destination search, fare previews, ride requests, driver tracking, trip chat, trip history and safety reports |
| Drivers | Availability controls, ride offers, pickup and trip updates, commuter chat and trip records |
| Administrators | Driver verification, transport-area management, dispatch oversight, trip records and safety-report review |
| Shared-link viewers | Browser-based tracking for a shared ride, without installing the mobile app |

The booking flow focuses on **Espesyal (special) trips for 1–4 passengers** in
Calamba. Fare calculation follows the project's documented local fare matrix;
road-routing results support the map and arrival estimates.

**Payments:** cash is the beta payment method. Full wallet and digital-payment
implementation is pending; no payment provider is connected and simulated
balances do not represent real funds.

## How it is built

- **Mobile:** Flutter and Dart, Riverpod, go_router.
- **Admin:** Flutter Web, Riverpod, go_router.
- **Backend:** Supabase Auth, PostgreSQL/PostGIS, Row Level Security, Realtime,
  Storage and Edge Functions.
- **Maps:** MapLibre, MapTiler and OpenStreetMap; openrouteservice for routing,
  with an optional Google Routes integration.
- **Notifications:** Firebase Cloud Messaging.
- **Tracking and public pages:** HTML, CSS and JavaScript.

Connected features require configured services and network access. Local demo
flows use simulated data and do not demonstrate a live backend connection.

## Repository guide

| Path | Contents |
| --- | --- |
| [`apps/mobile`](apps/mobile) | Commuter and driver app, including its tests and setup guide |
| [`apps/admin_web`](apps/admin_web) | Administration console |
| [`apps/track_web`](apps/track_web) | Shared ride-tracking page and Node tests |
| [`apps/web`](apps/web) | Public information and legal pages |
| [`supabase`](supabase) | Database migrations, Edge Functions and database tests |
| [`scripts`](scripts) | Setup and verification utilities |
| [`docs`](docs) | Architecture, service setup and operating references |

## Run the mobile app

Install Flutter with the Dart version required by
[`pubspec.yaml`](apps/mobile/pubspec.yaml), and configure an Android device or emulator.

```sh
cd apps/mobile
flutter pub get
```

Copy [`env.json.example`](apps/mobile/env.json.example) to `env.json` and enter
your own service configuration. For Android push notifications, add your Firebase
project's `google-services.json` at `android/app/google-services.json`.
Connected operation also requires a Supabase project provisioned with the
repository's migrations and matching server-side configuration.

```sh
flutter run --dart-define-from-file=env.json
```

See the component guides for further setup:
[mobile](apps/mobile/README.md) · [admin](apps/admin_web/README.md) ·
[tracking](apps/track_web/README.md) · [public pages](apps/web/README.md).

## Verify changes

From the affected Flutter app directory:

```sh
flutter analyze
flutter test
```

For the tracking page, run `npm test` from `apps/track_web`.
Database checks live in `supabase/tests`; inspect `scripts/run_db_tests.sh`
before use because it rebuilds its target database. Run it only against an
explicitly selected disposable local database.

## Configuration and handover

Recipients must provide their **own service accounts, API keys, billing,
notification configuration and signing credentials**. Personal developer accounts,
service credits and ongoing hosting or support are not included in the source handover.

Keep secrets and real service configuration out of Git. Never place a Supabase
service-role key in a mobile or public web client. Compile-time client keys can
be extracted from a built app; handover builds must use recipient-owned configuration.

- [Mobile handover and acceptance checklist](apps/mobile/HANDOVER.md)
- [Security boundaries](SECURITY.md)
- [System architecture](docs/ARCHITECTURE.md)
- [Fare matrix](docs/LGU_FARE_MATRIX.md)

## AI assistance disclosure

ArangCada's concept, visual direction and final design decisions were led by its
developer. AI assistants were used as development tools to help generate and
refine code, troubleshoot issues, review implementations, and prepare tests and
documentation. The developer directed the work and remains responsible for the
selection, integration and validation of the final project.

## Acknowledgments

ArangCada builds on the open-source libraries and services listed in its
component manifests. Map data is provided by OpenStreetMap contributors, with
map and routing services supplied by the configured providers. Third-party
licenses and required attribution remain applicable.
