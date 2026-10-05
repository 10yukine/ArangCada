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

**Last updated:** October 2026 · **Effective date:** September 2026 (Academic
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
- Pilot builds use **Google Maps** for the map and route lines. Place search
  uses Google Places, MapTiler or **LocationIQ**, depending on the build.
  The selected search provider receives what you type; Google receives map
  areas and route coordinates. We do not include your name or account in
  these requests. Trip pickup and destination names and coordinates
  are cleared by an hourly cleanup after **29 days from the ride request**;
  financial and participant records are retained separately.
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
| Driver | Registers under a Calamba TODA, uploads verification documents, receives dispatch requests, updates ride status, shares location while available online and during an assigned trip, completes mandatory in-app feedback |
| LGU/TODA administrator | Approves drivers, manages TODA zones, reviews trips and complaints, monitors dispatch, views evaluation results |

## 2. What we collect

| Category | Examples | Where it lives | Who it's for |
|---|---|---|---|
| Account/profile info | Display name, phone number, role, account status | `profiles` table, Supabase Auth | You, and admins for verification |
| Location data | Device GPS for the Home map and pickup preview, online driver availability, assigned-trip tracking, pickup/destination points and service-area checks | App state; driver location in `driver_availability`; active-trip updates in `trip_locations`; pickup/destination in `trips` | Dispatch, service-area validation, fare distance and tracking |
| Driver verification documents | Driver's license, vehicle OR/CR, profile photo | `driver_documents` table + private Supabase Storage bucket (not public) | LGU/TODA admin review only |
| Trip records | Pickup/destination, ride type (currently always Special), passenger count (1–4), fare amount, status history | `trips` table | You, your matched driver, TODA/LGU admin |
| Ride-tracking link data | An unguessable link code, the trip it points to, when it was created or revoked | `ride_share_links` table | You (the creator); anyone holding the link sees only a limited live view — see Section 6a |
| Payment method | Always cash; the fare is stored with the trip | `trips` table | You, your matched driver, TODA/LGU admin |
| Emergency/safety reports | SOS event, linked ride, location snapshot at time of report | `emergency_reports` table | LGU/TODA admin review |
| Complaints | Commuter or driver complaint text | `complaints` table | LGU/TODA admin review |
| ISO/IEC 25010 evaluation responses | Your ratings/answers comparing the app to the manual dispatch baseline | Evaluation dataset (admin console) | Capstone research + LGU/TODA program review |
| Mandatory driver app-usage feedback | Bilingual five-point Likert responses, collected after a configurable number of completed trips (currently every trip) | Evaluation dataset (admin console) | Capstone research + LGU/TODA program review, reported with per-TODA counts and item means |

We **do not** intentionally collect: government ID numbers beyond what's on
an uploaded driver document image itself, health data or biometric data
(no facial recognition). Location is also used before a trip: Home reads
GPS for the map and pickup preview, and online drivers share availability
coordinates for matching. Device location access requires permission.

## 3. How we collect it

- **Directly from you**: registration forms, document uploads, in-app
  feedback surveys, complaint/SOS submissions.
- **With device location permission**: Home reads GPS for the map and pickup
  preview before a ride. Online drivers send availability coordinates to
  the backend for matching; during an assigned trip they send location
  updates for rider tracking. Map, route and pin-label requests can also
  send coordinates to the configured providers described in Section 6a.
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
- **Cloudflare** (Cloudflare, Inc., United States) — serves our public
  website (arangcada.app), the ride-tracking page and the admin web console
  from its global network. It handles the requests your browser makes to
  them, including your IP address and browser details, in order to deliver
  the pages and protect them from abuse. The account-deletion page uses
  Cloudflare Turnstile to tell people from automated scripts before a
  deletion is attempted. The website and, for now, the admin console also
  load **Cloudflare Web Analytics**, which counts page views and records the
  page address, the referring page, the browser, operating system and device
  type, the country, and page-load timings. It sets no cookies, stores
  nothing on your device, and does not identify or follow individual
  visitors. The ride-tracking page blocks it, because that page's address
  contains your share link. Cloudflare is outside the Philippines; see
  Section 6b.
- **MapTiler** — receives map tile requests for the admin console, tracking
  page and mobile builds using the open map, plus place-search text when
  selected or used as a search fallback and coordinates for pin labels.
  Map data includes **OpenStreetMap** data. We do not send account names,
  ride IDs or verification documents with these requests.
- **openrouteservice** — receives route endpoint coordinates when the app
  uses the open map and routing provider. It is not an automatic routing
  fallback on the Google map. We do not send account identity with routes.
- **LocationIQ** — builds configured for LocationIQ send what you type in
  place search to our own server, which adds a fixed search box around
  Calamba and passes the text to LocationIQ. LocationIQ receives the text
  and our server's address, not your phone's. One earlier build, alpha.3
  build 4046, sent the text to LocationIQ straight from the phone, so
  LocationIQ also received that phone's IP address. These builds do not use
  Google Places for search. Pin labels still use MapTiler; map and route
  requests remain with their configured providers. We do not send your
  account, ride ID, phone number or documents to LocationIQ. To stay within
  LocationIQ's limits we count how many searches each account makes per day;
  we do not store what was searched. LocationIQ records API usage, request
  timestamps and IP addresses under its
  [privacy policy](https://locationiq.com/privacy). If LocationIQ search is
  unavailable, the app offers map pin selection rather than automatically
  calling another place-search provider.
- **Google Maps Platform** (Google LLC, United States) — used by pilot
  builds of the mobile app for the in-app map (Maps SDK for Android), road
  route lines (Routes API), and place search when configured for Google
  Places (Places API).
  Google receives the map area being viewed, the two coordinates of a route
  lookup, and the text you type into place search, plus device and usage
  information its map SDK collects under Google's own privacy policy. It never
  receives your name, account, ride ID, phone number or documents from us.
  In Google Places builds, unavailable place search may use MapTiler. If Google
  routing is unavailable while the Google map is selected, the route line
  is unavailable; the app does not send that request to openrouteservice.
  Builds configured for the open map use MapTiler and openrouteservice.
  Fare calculation does not use either provider's route distance.
  Google is outside the Philippines, so using it is a cross-border
  transfer; we remain accountable for it under Section 21 of RA 10173 and
  send Google only what each request needs. Google Maps content is not
  shown in the admin console or on the ride-tracking page.
- **Semaphore** (SOMBRA, Inc., Philippines) — designed to receive your mobile
  number and a one-time verification code in order to deliver that code by
  SMS when live SMS delivery is enabled. The current alpha testing mode
  delivers the code to the account's email through Resend instead; Semaphore
  is not used for those deliveries. Email delivery does not prove ownership
  of the supplied mobile number. The app does not intentionally log the code.
- **Resend** — receives recipient email addresses and message content for
  administrator invitations and alpha verification-code emails. The code is
  included in the email subject and body. These deliveries can apply to
  commuters and drivers as well as administrators. The verification email
  does not include your phone number, precise location, trip history or
  password. Real SMS ownership verification remains a separate pilot gate.
  Resend also delivers the email-confirmation message: after your number is
  verified, and when you ask from the Profile screen, we email a single-use
  link to the address on your account. We keep a scrambled copy of that link
  (not the link itself), the address it was sent to and whether it was used,
  and we record the date you confirmed. Changing your email clears that date.

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
- **Google Maps Platform (pilot builds):** Map, route and place-search
  requests are processed on Google's global infrastructure, including outside
  the Philippines and the EU, as described in Section 6.
- **Place search in LocationIQ builds (LocationIQ):** Search text is sent to
  LocationIQ, operated by Unwired Labs (India) Pvt. Ltd., and processed on its
  servers outside the Philippines; it lists data centres in the United States
  and the European Union. This is a cross-border transfer, as described in
  Section 6.
- **Website, ride-tracking page and admin console (Cloudflare):** These are
  served from Cloudflare's global network, including locations outside the
  Philippines, as described in Section 6.

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
| Live trip location pings (`trip_locations`) | High-frequency breadcrumbs purged within 48 hours of trip completion | Automatic server cleanup; trip pickup/destination fields follow the next row |
| Trip pickup and destination (names and coordinates) | Cleared after 29 days from the ride request, regardless of trip status | Hourly cleanup clears coordinates and replaces labels with "Pickup" and "Destination"; financial and participant records remain |
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
