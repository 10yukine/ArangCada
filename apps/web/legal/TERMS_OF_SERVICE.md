# ArangCada Terms of Service

> **STATUS: Academic Capstone Release · Researched Legal Draft.** Prepared
> for the Calamba City academic pilot pursuant to Philippine Law (RA 8792,
> RA 10173, RA 6809, and Calamba City Ordinance No. 743, s. 2022). Emergency
> hotline numbers in Section 7 remain pending official Calamba City Hall
> release. Read alongside the [Privacy Policy](/policy), which this document
> incorporates by reference for all data-handling questions.

**Applies to:** the ArangCada mobile app (commuter and driver roles) and the
ArangCada LGU/TODA admin web console.

**Prepared by:** ArangCada capstone group (NU Laguna, Department of Computer
Engineering, Section CpE231B), CPTHS120 Capstone Design 1, adviser Dr. Juliet
O. Niega.

**Last updated:** September 2026 · **Effective date:** September 2026 (Academic
Pilot)

**Published at:** [arangcada.app/terms](https://arangcada.app/terms)

---

## TL;DR (plain English)

- ArangCada is a **3-month academic capstone project**, currently in
  **internal testing only**. It is not a launched commercial product, and
  using it does not create a commercial contract or guarantee of service.
- The app only works for **tricycle dispatch within Calamba City** (a small,
  clearly-labeled exception exists for developer test accounts in Cabuyao's
  SJVTODA — it is not a public service-area expansion).
- The only bookable ride is **Special ("Espesyal"), up to 4 passengers, one
  flat fare per trip**. You're matched to the **nearest available verified
  driver city-wide**, not just drivers from your pickup's own TODA — search
  starts at 1 km and widens to 3 km if needed.
- Fares are computed **by the server**, using straight-line distance and the
  official Calamba City fare ordinance — never a surprise "surge" price.
- If you're a **driver**, you must be verified (license, TODA membership,
  vehicle documents) by an LGU/TODA administrator before you can accept
  rides, and you are required to complete short in-app feedback surveys.
- During a trip you can **share a live ride-tracking link** with family or
  friends — no account is needed to view it, and it stops working once the
  trip ends. See the Privacy Policy for exactly what it shows.
- The in-app **SOS button** notifies our administrators — it is **not** a
  replacement for calling local emergency services directly.
- Because this is a student project, there is **no commercial warranty or
  guaranteed uptime**, and rides are paid in cash only.

---

## 1. Acceptance of these terms

By creating an account or using ArangCada, you agree to these Terms of
Service and to the [Privacy Policy](/policy). ArangCada is presented here as
an **Academic Pilot & Informed Consent Platform** under Republic Act No. 8792
(Electronic Commerce Act of 2000), developed by computer engineering students
at National University Laguna for academic research and software prototyping.
ArangCada is **not** a licensed Transport Network Company (TNC) or Common
Carrier under the Land Transportation Franchising and Regulatory Board (LTFRB)
or Department of Transportation (DOTr). Participation in this pilot is voluntary.
All tricycle transportation services are rendered independently by licensed
TODA operators franchised under the City Government of Calamba. By using the
service, you acknowledge the experimental, non-commercial nature of this
academic pilot and give informed consent to participate under these terms.

## 2. Eligibility

- **Commuters**: must be at least 18 years of age (the age of majority under
  Republic Act No. 6809). Minors aged 15 to 17 may only register and use the
  application with the explicit consent and supervision of a parent or legal
  guardian who agrees to be bound by these terms. Children under 15 years of
  age are strictly prohibited from creating an account.
- **Drivers**: must hold a valid Philippine driver's license appropriate to
  a tricycle, be a member in good standing of a recognized Calamba City TODA,
  and complete the in-app verification process (document upload, LGU/TODA
  admin approval) before receiving ride requests.
- **Service area**: Calamba City only. A separate, clearly-labeled,
  server-enforced exception exists solely for explicitly marked
  developer-test accounts operating under Cabuyao's SJVTODA; this is a
  testing accommodation, not a public expansion of the service area.

## 3. Description of the service

ArangCada digitizes the manual tricycle "pila" (queue) process. It offers:

- **Special** bookings only ("Espesyal na Byahe" — up to 4 passengers, one
  flat fare per trip), matched to the **nearest available verified driver
  within Calamba City**. Driver search starts at a 1 km radius and widens to
  3 km if unmatched. A driver's TODA membership no longer restricts which
  pickups they can be dispatched to — the pickup's TODA is still recorded for
  LGU/TODA oversight and reporting, but it is not a matching boundary.
  **Pooling ("Regular na Byahe") is not currently offered to commuters** —
  its fare figures remain in the system only as the ordinance's own record
