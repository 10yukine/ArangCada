# SECURITY.md — ArangCada Supabase Security Checklist
*Use this before every demo build, panel test, and Supabase migration.*

---

## Security Goal

ArangCada handles commuter accounts, driver verification documents, vehicle identifiers, ride records, live location, payment references, complaints, and emergency reports. The system must follow data minimization and access control practices suitable for the Philippine Data Privacy Act and a public transport capstone.

The current target is internal testing only. Do not expose the app, admin dashboard, Supabase data, Storage objects, or development map/routing credentials through a public deployment.

---

## Supabase Auth

- [ ] Supabase Auth is the only auth provider for MVP
- [ ] Clerk is not installed unless explicitly approved
- [ ] New auth users get exactly one `profiles` row
- [ ] Valid roles are limited to `commuter`, `driver`, `admin`
- [ ] Driver accounts default to `pending`, not `approved`
- [ ] Suspended users cannot create or accept rides
- [ ] Admin creation is controlled through a safe seed script or manual Supabase dashboard action, not public sign up
- [ ] Auth state is cleared on logout
- [ ] No password, OTP, refresh token, or private credential is logged

---

## Key and Secret Safety

- [ ] Supabase URL and anon key are the only Supabase values allowed in Flutter or public web code
- [ ] Supabase service role key is never placed in Flutter, web dashboard, Git, screenshots, or logs
- [ ] MapTiler and openrouteservice keys use the narrowest available restrictions and free-tier quotas
- [ ] MapLibre contains no secret; provider style URLs and tokens are treated as configuration, not committed credentials
- [ ] `.env`, `.env.local`, and key files are ignored by Git
- [ ] Edge Function secrets are stored in Supabase secrets, not hardcoded

---

## Row Level Security Baseline

Every sensitive table must have RLS enabled.

- [ ] `profiles`
- [ ] `driver_profiles`
- [ ] `vehicles`
- [ ] `toda_zones`
- [ ] `fare_matrix`
- [ ] `driver_availability`
- [ ] `rides`
- [ ] `ride_locations`
- [ ] `payments`
- [ ] `emergency_reports`
- [ ] `complaints`
- [ ] `admin_audit_logs`

Minimum rules:

- [ ] Commuters can read and update only their own profile
- [ ] Drivers can read and update only their own driver profile, except approval fields
- [ ] Drivers cannot approve themselves
- [ ] Commuters can read only their own rides
- [ ] Drivers can read only rides assigned to them or eligible minimal dispatch request data
- [ ] Admins can read records needed for governance, but admin access is still logged
- [ ] Public users cannot read driver documents, live locations, emergency reports, or payment proof

---

## Suggested RLS Patterns

Use these patterns as starting points, then adapt per migration.

```sql
-- Profiles: user can read own profile
create policy "profiles_select_own"
on public.profiles
for select
to authenticated
using (id = auth.uid());

-- Rides: commuter can read own ride
create policy "rides_select_rider_own"
on public.rides
for select
to authenticated
using (rider_id = auth.uid());

-- Rides: assigned driver can read assigned ride
create policy "rides_select_assigned_driver"
on public.rides
for select
to authenticated
using (driver_id = auth.uid());
```

Admin policies must reference a trusted profile role check or secured function. Do not rely on Flutter hiding admin screens.

---

## Storage Buckets

### Driver Documents

- [ ] Bucket is private
- [ ] Drivers can upload only inside their own folder path
- [ ] Drivers can read only their own uploaded documents
- [ ] Admins can read documents for verification
- [ ] Public access is disabled

### Payment Proof

- [ ] Bucket is private
- [ ] Commuter can upload proof only for their own ride
- [ ] Assigned driver and authorized admin can view payment status only when needed
- [ ] Raw financial account details are not stored

All driver-document and payment-proof buckets remain private. Access uses authenticated, short-lived URLs or authorized downloads; never public bucket URLs.

---

## Map and Routing Privacy

- [ ] MapLibre is only the client renderer and never receives Supabase service-role credentials or unrestricted ride records
- [ ] MapTiler receives only the tile/style requests needed to draw the map
- [ ] openrouteservice receives only the coordinates needed for the current route lookup; do not attach names, phone numbers, ride IDs, or document URLs
- [ ] Point-in-Polygon TODA authorization and LGU fare decisions remain in trusted project logic, not in a third-party map response
- [ ] Development keys are rotated if exposed and are never reused as future production credentials

