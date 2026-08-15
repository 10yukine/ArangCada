# ArangCada mobile demo

ArangCada is an Android-first academic capstone prototype for TODA-anchored tricycle hailing and dispatch in Calamba City, Philippines. This Flutter app demonstrates the commuter and driver journeys with deterministic local data and works in aeroplane mode. It is an internal defence build, not a public transport, payment, or emergency-response service.

## Demo accounts

Both accounts use the password `demo1234`.

| Role | Email | Demo identity |
| --- | --- | --- |
| Commuter | `commuter@arangcada.demo` | Joshua Adia |
| Driver | `driver@arangcada.demo` | Marco Dela Cruz, Tricycle 024, Calamba TODA |

The login-screen chips fill these credentials for a quick live demonstration.

## Architecture

The app uses Flutter and Dart with Riverpod for dependency injection and state access, `go_router` for guarded commuter and driver navigation, and Hive for local demo bootstrap/cache storage. Feature screens live under `lib/features`, domain models and the ordinance fare implementation under `lib/domain`, replaceable repository contracts under `lib/data/repositories`, and their offline implementations under `lib/data/mock`.

All mock repositories share one `DemoState`, which prevents the wallet, authentication session, and active booking from drifting apart. Fare calculation is isolated from ETA and routing. The painted Calamba map is a local `CustomPainter` surface and requires no tile or routing network call.

The app starts in demo mode when production configuration is absent. Supabase initialization is optional and never blocks the offline experience.

## Run locally

From `apps/mobile`:

```powershell
flutter pub get
flutter run
```

No API key is required for the offline demo. Do not use or commit a service-role key, payment secret, or private environment file.

Run the quality checks with:

```powershell
flutter analyze
flutter test
```

## Build the Samsung A32 APK

Build split release APKs so the arm64 device receives only its ABI artifact:

```powershell
flutter build apk --release --split-per-abi
```

Install `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` on the Samsung SM-A325F. This internal demo uses Flutter's default debug signing unless a separate signing setup is deliberately supplied; an older install signed with another certificate may need to be uninstalled before installation.

## Mock and production boundaries

| Capability | This demo | Later production integration |
| --- | --- | --- |
| Authentication and profiles | Local demo accounts | Supabase Auth and `profiles` with RLS |
| Fare and TODA rules | Local, pinned ordinance data for offline demonstration | Trusted Supabase SQL RPC/Edge Function; the client consumes the result and does not reimplement authority |
| Dispatch, trip status, and driver availability | Deterministic in-memory demo state | Supabase PostgreSQL, PostGIS, Realtime, and preconditioned RPC/Edge Function actions |
| Map | Hand-painted illustrative map with no OSM data | MapLibre rendering, MapTiler tiles, and OpenStreetMap-derived map data |
| Routing and ETA | Static demo route and fallback labels | openrouteservice for display routing plus a replaceable ETA service; neither determines fare |
| Location | Seeded Calamba demo coordinates | Android fused location through `geolocator` |
| Wallet and payments | Simulated balance and synthetic `DEMO-` references; no funds move | A regulated payment provider behind the payment repository seam |
| Notifications | Mock in-app notification cards | A later push/in-app notification adapter |

Supabase plugs into the repository/provider layer. Trusted fare, geofence, dispatch, safety, and approval actions belong in SQL RPCs or Edge Functions with RLS and status preconditions. openrouteservice plugs into a routing repository and remains display-only. A payment provider plugs into the payment repository; its identifiers must remain provider-owned and synthetic identifiers must stay clearly marked in demo mode.

## openrouteservice configuration and limits

Supply an openrouteservice key at compile/run time, never in source:

```powershell
flutter run --dart-define=ORS_API_KEY=your_key_here
```

The same `--dart-define=ORS_API_KEY=...` form can be appended to the APK build command. `AppConfig` reads it with `String.fromEnvironment`; the offline demo continues when it is absent.

A production routing adapter must use one in-flight request, debounce endpoint changes, and reuse a coordinate-keyed cache when endpoints have not materially moved. HTTP `429` means the minutely limit was reached: serve a cached or demo route with a friendly message and do not create a retry storm. HTTP `403` means the daily quota or authorization is unavailable: stop retrying for the session and fall back to the offline route. Timeouts use bounded backoff and must never block booking or affect the billed Haversine distance.

Use of the HeiGIT Collaborative plan is limited to this non-commercial academic capstone context and remains subject to the plan's current terms. No endorsement by HeiGIT is implied.

## Attribution and disclosures

The offline painted map is labelled `Demo map · illustrative, not to scale`. It contains no OpenStreetMap data and displays no live openrouteservice route.

When the production map stack is displayed, retain these disclosures:

- Map data © OpenStreetMap contributors under the Open Database License (ODbL).
- Tiles by MapTiler.
- Routing by openrouteservice / HeiGIT.
- No endorsement by HeiGIT is implied.

Apple Sign-In is deliberately excluded. This Android-first internal MVP uses email and password only; there is no Apple button, dependency, or code path.

ArangCada does not hold or custody customer funds. The on-device balance is simulated and every demo top-up/payment states that no funds moved. In a production model, balances and transfers are held and processed by the payment provider, not by ArangCada.
