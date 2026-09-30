# Mobile handover

ArangCada is a self-funded academic capstone intended for donation to Calamba
City. City Hall sponsorship is not assumed. The source handover does not include
the developer's personal accounts, credentials, service credits, or ongoing
hosting and support.

## Recipient-owned services

| Service | Recipient supplies |
| --- | --- |
| Supabase | A project with this repository's migration chain, Auth configuration, private Storage, RLS, Edge Functions and server secrets |
| MapTiler | Their own map and geocoding key, restrictions and usage budget |
| openrouteservice | Their own routing key and plan suitable for the intended use |
| Google Routes (optional) | Their own restricted API key and billing account, or leave it blank. Only used when `GOOGLE_MAPS_API_KEY` is also set |
| Google Maps SDK (optional) | `GOOGLE_MAPS_API_KEY`, restricted to the Android package and signing SHA-1. Replaces the MapTiler map; Google's terms forbid Routes results on a non-Google map |
| Google Places (optional) | `GOOGLE_PLACES_API_KEY` for Places API (New), restricted to that API with a daily quota. Only used with the Google map; MapTiler stays the fallback. Trip places are purged after 30 days by `purge_trip_places()` |
| Firebase Messaging | Their own Firebase project, Android registration and push sender configuration |
| SMS/email | Their own providers and server-side credentials for authentication and notifications |
| Public pages and tracking | Their own hosting/domain configuration; update mobile legal links and backend tracking URLs before acceptance |
| Android distribution | Their own signing/upload key and distribution account |

1. Copy `env.json.example` to the ignored `env.json`; enter only recipient values.
   Never put service-role keys, account passwords or server secrets in the app.
2. Register `ph.calamba.arangcada` in the recipient Firebase project and place its
   configuration at `android/app/google-services.json`. Configure the matching
   backend push sender using recipient credentials.
3. Provision the backend using the repository's existing migration workflow.
   Create fresh recipient administrators and test accounts. Do not copy personal
   sessions, private driver documents or development database dumps.
4. Run `flutter pub get`, `flutter analyze` and `flutter test`. Build with
   `flutter build apk --dart-define-from-file=env.json` for acceptance testing.
   Android currently uses debug signing for release builds; configure recipient
   signing before distribution.
5. Verify registration/login, map/search, cash booking, dispatch, trip completion,
   chat and notifications against the recipient services on physical devices.

Wallet top-ups and digital payments are disabled during beta testing, pending
full implementation. Cash booking remains available. No payment provider is
connected; simulated balances are not money.

## Source package boundary

Deliver a reviewed source snapshot, not the owner's working directory or `.git`
history. Exclude personal configuration, signing keys, builds/APKs, logs,
screenshots, device dumps and local AI notes. Keep source, migrations, dependency
manifests, tests, setup templates, required licenses and operating instructions.
Git ignore rules do not remove anything from past commits or existing copies.

Compile-time values can be extracted from an APK even when the JSON file is
absent. Rebuild using recipient keys; do not hand over an owner-configured APK as
the recipient's operational build. Restrict client keys and keep privileged
credentials on the server. Rotate any credential previously exposed separately.

Confirm the donation's deliverables and any separately paid setup, training,
maintenance or hosting in writing before promising ongoing work. This document
does not establish intellectual-property ownership or license terms.
