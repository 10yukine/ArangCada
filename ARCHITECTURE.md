# Architecture

ArangCada has a Flutter mobile app for commuters and drivers, a Flutter Web
administration console, and static public and ride-tracking pages. Connected
clients use Supabase for authentication, data and trusted operations.

## Components

| Component | Responsibility |
| --- | --- |
| `apps/mobile` | Role-based navigation, booking, driver workflows, maps and trip communication |
| `apps/admin_web` | Driver administration, dispatch oversight and operational records |
| `apps/track_web` | Limited tracking view for a shared ride link |
| `apps/web` | Public information and legal pages |
| `supabase/migrations` | Versioned schema, access policies and database functions |
| `supabase/functions` | Server integrations, invitations and notification delivery |

The Flutter apps use Riverpod for state and repositories, and go_router for
navigation. Mobile map rendering uses MapLibre, or the Google Maps SDK when its key is
set (required before Google Routes is used); configured providers supply
map tiles, geocoding and road routes. Firebase Messaging delivers push messages.

## Trust boundaries

Supabase Auth identifies connected users. Database policies and server functions
control role, account status, record ownership and administrator scope. Client
navigation and locally calculated fare previews do not authorize operations.
The backend owns final fares, assignment and trip state transitions.

Private documents use controlled Storage access. Shared ride links expose a
limited tracking view through the backend. See [SECURITY.md](SECURITY.md) for
credential handling, access requirements and verification expectations.

## Configuration and deployment

Each Flutter app owns its dependency manifest and tests. Client configuration is
provided separately from source; privileged credentials belong on the server.
The web apps have individual Cloudflare Workers static-assets configurations.
Legal HTML is generated from `apps/web/legal/` by `scripts/render_legal_html.py`.

Local demo flows use simulated data. Connected acceptance testing requires the
matching schema, services and accounts. Follow the component READMEs and
[mobile handover guide](apps/mobile/HANDOVER.md) for setup.