---

## Trusted Backend Logic

Use Supabase Edge Functions or secured SQL RPC for these operations:

- [ ] Final fare computation
- [ ] Driver assignment
- [ ] Driver approval or suspension
- [ ] Ride cancellation rules
- [ ] SOS report creation and notification routing
- [ ] Fare matrix changes
- [ ] Admin audit logging

The Flutter app may request these actions, but must not be the final authority.

---

## Location Privacy

- [ ] Live driver location is visible only during eligible states
- [ ] Active commuter can see only assigned driver location
- [ ] Driver can see only relevant pickup and destination details for assigned rides
- [ ] Completed ride route traces are restricted to participant users and authorized admins
- [ ] GPS trail retention is limited to what the capstone needs
- [ ] SOS stores a location snapshot, not unnecessary continuous private tracking beyond the active ride

---

## Fare and Payment Safety

- [ ] No surge pricing
- [ ] Fare matrix changes require admin role
- [ ] Fare preview and final fare are compared during testing
- [ ] Final fare is computed through trusted logic
- [ ] Payment methods are limited to `cash`, `gcash`, `qr_transfer` for MVP
- [ ] No raw card numbers
- [ ] No fake Stripe or external payment gateway unless explicitly requested
- [ ] QR payment proof is private

---

## Input Validation

- [ ] Coordinates must be valid latitude and longitude values
- [ ] Pickup and dropoff must pass Calamba or TODA boundary rules
- [ ] Ride type must be `special` or `pooling`
- [ ] Driver status must be approved before accepting rides
- [ ] Uploaded files must be limited by size and type
- [ ] Phone numbers and names must be normalized where needed
- [ ] Complaint text must have length limits
- [ ] SOS reason text must have length limits

---

## Realtime Safety

- [ ] Realtime is enabled only on tables that need it
- [ ] Realtime payloads do not expose private fields to unauthorized subscribers
- [ ] RLS policies are tested with Realtime subscriptions
- [ ] Driver availability updates are throttled or paced to reduce cost and noise
- [ ] Location updates stop after ride completion or cancellation

---

## Logging and Audit

- [ ] No full name, phone, ID number, license number, exact GPS trail, emergency contact, or uploaded document URL in logs
- [ ] Admin actions write to `admin_audit_logs`
- [ ] Driver approval, suspension, fare matrix update, complaint status update, and emergency report review are audited
- [ ] Debug logs are removed or reduced before demo build

---

## Manual Security Tests

Run these with separate commuter, driver, and admin accounts.

- [ ] Commuter A cannot read Commuter B's ride
- [ ] Driver A cannot read Driver B's documents
- [ ] Pending driver cannot go online
- [ ] Pending driver cannot accept a ride
- [ ] Driver cannot approve their own account
- [ ] Commuter cannot edit fare matrix
- [ ] Commuter cannot read emergency reports of other users
- [ ] Public user cannot read private Storage files
- [ ] User cannot create ride outside allowed boundary
- [ ] User cannot mark another user's ride as completed

---

## Pre Demo Checklist

- [ ] RLS enabled on all sensitive tables
- [ ] Storage buckets private
- [ ] Service role key absent from repo
- [ ] MapTiler and openrouteservice keys restricted and absent from Git
- [ ] No public deployment or public Storage buckets
- [ ] Test accounts prepared
- [ ] Demo data does not contain real private documents
- [ ] Emergency demo uses mock contacts or safe placeholder data
- [ ] Backup demo video prepared in case internet or GPS fails

---

## Agent and Wiki Privacy

- [ ] Do not paste Supabase service role keys, MapTiler/openrouteservice unrestricted keys, `.env` contents, or real private records into Claude Code, Codex, or the wiki.
- [ ] Keep `wiki/raw/` sanitized. No real driver documents, license IDs, emergency contacts, or private GPS trails.
- [ ] Codex and Claude Code must not run destructive commands without explicit approval.
- [ ] Handoff logs must describe files and state, not private user data.
- [ ] If using screenshots or transcripts as sources, remove personal information before ingestion.
