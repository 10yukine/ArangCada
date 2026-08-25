// Pure logic for admin-onboard-driver, deliberately separated from every
// network call. Nothing in this file touches Supabase, `fetch`, or
// `Deno.env`, so it can be unit tested with `deno test` and no live project
// -- the same tests-first discipline the SQL layer used, applied here.
//
// See .pipeline/specs.md, "Commuter-first driver onboarding, server layer"
// addendum (2026-08-25 second session), §5 and §6.

/** One row as returned by the `admin_preview_driver_candidate` RPC. */
export interface CandidateRow {
  match_key: "email" | "phone";
  masked_name: string;
  joined_on: string;
  account_role: string;
  account_status: string;
  trip_count: number;
}

export interface OnboardRequest {
  email: string;
  phone: string;
  toda_zone_id: string;
  body_number?: string | null;
  reason?: string | null;
}

export type ValidationResult =
  | { ok: true; value: OnboardRequest }
  | { ok: false; error: string };

// A UUID shape check, not a database round trip -- catching an obviously
// malformed zone id here means the client gets a fast, specific 400 instead
// of a generic Postgres foreign-key error surfaced through two layers.
const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Validates the raw request body. Deliberately strict about what counts as
 * present: an empty string is not a value, matching how the SQL layer's
 * `nullif(trim(...), '')` pattern treats it.
 */
export function validateOnboardRequest(body: unknown): ValidationResult {
  if (typeof body !== "object" || body === null) {
    return { ok: false, error: "request body must be a JSON object" };
  }

  const b = body as Record<string, unknown>;

  const email = typeof b.email === "string" ? b.email.trim() : "";
  if (email === "" || !email.includes("@")) {
    return { ok: false, error: "email is required and must look like an email address" };
  }

  const phone = typeof b.phone === "string" ? b.phone.trim() : "";
  if (phone === "") {
    return { ok: false, error: "phone is required" };
  }

  const todaZoneId = typeof b.toda_zone_id === "string" ? b.toda_zone_id.trim() : "";
  if (!UUID_RE.test(todaZoneId)) {
    return { ok: false, error: "toda_zone_id is required and must be a uuid" };
  }

  const bodyNumberRaw = b.body_number;
  const bodyNumber =
    typeof bodyNumberRaw === "string" && bodyNumberRaw.trim() !== ""
      ? bodyNumberRaw.trim()
      : null;

  const reasonRaw = b.reason;
  const reason =
    typeof reasonRaw === "string" && reasonRaw.trim() !== "" ? reasonRaw.trim() : null;

  return {
    ok: true,
    value: {
      email: email.toLowerCase(),
      phone,
      toda_zone_id: todaZoneId,
      body_number: bodyNumber,
      reason,
    },
  };
}

export type OnboardOutcome =
  | { kind: "candidate_found"; candidates: CandidateRow[] }
  | { kind: "created"; action_link: string };

/**
 * The one branch that matters: a match means stop and hand the decision back
 * to a human, no match means create. This function takes an
 * already-fetched candidate list rather than calling the RPC itself, which
 * is what makes it testable without a database.
 *
 * Per the addendum: even when a match is found, THIS function never
 * promotes anything. Promotion happens through
 * admin_promote_commuter_to_driver from the admin's own authenticated
 * session afterwards, so the confirm step stays visible and auditable
 * through the normal RPC path rather than being buried inside this
 * function's control flow.
 */
export function decideOnboardOutcome(candidates: CandidateRow[]): "promote_via_client" | "create" {
  return candidates.length > 0 ? "promote_via_client" : "create";
}

/**
 * Shapes the create-path response. Deliberately does not include anything
 * beyond the link -- no email, no phone, no name.
 *
 * DEVIATION FROM SPEC, found by inspecting the real supabase-js type
 * definitions rather than assuming: the addendum's contract said this
 * function returns { action_link, expires_at }, but
 * GoTrueAdminApi.generateLink()'s response type (auth-js
 * GenerateLinkProperties) has no expiry field at all -- no expires_at, no
 * expires_in. Invite-link lifetime is governed by the project's Auth
 * settings (Email OTP expiry) and is not exposed through this API call.
 * Returning a locally-fabricated guess would be worse than returning
 * nothing: it would look authoritative to apps/admin_web while being
 * disconnected from the value that actually governs the link. Recorded in
 * .pipeline/specs.md and .pipeline/changes.md.
 */
export function buildCreatedResponse(
  actionLink: string,
): { kind: "created"; action_link: string } {
  return { kind: "created", action_link: actionLink };
}

/**
 * Redacts a request body for logging. Edge Function logs go to Supabase's
 * log viewer, which this repo treats like any other log under CLAUDE.md
 * rule 10 -- no phone numbers, emails, or names, even in an error path.
 */
export function redactForLogging(body: unknown): Record<string, unknown> {
  if (typeof body !== "object" || body === null) {
    return { type: typeof body };
  }
  const b = body as Record<string, unknown>;
  return {
    has_email: typeof b.email === "string" && b.email.trim() !== "",
    has_phone: typeof b.phone === "string" && b.phone.trim() !== "",
    toda_zone_id: typeof b.toda_zone_id === "string" ? b.toda_zone_id : null,
    has_body_number: typeof b.body_number === "string" && b.body_number.trim() !== "",
  };
}
