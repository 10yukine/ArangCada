# Security policy

ArangCada handles account information, driver verification documents, vehicle
records, trip locations, chat and safety reports. Protecting this data and the
credentials used to operate the project is part of every release and handover.

**Status:** academic capstone in beta/internal testing. This document defines
security requirements and verification steps; it is not evidence of a completed
security audit, production readiness or legal compliance. Deployed settings must
be checked separately from repository code.

## Report a vulnerability

Contact the repository maintainer privately through an established project
communication channel. Do not put credentials, personal records, usable tracking
links or exploit details in public issues or discussions. If no private channel
is available, request one without including sensitive details.

Include the affected component/version, expected and observed behavior,
reproduction steps using synthetic accounts, and a redacted screenshot or log
if needed. Do not access another person's records to demonstrate a finding.
Testing must stay within systems and accounts you are authorized to use.

Reports are handled as maintainer availability permits. No response-time or
security-support guarantee is currently offered for this beta.

## Credentials and service ownership

| Material | Required handling |
| --- | --- |
| Supabase project URL and publishable/anon key | Client configuration; access must still be enforced by backend authorization and RLS |
| MapTiler, openrouteservice and optional Google Routes and Google Maps SDK client keys | Separate keys per environment, provider-supported restrictions, quotas and usage monitoring; assume shipped values are extractable |
| Supabase service-role/secret keys, provider account tokens, webhook secrets and Firebase service-account credentials | Server or operator environment only; never mobile/web code, public configuration or Git |
| Passwords, OTPs, access/refresh tokens and recovery codes | Never commit, log, paste into AI conversations or include in screenshots or reports |
| Android signing keys and passwords | Owner-controlled secure storage and backup; exclude from source packages and logs |

`env.json`, `.env` files, Firebase client configuration and signing material must
remain ignored. Commit only templates without real values. Ignoring a path does
not remove an already tracked file, past commits, uploaded artifacts or other
copies. Check the exact staged files before pushing.

`--dart-define-from-file` does not make embedded values secret. Obfuscation and a
private repository are not substitutes for authorization or key restrictions.
Firebase client configuration identifies the client project; it must never be
confused with privileged Firebase service-account credentials.

The donation does not transfer the developer's personal logins, service credits,
billing accounts or ongoing operating costs. Recipients must provision their own
services and rebuild with their own configuration. See the
[handover checklist](apps/mobile/HANDOVER.md).

## Authentication and authorization

- Supabase Auth handles connected user authentication. Firebase Messaging is
  used for push transport. Local demo accounts represent simulated users and
  must not gain access to live records or administrative operations.
- Resolve roles, approval status, suspension and administrator scope from
  trusted server-side records. Do not trust client-selected roles, user-editable
  metadata or hidden navigation controls as authorization.
- Restrict administrator creation and invitations to authorized operators.
  Validate invitation tokens, expiration, intended recipient and reuse rules.
- Enforce account and trip permissions on every RPC, table, Storage operation,
  Edge Function and Realtime subscription that exposes sensitive data.
- Clear user-specific state on sign-out and account switching. Verify session
  restoration and push-token reassignment do not expose the previous user's data.
- Let the authentication SDK manage sessions; do not copy passwords or tokens
  into application caches. Review the SDK's configured persistence and device
  storage separately; encrypted session storage is not asserted by this policy.

## Database and server functions

Enable RLS and least-privilege grants for every exposed table containing private
data. Use the existing [migrations](supabase/migrations) and
[database tests](supabase/tests) as the implementation reference, rather than
copying generic policy snippets into a live database.

Required boundaries:

- Commuters access their own records and the minimum information needed for
  their trips. Drivers access eligible offers and their assigned trips.
- Drivers cannot approve themselves, change privileges or bypass suspension.
  Administrative reads and writes respect the caller's authorized scope.
- The server owns final fares, assignment, state transitions, cancellations,
  approvals and audit records. Client previews are not authoritative.
- Security-definer functions validate the caller and inputs, constrain object
  resolution, and expose only the execute permissions they require.
- Validate coordinates, service-area eligibility, passenger counts, ride types,
  text lengths and permitted state transitions at the backend boundary.

