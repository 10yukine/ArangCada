# Staged app fare v1

Status: proposed policy, disabled by default. This branch is for review and
later approval. It does not constitute an approved tariff or collection scheme.
Do not deploy or enable it until those decisions are settled.

## Prices

Keep the published special-trip matrix as the trip component, including its
literal discounted rows and existing straight-line distance brackets.

| Passengers | Full driver service minimum | Full system fee | Full minimum total |
|---|---:|---:|---:|
| 1–2 | PHP70 | PHP5 | PHP75 |
| 3 | PHP75 | PHP5 | PHP80 |
| 4 | PHP80 | PHP5 | PHP85 |

Driver share = trip component + max(service premium, pickup allowance).
The premium is PHP10/15/20 for parties of 1–2/3/4. Pickup allowance is PHP8/km
after the first 500 m, counted by the metre and rounded half up to a whole peso,
with a fixed 3 km distance cap (maximum PHP20), even if dispatch later expands.
The passenger pays the driver share plus the system fee. Supplements do not stack.

Provisional discount handling: preserve the discounted trip matrix; premium
PHP8/12/16, pickup PHP6.40/km (maximum16), system fee PHP4. Minimum totals are
PHP60/64/68. Confirm eligibility, mixed parties and discount scope before enabling.
No body-weight charge, surge or road-distance multiplier is introduced.

## Implementation

- `app_fare_enabled` is an owner-controlled database setting, default false.
  Mobile previews take it from `get_mobile_settings`. The existing standalone
  pickup switch also defaultsfalse; the combined policy includes its own capped
  pickup allowance when enabled.
- `request_ride` accepts a validated count in the original booking transaction.
  Older calls remain compatible while disabled. When enabled, callers omitting
  the count are rejected rather than quietly charged a policy they did not preview.
- Trip rows snapshot the count, fare class, policy version, base trip fare,
  combined driver supplement and system fee. Assignment records pickup distance
  and calculated allowance; retries, discount approval or disabling the setting
  do not recalculate the original quote. Rebooking is required to change an
  already-priced party count. Completion retains the quoted passenger total.
- Review and receipt screens itemize the components; before matching, any
  additional pickup amount is bounded above the already included premium.
  Driver offers distinguish cash to collect from driver share. Earnings and
  driver history exclude the retained system fee, before operating costs.
- The published ordinance reference table is retained as the source record.
  The new supplements are described separately rather than attributed to it.

This branch incorporates and adapts the pickup-leg feature in one subsequent
migration. Do **not** independently merge/apply the older pickup-leg migration
as well: reconcile the duplicate columns/functions first if that branch lands.
The original pickup branch is unchanged.

## Approval and release checklist

1. Confirm prices, discount policy, pickup ceiling, disclosures and authorized
   collection arrangements with BPTFO/city staff. The amounts are our proposal;
   static competitor analysis did not recover a matching numerical tariff.
2. Rebase/review against the then-current main and migration history. The
   migration patches the fully migrated booking function and aborts on changed
   anchors, preserving admin-booking and driver-dispatch safeguards.
3. Re-run database/mobile checks, choose a new application build number and
   prepare the rollout. No release build was produced during this implementation.
4. Apply the migration with the switch still off, distribute a compatible client,
   and set `min_mobile_build` to that compatible release before enabling.
5. Only after approval and collection readiness, an authorized database operator
   can set `mobile_settings.app_fare_enabled=true`. No client/admin API can
   change that table. Disabling affects new bookings; existing quotes retain
   their snapshots.

System-fee columns record the quoted liability, **not money received by the
platform**. No wallet, remittance reconciliation, treasury integration or
nonpayment suspension is implemented. Completed-trip fees are the data needed
for a future approved collection process; cancelled quotes are not earned fees.

## Verification

Database regression covers default-off behavior, count bounds, all full-fare
minimums, discounted pricing, idempotency, stale-client rejection, delayed
assignment, non-stacking, fixed pickup cap despite expanded dispatch, and final
driver/system split. The complete existing database suite protects dispatch,
admin booking, completion and permission rules.

Mobile regression covers the calculator, server count/breakdown synchronization,
settings, review/matched screens, receipts and earnings. Test database:
`arangcada_fare_roi_test` on the disposable local WSL PostgreSQL instance.
No hosted database, phone, vendor endpoint, APK build, release or main merge is
part of these checks.

Validated during implementation: full mobile suite: 474 passed / 13 existing skips;
73 affected mobile tests passed after the last UI guard; flutter analyze clean;
52 local database files / 974 checks passed. Supabase CLI security advisors were
unavailable because its Docker-local endpoint 127.0.0.1:54322 was not running;
WSL PostgreSQL pgTAP permission/dispatch regressions passed instead.