- A fare estimate and a final fare, both computed using Haversine distance
  against the LGU-approved fare matrix (Calamba City Ordinance No. 743, s.
  2022). **There is no surge pricing.** Final
  fare computation always happens server-side; the app only ever previews it.
- Driver registration, document verification, and dispatch status updates.
- Real-time ride tracking between a commuter and their assigned driver,
  including an optional **live ride-tracking link** you can generate and
  send to family or friends for the duration of one trip — see
  the [Privacy Policy](/policy), Section 6a for exactly what it shows, what
  it does not show, and when it stops working.
- An in-app SOS/emergency reporting feature (see Section 7).
- Mandatory ISO/IEC 25010 evaluation and driver app-usage feedback, used to
  measure this system against the LGU's manual dispatch baseline (see
  Section 8 and the [Privacy Policy](/policy), Section 10).

## 4. Accounts and verification

You are responsible for the accuracy of the information you provide and for
keeping your account credentials confidential. Creating an account requires
verifying your mobile number with a one-time code sent by SMS — see
the [Privacy Policy](/policy), Section 6 for how that code is delivered.
Driver accounts additionally require LGU/TODA administrator approval before
activation; an administrator may reject, suspend, or deactivate a driver
account for failure to meet verification, safety, or conduct requirements.
Role-based access in the app UI is a convenience only — actual authorization
is enforced server-side (database Row Level Security and server-side
functions), not by the app alone.

## 5. Fares and payment

- Fares follow the published LGU ordinance (Calamba City Ordinance No. 743,
  s. 2022). Neither party may negotiate a different fare inside the app.
- Payment is **cash only**, handed directly to the tricycle driver at the end
  of the trip. ArangCada does not process, hold, or transfer money and has no
  payment gateway.
- Final fare and payment-completion logic is verified server-side; the app
  displaying a number is a preview, not a binding quote independent of the
  server calculation.
- **Fare or ride disputes:**
  - **Filing window:** Any fare discrepancy, improper overcharge, incomplete
    trip, or disputed payment must be reported via the in-app
    "Report Issue" tool or submitted to `support@arangcada.app` within
    **seventy-two (72) hours** of trip completion.
  - **Mediation & resolution:** ArangCada records server-side trip telemetry,
    calculated fare, and payment confirmation status as an immutable audit
    trail. Because physical cash and peer-to-peer transfers are received
    directly by the driver, ArangCada does not hold commuter funds and cannot
    issue automated cash refunds.
  - **Adjudication:** Disputed cash or QR amounts shall be mediated directly
    between the parties with the assistance of the relevant Calamba TODA
    officer, or referred to the Calamba City Business Permits and Licensing
    Office (BPLO) / Tricycle Franchising Board, using ArangCada's digital
    trip record as official documentation.

## 6. User conduct

You agree not to: submit fraudulent booking requests; misuse the SOS/safety
reporting feature for non-emergencies or as a prank; attempt to bypass driver
verification requirements; attempt to access another user's trip, location,
document, or payment data; widely redistribute a ride-tracking link to people
you do not trust, given that anyone holding the link can view that trip's
live position for as long as it is active; or use the app outside its
intended Calamba City service area (other than the explicit developer-test
exception in Section 2).

## 7. Safety reporting (SOS)

The in-app SOS feature creates an immediate administrative record and notifies
ArangCada's LGU/TODA administrators of a safety concern tied to an active ride.
**It is an administrator-reviewed safety log, not an automated 911 emergency
dispatch line.** If you or any passenger are in immediate physical danger,
encounter a medical emergency, or face a crime in progress, **dial the
Philippine National Emergency Hotline (911) or the Philippine National Police
(PNP) Calamba City Police Station directly** before or immediately after
triggering the in-app SOS.

> *Note on Local Hotlines:* Dedicated direct hotline numbers for the Calamba City
> Hall Emergency Operations Center (EOC) and CDRRMO remain pending official
> publication from the City Government of Calamba and will be incorporated into
> this section and the app's safety dialer upon formal release.

## 8. Mandatory evaluation participation

As part of the underlying capstone research, **registered drivers are
required** to complete a short bilingual, five-point Likert app-usage
feedback survey after a configurable number of completed trips (currently
every trip, an LGU-administrator-configurable setting). Both drivers and the
LGU/TODA office may also see ISO/IEC 25010 evaluation results comparing this
system to the manual dispatch baseline. This is separate from, and does not
replace, the optional driver-to-commuter star rating. See
the [Privacy Policy](/policy), Section 10 for how this data is shared with
the Calamba City LGU/TODA office.

