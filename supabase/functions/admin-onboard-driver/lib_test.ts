// Unit tests for admin-onboard-driver's pure logic. No network, no
// Deno.env, no live project -- run with `deno test` and nothing else.
import {
  assertEquals,
  assertObjectMatch,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  buildCreatedResponse,
  decideOnboardOutcome,
  redactForLogging,
  validateOnboardRequest,
  type CandidateRow,
} from "./lib.ts";

// ---------------------------------------------------------------------------
// validateOnboardRequest
// ---------------------------------------------------------------------------

Deno.test("validateOnboardRequest accepts a complete, well-formed request", () => {
  const result = validateOnboardRequest({
    email: "Juan@Example.Test",
    phone: "09171234567",
    toda_zone_id: "11111111-1111-1111-1111-111111111111",
    body_number: "  DT-001  ",
    reason: "  FTF onboarding  ",
  });
  assertEquals(result.ok, true);
  if (result.ok) {
    assertEquals(result.value.email, "juan@example.test", "email is lowercased");
    assertEquals(result.value.body_number, "DT-001", "body_number is trimmed");
    assertEquals(result.value.reason, "FTF onboarding", "reason is trimmed");
  }
});

Deno.test("validateOnboardRequest accepts optional fields being absent", () => {
  const result = validateOnboardRequest({
    email: "juan@example.test",
    phone: "09171234567",
    toda_zone_id: "11111111-1111-1111-1111-111111111111",
  });
  assertEquals(result.ok, true);
  if (result.ok) {
    assertEquals(result.value.body_number, null);
    assertEquals(result.value.reason, null);
  }
});

Deno.test("validateOnboardRequest rejects a non-object body", () => {
  assertEquals(validateOnboardRequest(null).ok, false);
  assertEquals(validateOnboardRequest("a string").ok, false);
  assertEquals(validateOnboardRequest(42).ok, false);
});

Deno.test("validateOnboardRequest rejects a missing email", () => {
  const result = validateOnboardRequest({
    phone: "09171234567",
    toda_zone_id: "11111111-1111-1111-1111-111111111111",
  });
  assertEquals(result.ok, false);
});

Deno.test("validateOnboardRequest rejects an email with no @", () => {
  const result = validateOnboardRequest({
    email: "not-an-email",
    phone: "09171234567",
    toda_zone_id: "11111111-1111-1111-1111-111111111111",
  });
  assertEquals(result.ok, false);
});

Deno.test("validateOnboardRequest rejects whitespace-only email as absent", () => {
  const result = validateOnboardRequest({
    email: "   ",
    phone: "09171234567",
    toda_zone_id: "11111111-1111-1111-1111-111111111111",
  });
  assertEquals(result.ok, false);
});

Deno.test("validateOnboardRequest rejects a missing phone", () => {
  const result = validateOnboardRequest({
    email: "juan@example.test",
    toda_zone_id: "11111111-1111-1111-1111-111111111111",
  });
  assertEquals(result.ok, false);
});

Deno.test("validateOnboardRequest rejects a malformed toda_zone_id", () => {
  const result = validateOnboardRequest({
    email: "juan@example.test",
    phone: "09171234567",
    toda_zone_id: "not-a-uuid",
  });
  assertEquals(result.ok, false);
});

Deno.test("validateOnboardRequest rejects a missing toda_zone_id", () => {
  const result = validateOnboardRequest({
    email: "juan@example.test",
    phone: "09171234567",
  });
  assertEquals(result.ok, false);
});

Deno.test("validateOnboardRequest treats a whitespace-only body_number as absent, not an error", () => {
  const result = validateOnboardRequest({
    email: "juan@example.test",
    phone: "09171234567",
    toda_zone_id: "11111111-1111-1111-1111-111111111111",
    body_number: "   ",
  });
  assertEquals(result.ok, true);
  if (result.ok) {
    assertEquals(result.value.body_number, null);
  }
});

// ---------------------------------------------------------------------------
// decideOnboardOutcome
// ---------------------------------------------------------------------------

const sampleCandidate: CandidateRow = {
  match_key: "email",
  masked_name: "J*** D*** C***",
  joined_on: "2026-01-01",
  account_role: "commuter",
  account_status: "active",
  trip_count: 3,
};

Deno.test("decideOnboardOutcome: no candidates means create", () => {
  assertEquals(decideOnboardOutcome([]), "create");
});

Deno.test("decideOnboardOutcome: one candidate means hand off to the client, never promote here", () => {
  assertEquals(decideOnboardOutcome([sampleCandidate]), "promote_via_client");
});

Deno.test("decideOnboardOutcome: two independent matches (the discrepancy case) still means hand off, not a merged guess", () => {
  const phoneMatch: CandidateRow = { ...sampleCandidate, match_key: "phone" };
  assertEquals(
    decideOnboardOutcome([sampleCandidate, phoneMatch]),
    "promote_via_client",
    "the function does not try to pick between two different matches -- that decision belongs to a human",
  );
});

// ---------------------------------------------------------------------------
// buildCreatedResponse
// ---------------------------------------------------------------------------

Deno.test("buildCreatedResponse carries only the link -- no fabricated expiry", () => {
  const response = buildCreatedResponse("https://example.test/invite/abc");
  assertObjectMatch(response, {
    kind: "created",
    action_link: "https://example.test/invite/abc",
  });
  assertEquals(
    Object.keys(response).sort(),
    ["action_link", "kind"],
    "no email, phone, name, or invented expiry field -- GoTrueAdminApi.generateLink() does not return one, so this function does not pretend to",
  );
});

// ---------------------------------------------------------------------------
// redactForLogging
// ---------------------------------------------------------------------------

Deno.test("redactForLogging never echoes the actual email or phone value", () => {
  const redacted = redactForLogging({
    email: "juan@example.test",
    phone: "+639171234567",
    toda_zone_id: "11111111-1111-1111-1111-111111111111",
    body_number: "DT-001",
  });
  const serialized = JSON.stringify(redacted);
  assertEquals(serialized.includes("juan@example.test"), false);
  assertEquals(serialized.includes("+639171234567"), false);
  assertObjectMatch(redacted, {
    has_email: true,
    has_phone: true,
    toda_zone_id: "11111111-1111-1111-1111-111111111111",
    has_body_number: true,
  });
});

Deno.test("redactForLogging handles a malformed body without throwing", () => {
  const redacted = redactForLogging("not an object");
  assertObjectMatch(redacted, { type: "string" });
});