An Edge Function with `verify_jwt = false` still needs the appropriate in-function
authorization. Some configured endpoints use signed webhooks, a shared secret or
an invitation token rather than a signed-in user's JWT. Review each handler with
[`supabase/config.toml`](supabase/config.toml); do not enable or disable gateway
JWT checks indiscriminately. A valid JWT alone does not establish admin authority.

## Documents, locations and shared links

- Keep verification documents and other private uploads in private Storage.
  Check ownership, administrator scope, allowed file types and size limits.
  Use authorized downloads or short-lived signed URLs; treat those URLs as
  sensitive while valid.
- Restrict location access to the participants, eligible trip states and
  authorized operational roles. Collect only what the active workflow needs.
- A ride-sharing link grants access to a limited tracking view. Treat its token
  as a bearer credential: enforce its scope, expiry and revocation on the
  server, and keep it out of analytics, screenshots and logs.
- Shared tracking must not expose private documents, full profiles, chat,
  emergency reports or unrelated trip histories.
- Define and verify retention/deletion periods for documents, chat, GPS records,
  notifications and backups before operational handover. Do not assume that
  hiding data in the UI deletes it from the backend.

## Third-party requests and local data

MapTiler receives map/style requests and geocoding search text or coordinates.
openrouteservice and optional Google Routes receive coordinates needed for route
lookups. Do not attach names, phone numbers, trip IDs, documents or authentication
tokens to those requests. Keep required provider attribution visible.

Push, SMS and email providers receive the data required to deliver their
messages. Minimize message content, especially on lock screens. Protect push
tokens and ensure server-side recipient selection follows account permissions.

Application caches must hold only the minimum display data needed. Do not treat
Hive or any local cache as a vault for credentials, private documents or raw
financial details. Test cache isolation, logout cleanup and behavior on shared
devices. Avoid logging request URLs or SDK errors that may contain tokens,
provider keys or personal data.

## Payments and beta boundaries

Cash is the beta payment method. Wallet top-ups and digital payments remain
outside the supported beta flow pending full implementation. Simulated balances
are not customer funds, and no payment provider is connected.

Do not collect card details, banking passwords or payment-provider credentials.
Enabling digital payments requires a separate implementation and security review,
including server-side verification and protection against duplicate transactions.
A wallet UI or payment screenshot is not proof that money moved.

## Exposure response

If a credential or private record is exposed:

1. Revoke or rotate the affected credential at its provider; removing text from
   Git is not enough. Revoke affected sessions or shared links where applicable.
2. Identify affected environments, accounts, artifacts and access. Review provider
   usage and audit logs without copying sensitive records into the incident note.
3. Replace configuration securely and rebuild/redeploy affected clients or
   services through the authorized release process.
4. Remove exposed material from current files and coordinate any necessary
   history/artifact cleanup. Existing clones and downloaded builds may retain it.
5. Record the scope, containment and follow-up privately. Escalate personal-data
   exposure to the responsible project or recipient contact for assessment.

## Verification before release or handover

Run checks with synthetic data and separate commuter, driver and administrator
accounts. A passing checklist applies only to the environment and build tested.

- [ ] Scan staged source and delivery artifacts for credentials and personal data.
- [ ] Confirm recipient-owned services, restricted client keys and appropriate signing.
- [ ] Confirm commuter A cannot access commuter B's trips, chat or safety reports.
- [ ] Confirm drivers cannot read another driver's documents or approve themselves.
- [ ] Confirm pending/suspended drivers cannot accept rides or bypass restrictions.
- [ ] Test unauthorized RPC calls and administrator scope with direct requests.
- [ ] Confirm private Storage and Realtime access across accounts and anonymous users.
- [ ] Test shared-link expiry, revocation and minimal response fields.
- [ ] Test sign-out, account switching, restored sessions and notification recipients.
- [ ] Confirm cash booking works and unsupported digital payment paths stay blocked.
- [ ] Check logs, screenshots, exports and backups for sensitive information.
- [ ] Record remaining findings and acceptance results before operational use.

Use relevant existing Flutter, tracking-page, Edge Function and database tests.
[`scripts/run_db_tests.sh`](scripts/run_db_tests.sh) rebuilds its target database:
inspect it first and use only an explicitly identified disposable local database.
A request for local verification does not authorize tests against live data.