## 9. Service availability; no warranty

This is an internal-testing academic MVP. **There is no guaranteed uptime,
no service-level agreement, and the service may change, be interrupted, or be
discontinued at any time without notice**, including at the end of the
capstone testing period. The app is provided "as is" and "as available."
Map, routing, and geolocation data are provided by third parties (MapTiler,
OpenStreetMap contributors, openrouteservice/HeiGIT) and may be inaccurate,
delayed, or unavailable. A Google Routes integration also exists in the
codebase as an optional route/ETA provider but is **not active in current
builds** (see the [Privacy Policy](/policy), Section 6 for its disclosure and
current status) — if it or any other additional routing provider is
activated, this section and the Privacy Policy will be updated first.

## 10. Limitation of liability

To the maximum extent permitted by applicable Philippine law (including Articles
1171 and 1174 of the Civil Code of the Philippines):

- **Non-commercial academic pilot:** ArangCada is an academic research software
  prototype developed solely to satisfy undergraduate degree requirements at
  National University Laguna. The software, location services, and fare previews
  are provided strictly "AS IS" and "AS AVAILABLE" without warranties of
  commercial merchantability, fitness for a particular purpose, uninterrupted
  network uptime, or continuous GPS accuracy.
- **Independent operator disclaimer:** Tricycle drivers are independent
  franchise operators governed by the Calamba City Tricycle Franchising Board
  and their respective TODA. Drivers are neither employees, agents, nor
  subcontractors of the ArangCada student team, faculty advisers, or National
  University Laguna. ArangCada exercises no physical supervision over vehicle
  roadworthiness, mechanical maintenance, traffic law adherence, or passenger
  interaction on the road.
- **Exclusion of indirect damages:** In no event shall the student developers,
  capstone adviser, or National University Laguna be held liable for any direct,
  indirect, incidental, special, punitive, or consequential damages—including
  personal injury, vehicular collisions, delays, loss of personal belongings,
  or criminal acts by third parties—arising out of or in connection with the
  use of the application or tricycle transit.
- **Non-waivable rights:** Nothing in these terms excludes or limits liability
  for willful misconduct or gross negligence, nor any statutory consumer rights
  that cannot be disclaimed under Republic Act No. 7394 (Consumer Act of the
  Philippines).

## 11. Termination and suspension

- **Drivers:** LGU/TODA administrators may suspend or deactivate a driver
  account for verification failure, safety complaints, or policy
  violations, using the approval, rejection, and suspension states of the driver
  account lifecycle.
- **Commuters:** an administrator may likewise suspend or deactivate a
  commuter account for violating Section 6 (User conduct) — such as fraudulent
  booking spams, harassment in trip chats, or misuse of the SOS feature.
  - **Progressive discipline:** (1) First offense: in-app/SMS written warning;
    (2) Second offense: temporary fourteen (14) day booking suspension; (3) Third
    or severe offense: permanent account termination.
  - **Appeal procedure:** A commuter may contest an account suspension by
    submitting a written explanation with relevant trip IDs to
    `support@arangcada.app` or visiting the designated Calamba TODA / LGU
    administrative desk within seven (7) calendar days of notification. Admin
    determinations upon review are final.
- **Either role:** you may stop using the app and request account
  deactivation at any time by contacting the group (see Section 14).
- Because this is a testing MVP, the entire service may be wound down at the
  end of the capstone cycle.

## 12. Governing law and venue

These Terms of Service are governed by, construed, and enforced in accordance
with the laws of the Republic of the Philippines. Any dispute, claim, or
controversy arising from or relating to the service or these Terms that cannot
be settled amicably through TODA or LGU administrative mediation shall be
submitted to the exclusive jurisdiction of the competent courts of
**Calamba City, Laguna, Philippines**.

## 13. Changes to these terms

These terms will be revisited whenever the app's fare rules, payment
methods, service area, dispatch matching rule, or data-sharing practices
change. There is currently no in-app mechanism to notify users of changes;
the latest version is always published on this page.

## 14. Contact

ArangCada capstone group, Section CpE231B, Department of Computer
Engineering, National University Laguna.
- **Capstone Adviser:** Dr. Juliet O. Niega
- **Group Legal-Research Contact:** Hernandez, Justin T.
- **General Support & Inquiries:** `support@arangcada.app`
- **Legal & Compliance:** `legal@arangcada.app`
- **Campus Address:** National University Laguna, Km. 53 Pan-Philippine
  Highway, Brgy. Milagrosa, Calamba City, Laguna 4027, Philippines.
