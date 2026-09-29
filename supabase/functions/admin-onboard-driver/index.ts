import { CORS_HEADERS, jsonResponse } from "../_shared/http.ts";
// admin-onboard-driver -- the one piece of driver onboarding that must be
// server-side, because only the Supabase Auth Admin API can create an auth
// user or issue an invite link, and that API requires the service-role key.
//
// addendum (2026-08-25 second session), §5 and §6.
//
// WHAT THIS FUNCTION DOES AND DOES NOT DO
//
//   * Verifies the caller is an active admin, using a client scoped to the
//     caller's OWN JWT -- never the service-role key -- for that check.
//   * Calls admin_preview_driver_candidate. If a match already exists, it
//     returns the (masked) preview and STOPS. It does not promote anything
//     itself: promotion happens through admin_promote_commuter_to_driver
//     from the admin's own authenticated session afterwards, so the confirm
//     step stays visible and auditable through the normal RPC path rather
//     than being buried inside this function's control flow.
//   * If no match exists, it switches to a SEPARATE service-role client --
//     constructed fresh, never derived from the caller's client -- to create
//     the account via generateLink(), then calls admin_activate_new_driver,
//     which is granted -- scoped exclusively to service_role and unreachable
//     from any ordinary admin session, by GRANT, not by a check this
//     function could get wrong.
//   * Returns only { action_link }. generateLink()'s response carries no
//     expiry -- see lib.ts's buildCreatedResponse for why one is not
//     fabricated here. Never sends the email itself and never renders a QR
//     code -- both are apps/admin_web's job.
//
// All decision logic (validation, the found-vs-not-found branch, response
// shaping) lives in lib.ts and is unit tested there without a network call.
// This file is deliberately thin: wire the clients, call the RPCs, map
// errors to HTTP status codes.

import { createClient } from "npm:@supabase/supabase-js@2.45.4";
import {
  buildCreatedResponse,
  decideOnboardOutcome,
  redactForLogging,
  validateOnboardRequest,
  type CandidateRow,
} from "./lib.ts";

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return jsonResponse(405, { error: "method not allowed" });
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return jsonResponse(401, { error: "missing Authorization header" });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const redirectTo = Deno.env.get("SET_PASSWORD_REDIRECT_URL");

  if (!supabaseUrl || !anonKey || !serviceRoleKey || !redirectTo) {
    // A config problem, not a caller problem -- deliberately generic so a
    // misconfigured deployment does not tell an unauthenticated caller which
    // secret is missing.
    console.error("admin-onboard-driver: missing required configuration");
    return jsonResponse(500, { error: "server misconfigured" });
  }

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return jsonResponse(400, { error: "request body must be valid JSON" });
  }

  const validated = validateOnboardRequest(body);
  if (!validated.ok) {
    return jsonResponse(400, { error: validated.error });
  }
  const input = validated.value;

  // Scoped to the CALLER's own JWT. Used only to establish who is asking and
  // to run the admin-gated preview RPC, which re-checks admin status itself
  // server-side -- this client never touches anything that requires the
  // service-role key.
  const callerClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });

  const { data: userData, error: userError } = await callerClient.auth.getUser();
  if (userError || !userData?.user) {
    return jsonResponse(401, { error: "invalid or expired session" });
  }
  const actorId = userData.user.id;

  const { data: isAdminData, error: isAdminError } = await callerClient.rpc(
    "is_admin",
    { uid: actorId },
  );
  if (isAdminError) {
    console.error("admin-onboard-driver: is_admin check failed", isAdminError.message);
    return jsonResponse(500, { error: "could not verify admin status" });
  }
  if (isAdminData !== true) {
    return jsonResponse(403, { error: "admin privileges required" });
  }

  const { data: candidateData, error: candidateError } = await callerClient.rpc(
    "admin_preview_driver_candidate",
    { p_email: input.email, p_phone: input.phone },
  );
  if (candidateError) {
    console.error(
      "admin-onboard-driver: candidate preview failed",
      candidateError.message,
      redactForLogging(body),
    );
    return jsonResponse(500, { error: "could not check for an existing account" });
  }

  const candidates = (candidateData ?? []) as CandidateRow[];
  const outcome = decideOnboardOutcome(candidates);

  if (outcome === "promote_via_client") {
    // A match exists. Hand it back and stop -- see the file header for why
    // this function does not promote anything itself.
    return jsonResponse(200, { kind: "candidate_found", candidates });
  }

  // No match: create the account. From here on, only the service-role
  // client is used, and only for the two calls that require it. This client
  // is constructed fresh here, not derived from callerClient, so a bug
  // above can never accidentally carry service-role privilege into a path
  // that was only supposed to run as the caller.
  const serviceClient = createClient(supabaseUrl, serviceRoleKey);

  const { data: linkData, error: linkError } = await serviceClient.auth.admin.generateLink({
    type: "invite",
    email: input.email,
    options: { redirectTo },
  });
  if (linkError || !linkData?.user || !linkData.properties?.action_link) {
    console.error(
      "admin-onboard-driver: generateLink failed",
      linkError?.message ?? "no user/action_link returned",
      redactForLogging(body),
    );
    return jsonResponse(500, { error: "could not create the account" });
  }

  const { error: activateError } = await serviceClient.rpc("admin_activate_new_driver", {
    p_new_profile_id: linkData.user.id,
    p_actor_id: actorId,
    p_toda_zone_id: input.toda_zone_id,
    p_body_number: input.body_number,
    p_reason: input.reason,
  });
  if (activateError) {
    // The auth user now exists but was never marked as a driver. This is a
    // partial-failure state a human must resolve -- logged with an action
    // tag an admin can search for, never with the email/phone that would
    // violate rule 10.
    console.error(
      "admin-onboard-driver: account created but activation failed -- MANUAL FOLLOW-UP REQUIRED",
      activateError.message,
      { new_user_id: linkData.user.id },
    );
    return jsonResponse(500, {
      error:
        "account was created but could not be marked as a driver -- contact a developer",
    });
  }

  return jsonResponse(200, buildCreatedResponse(linkData.properties.action_link));
});
