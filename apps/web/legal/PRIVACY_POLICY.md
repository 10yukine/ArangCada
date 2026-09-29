# ArangCada Privacy Policy

> **STATUS: Academic Capstone Release · Researched Legal Draft.** Prepared
> for the Calamba City academic pilot pursuant to Republic Act No. 10173 (Data
> Privacy Act of 2012), its Implementing Rules and Regulations, and relevant
> National Privacy Commission (NPC) issuances. If this policy ever disagrees
> with how the app actually handles data, we treat that as an error in this
> document and correct it.

**Applies to:** the ArangCada mobile app (commuter and driver roles) and the
ArangCada LGU/TODA admin web console.

**Prepared by:** ArangCada capstone group (NU Laguna, Department of Computer
Engineering, Section CpE231B), CPTHS120 Capstone Design 1, adviser Dr. Juliet
O. Niega.

**Last updated:** September 2026 · **Effective date:** September 2026 (Academic
Pilot)

**Published at:** [arangcada.app/policy](https://arangcada.app/policy)

---

## TL;DR (plain English)

- ArangCada is a **school capstone project**, not a commercial company. It is
  being tested internally in Calamba City for about three months. It is not
  a public, paid product yet.
- We collect your **location** (to match you with the nearest available
  tricycle and compute your fare), basic **account info** (name, phone,
  role), **driver documents** (license, vehicle papers, photo) if you
  register as a driver, **trip and payment records**, and **SOS/safety
  reports** if you use that feature.
- The only bookable ride is **Special, up to 4 passengers**. You're matched
  to the nearest available verified driver anywhere in Calamba City, not
  just drivers from your pickup's own TODA.
- During a trip you can generate a **live ride-tracking link** to send to
  family or friends — see Section 6a for exactly what it shows and when it
  stops working.
- If you're a **driver**, you're also asked to complete short **feedback
  surveys** about using the app and about the LGU's own manual dispatch
  process (the "pila" system). Those results, and your ISO-quality-testing
  results, are shared with the **Calamba City LGU/TODA office**, usually as
  combined numbers rather than singling you out where possible.
- We do **not sell** your data. We do **not** show ads. We do **not** log
  your full name, phone number, government ID numbers, or your full GPS
  trail in plain system logs.
- Rides are paid **in cash only**, directly to the driver. ArangCada never
  handles your money and does not use any payment provider.
- You have rights under Philippine law (the **Data Privacy Act of 2012, RA
  10173**) to see, correct, or ask us to delete your data, and to complain to
  the **National Privacy Commission (NPC)** if you think we mishandled it.

If any of that sounds wrong for what the app actually does, tell the group —
this document is supposed to describe reality, not the other way around.

---

## 1. Who this document is about

ArangCada has three kinds of users:

| Role | What ArangCada does for/with them |
|---|---|
| Commuter | Books a Special tricycle ride (up to 4 passengers), sees a fare estimate, tracks the assigned driver, can share a live ride-tracking link, can send an SOS report |
| Driver | Registers under a Calamba TODA, uploads verification documents, receives dispatch requests, updates ride status, shares live location while on a trip, completes mandatory in-app feedback |
| LGU/TODA administrator | Approves drivers, manages TODA zones, reviews trips and complaints, monitors dispatch, views evaluation results |

## 2. What we collect

| Category | Examples | Where it lives | Who it's for |
|---|---|---|---|
| Account/profile info | Display name, phone number, role, account status | `profiles` table, Supabase Auth | You, and admins for verification |
| Location data | Live GPS while you have an active ride, pickup/destination points, Calamba service-area checks | `trip_locations` table (active trips only) | Dispatch, geofencing, fare distance |
| Driver verification documents | Driver's license, vehicle OR/CR, profile photo | `driver_documents` table + private Supabase Storage bucket (not public) | LGU/TODA admin review only |
| Trip records | Pickup/destination, ride type (currently always Special), passenger count (1–4), fare amount, status history | `trips` table | You, your matched driver, TODA/LGU admin |
| Ride-tracking link data | An unguessable link code, the trip it points to, when it was created or revoked | `ride_share_links` table | You (the creator); anyone holding the link sees only a limited live view — see Section 6a |
| Payment method | Always cash; the fare is stored with the trip | `trips` table | You, your matched driver, TODA/LGU admin |
| Emergency/safety reports | SOS event, linked ride, location snapshot at time of report | `emergency_reports` table | LGU/TODA admin review |
| Complaints | Commuter or driver complaint text | `complaints` table | LGU/TODA admin review |
| ISO/IEC 25010 evaluation responses | Your ratings/answers comparing the app to the manual dispatch baseline | Evaluation dataset (admin console) | Capstone research + LGU/TODA program review |
| Mandatory driver app-usage feedback | Bilingual five-point Likert responses, collected after a configurable number of completed trips (currently every trip) | Evaluation dataset (admin console) | Capstone research + LGU/TODA program review, reported with per-TODA counts and item means |

We **do not** intentionally collect: government ID numbers beyond what's on
an uploaded driver document image itself, health data, biometric data
(no facial recognition), or precise location from anyone who is not
currently a rider/driver on an active trip.

## 3. How we collect it

- **Directly from you**: registration forms, document uploads, in-app
  feedback surveys, complaint/SOS submissions.
- **Automatically, only during an active ride**: device GPS via the
  `geolocator` package, sent only while a trip is in progress.
- **From LGU/TODA administrators**: approval/rejection decisions, TODA-zone
  assignment.

## 4. Why we use it

- **Dispatch and fare**: match you to the **nearest available verified
  driver within Calamba City** — a server-side proximity search that starts
  at a 1 km radius and widens to 3 km if unmatched — and compute your fare
  using straight-line (Haversine) distance against the LGU-approved fare
  matrix (Calamba City Ordinance No. 743, s. 2022). A separate server-side check confirms your
  pickup and destination are both inside Calamba City; a driver's TODA
  membership no longer restricts which pickups they can be matched to, though
  it is still recorded for LGU/TODA oversight and reporting. There is no
  surge pricing, ever.
- **Driver verification**: confirm you hold a valid license and are
  registered under a legitimate TODA before you can receive ride requests.
- **Safety response**: route SOS reports and complaints to LGU/TODA admins
  for review.
- **Capstone research and LGU program evaluation**: the ISO/IEC 25010
  comparison against manual dispatch, and the mandatory driver app-usage
  survey, exist specifically to measure whether this system is worth
  recommending to the LGU beyond the capstone — this is a required part of
  the underlying academic study, not incidental data collection.

## 5. Legal basis (Republic Act No. 10173, the Data Privacy Act of 2012)

This app operates in the Philippines, so the Data Privacy Act of 2012 (RA
10173) and its Implementing Rules and Regulations govern how we handle your
personal data, under the oversight of the **National Privacy Commission
(NPC)**. Our basis for processing includes:

- **Consent** — you agree to this policy and to specific permissions (e.g.
  location access) when you use the app.
- **Contractual necessity (RA 10173 Sec. 12[b])** — we cannot match you with a
  driver or compute a fare without your pickup location and trip details. For
  drivers, participation in short app-usage and ISO/IEC 25010 evaluations is a
  contractual condition of participation in this academic pilot, explicitly
  accepted upon onboarding.
- **Legal obligation / public function (RA 10173 Sec. 12[c] & [e])** — verifying
  drivers and routing safety reports supports the LGU's regulatory and public
  transport-safety oversight.
- **Legitimate research interest (RA 10173 Sec. 12[f])** — collecting driver
  app feedback directly supports the capstone evaluation comparing digital
  dispatch to the manual "pila" baseline. All academic publications and thesis
  disclosures report only aggregated, de-identified statistical metrics (item
  means and per-TODA distributions) without exposing individual driver
  identities.

Driver's license and vehicle registration images may fall under RA 10173's
definition of **sensitive personal information** once uploaded (government
issued IDs). We apply the Act's higher standard of care to
`driver_documents`: private Storage only, visible solely to the document
owner and authorized LGU/TODA admins, per existing RLS/Storage policy.

## 6. Who can see your data

| Data | Visible to |
|---|---|
| Your profile | You; LGU/TODA admins (for verification/support) |
| Live trip location | You; your matched driver; LGU/TODA admin (active trip only) |
| Driver documents | You (the driver); LGU/TODA admins reviewing verification — never other drivers or commuters |
| Trip/payment history | You; your counterpart on that trip; LGU/TODA admin |
| SOS/complaint reports | LGU/TODA admin reviewers only; never shown publicly, and emergency-contact details are not exposed to unauthorized users |
| ISO 25010 / app-usage feedback | Capstone group (research); LGU/TODA admins, generally as aggregated per-TODA figures rather than individually attributed responses where the sample size allows it |
| Shared ride-tracking link | Anyone you send the link to, for the duration of that one trip — see Section 6a |
| Your mobile number | You; your matched driver during an active trip; LGU/TODA admins; our SMS provider, solely to deliver your verification code (see the Semaphore entry below for its current status) |

### 6a. Ride-tracking links you choose to share

During an active trip you can generate a tracking link and send it to family or
friends. This exists because Calamba City Hall asked for it: so someone can watch
your trip in real time and know you arrived.

You should understand exactly what you are handing out when you send that link.

**Anyone who has the link can open it. No account and no password is required.**
The link contains a long random code that cannot be guessed, but it is not
secret from anyone you forward it to, and they can forward it onward. Only send
it to people you trust.

**What the link shows:**

- the current status of the trip
- the vehicle's live position on a map and the estimated arrival time
- the pickup and destination place names
- the driver's display name and tricycle body number

**What the link does not show:**

- your name, phone number, or email address
- the driver's phone number, address, or verification documents
- any of your past trips, payments, or chat messages
- any stored history of where you have been — only the current position

**It stops working when the trip ends.** The link expires automatically once
the trip is completed or cancelled. It is not a permanent window into your
location. You can also revoke it yourself before the trip ends.

The expiry and the limits above are enforced on our server, not by the app on
your phone, so they cannot be bypassed by modifying the app.

**Third-party processors** (they receive only what's needed to do their job,
not a full copy of your account):

- **Supabase** — hosts our database, authentication, file storage, and
  realtime updates (Auth, Postgres with Row Level Security, Storage,
  Realtime, Edge Functions).
- **MapTiler** and **OpenStreetMap** — receive map tile requests (coordinates
  needed to draw the map), not your identity.
- **openrouteservice** — receives coordinates to compute a route/ETA, not
  your identity.
- **Google Routes API** — an optional route/ETA provider present in the
  codebase, intended to supplement or replace openrouteservice for better
  minor-road coverage in Calamba. If it is ever used, it would receive only
  the two coordinates needed for a route lookup — never your name, ride ID,
  or documents. **Not active, and staying that way for now**: no API key is
  configured, so no request currently reaches Google. The project owner
  confirmed on 4 Sept 2026 that this stays off — Google Routes is a paid API
  and the project has no budget for it during internal testing. Under NPC Circular 2020-03,
  routing requests to a US-headquartered processor would constitute a
  cross-border transfer requiring specific data transfer mechanisms; this
  remains inactive. Active routing continues to be serviced by European
  providers operating under EU GDPR adequacy.
- **Semaphore** (SOMBRA, Inc., Philippines) — designed to receive your mobile
  number and a one-time verification code in order to deliver that code by
  SMS when you register. **Not active for real messages yet**: verification
  currently runs in a development "stub" mode, where the code is written to
  a server-side function log instead of being sent by SMS, so Semaphore does
  not yet receive live traffic. The project owner confirmed on 4 Sept 2026
  that stub mode stays on for now because the project has not purchased
  Semaphore SMS credits — this is a budget decision, not a technical one; the
  provider itself is already chosen. This entry applies in full from the day
  credits are purchased and stub mode is switched off. Semaphore is an
  NPC-registered Philippine domestic processor that retains transmission logs
  and recipient mobile numbers for thirty (30) to ninety (90) days solely for
  carrier delivery status reconciliation and billing verification, after which
  logs are permanently purged. Semaphore does not receive your name, email
  address, location, or trip history.
- **Resend** — receives an invited administrator's email address, and only
  that address, in order to deliver a one-time account-creation link when an
  LGU administrator invites a new LGU or TODA admin through the admin web
  console. This never applies to
  commuters or drivers — only to the small number of LGU/TODA staff being
  added as administrators. **Not active for real messages yet**: the sending
  domain and API key are staged but no real invite has gone out. Resend, Inc.
  processes email dispatch through AWS infrastructure in US-East (N. Virginia)
  under SOC 2 Type II compliance, retaining delivery metadata and recipient
  addresses for thirty (30) days for bounce mitigation and audit logging,
  after which records are deleted. Resend does not receive your name, phone
  number, location, trip history, or password.

### 6b. Physical server infrastructure and cross-border transfers

In compliance with the Data Privacy Act of 2012 and NPC Circular 2020-03:

- **Primary Database & Application Storage (Supabase):** Hosted on Amazon Web
  Services (AWS) in **Singapore (`ap-southeast-1`)**, ensuring regional data
  residency within ASEAN, minimal transit latency to Calamba City, and
  compliance with ISO 27001/SOC 2 standards. All data is encrypted at rest
  using AES-256 and in transit via TLS 1.3.
- **Mapping & Coordinate Processing (MapTiler & openrouteservice/HeiGIT):** Map
  tiles and road network routing queries are processed on server clusters in
  Switzerland and Germany (European Union). Queries transmit only anonymous
  geographic coordinates (latitude and longitude) without personal names,
  account IDs, or device identifiers. Under NPC Advisory Opinion No. 2017-046,
  processing within the EU provides an adequate and comparable standard of
  data protection under the EU General Data Protection Regulation (GDPR).

## 7. How we protect it

- Row Level Security (RLS) is enabled on every table holding user, driver,
  trip, document, complaint, location, or emergency data — the database
  itself enforces who can read or write each row, not just the app's UI.
- Driver documents are stored in **private** Supabase Storage buckets, never
  public.
- We do not write your full name, phone number, government ID, license file
  contents, full GPS trail, or emergency contact details into application
  logs.
- Admin actions that touch sensitive records (approving a driver, editing
  fare data) are recorded in an audit log.
- No system is 100% secure; if we ever detect a data breach likely to harm
  you, we will notify you and the NPC as required by RA 10173 and its breach
  notification rules.

## 8. How long we keep it

In compliance with the Data Privacy Act of 2012 Principle of Proportionality
(RA 10173 Section 11), personal data is retained only for as long as necessary
to fulfill the academic research, dispatch evaluation, and regulatory oversight
purposes:

| Data Category | Retention Schedule | Deletion / Disposal Action |
|---|---|---|
| Account & profile data | Active duration of academic pilot + 6 months post-defense | Permanently purged from Supabase Auth & profiles table |
| Live trip location pings (`trip_locations`) | High-frequency breadcrumbs purged within 48 hours of trip completion | Automatic server cleanup; start/end coordinates retained in trip history |
| Ride-tracking link tokens (`ride_share_links`) | Expire automatically upon trip completion or cancellation, or manual revocation | Token deactivated immediately; record archived for audit |
| Driver verification documents (`driver_documents`) | Duration of driver active verification + 30 days after deactivation or capstone end | File assets permanently purged from private storage bucket |
| Trip and payment records (`trips`, `payments`) | 1 academic year (covering capstone research, evaluation, and defense) | Database rows scrubbed of direct user identifiers |
| SOS & complaint reports | 1 calendar year pursuant to LGU incident recordkeeping standards | Archived or purged per LGU administrative schedule |
| Evaluation & survey responses | Maintained during capstone evaluation; de-identified statistical datasets retained | Fully anonymized; research statistical datasets may be published in thesis papers |

## 9. Payments

Rides are paid **in cash only**, handed directly to the driver when the trip
ends. ArangCada does not process, hold, or transfer money and is not
connected to any payment provider. The only payment information kept is the
fare and the fact that the trip was paid in cash, stored with the trip
record. The fare itself is calculated on the server from the LGU fare
matrix, never trusted to the app alone.

## 10. Sharing with the Calamba City LGU/TODA office

Because this system exists to support the LGU's tricycle dispatch and to
measure whether it should be recommended beyond the capstone, some data is
specifically built to be shared with LGU/TODA administrators, not just kept
internal to the app:

- Driver verification status and documents (for approval decisions).
- Trip, complaint, and SOS records relevant to dispatch oversight and safety.
- **ISO/IEC 25010 evaluation results**, comparing the app against the manual
  "pila" baseline.
- **Mandatory driver app-usage feedback** (bilingual five-point Likert
  survey), reported to LGU/TODA administrators with per-TODA submission
  counts, unique-driver sample progress, and item means — kept separate from
  any optional driver-to-commuter star rating, which is not shared with the
  LGU in the same way.

Only LGU administrators may configure how often the mandatory feedback is
requested; during internal testing that interval is every trip.

## 11. Your rights under RA 10173

You may:

- **Be informed** about how your data is processed (this document).
- **Access** a copy of your personal data that we hold.
- **Object** to processing, and **withdraw consent** where consent is the
  basis for that processing.
- **Correct** inaccurate data.
- **Erase or block** your data under certain conditions (e.g. it's no longer
  needed for the stated purpose).
- **Claim damages** if you suffer harm from a violation of your rights.
- **Data portability** — request your data in a usable electronic format.
- **File a complaint** with the **National Privacy Commission (NPC)** if you
  believe your rights were violated.

To exercise any of these statutory rights during the capstone testing period,
contact our Data Protection Officer / Capstone Privacy Liaison at:
**[privacy@arangcada.app](mailto:privacy@arangcada.app)**. Identity verification is required, and requests
will receive a formal response within fifteen (15) business days.

To delete your account, open **Profile → Settings → Delete account** in the
app, or sign in at **[arangcada.app/delete-account](https://arangcada.app/delete-account)**
if you no longer have the app. Deletion is immediate: your account, profile,
photo, contact details, discount claims, chat messages and voice notes, and
driver records and documents are removed. Trips, ratings, complaints and SOS
reports are kept only for the periods in Section 8, with your name and account
link removed. An account cannot be deleted during an active ride.

## 12. Children's privacy

ArangCada is strictly intended for individuals aged 18 and older. Minors aged
15 to 17 may use the application only with verifiable parental or legal
guardian consent and active supervision. We do not knowingly collect personal
information from children under 15 years of age. If we discover that personal
data of a child under 15 has been collected without parental consent, we will
promptly delete that data and terminate the account.

## 13. Changes to this policy

Because this is an active capstone build, this policy will be revisited
whenever the app's data model, dispatch/matching rule, third-party
provider list, RLS scope, or payment method list changes. Material changes
will be dated and summarized here before the next round of internal testing.
There is currently no in-app mechanism to notify users of changes; the latest
version is always published on this page.

## 14. Contact

**Data controller (for capstone purposes):** ArangCada capstone group,
Section CpE231B, Department of Computer Engineering, National University Laguna.

- **Capstone Adviser:** Dr. Juliet O. Niega
- **Group Legal-Research Contact:** Hernandez, Justin T.
- **Privacy & DPO Inquiries:** [privacy@arangcada.app](mailto:privacy@arangcada.app)
- **General Support Inquiries:** [support@arangcada.app](mailto:support@arangcada.app)
- **Campus Address:** National University Laguna, Km. 53 Pan-Philippine
  Highway, Brgy. Milagrosa, Calamba City, Laguna 4027, Philippines.

**National Privacy Commission (NPC):** For regulatory inquiries, complaints, or
guidance regarding Republic Act No. 10173:

- **Website:** [privacy.gov.ph](https://www.privacy.gov.ph)
- **Complaints & Assistance:** [complaints@privacy.gov.ph](mailto:complaints@privacy.gov.ph) / [info@privacy.gov.ph](mailto:info@privacy.gov.ph)
- **Trunkline / Contact:** +63 (02) 8234-2228
- **Address:** 5th Floor, Delegation Building, Philippine International
  Convention Center (PICC) Complex, Vicente Sotto Avenue, Pasay City, Metro
  Manila 1307, Philippines.
