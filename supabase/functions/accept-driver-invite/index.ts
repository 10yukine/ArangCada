import { CORS_HEADERS, jsonResponse } from "../_shared/http.ts";
// accept-driver-invite -- the invited driver creates their own account.
// Called with no session at all: the token in the link is the only
// credential.
//
// Mirrors accept-admin-invite
// closely on purpose.
//
// WHAT THIS FUNCTION DOES AND DOES NOT DO
//
//   * Uses a SEPARATE, freshly constructed service-role client -- never
//     derived from anything, because there is no caller session to derive
//     it from.
//   * Looks up the invite by token first (driver_invite_lookup), purely to
//     resolve the locked email -- the caller cannot supply their own
//     email, only the token.
//   * Creates the auth user via the Auth Admin API. Passes user_metadata:
//     { display_name, mobile_number } -- both collected on the driver's
//     own form, unlike the admin invite flow, which had to design a phone
//     exemption because nothing there ever asked for one. A driver
//     provides theirs at acceptance, so handle_new_user()'s existing,
//     UNMODIFIED validation already does the right thing: no exemption to
//     design here at all.
//   * Calls driver_finalize_invited_account() to promote the new profile
//     to driver via create_driver_record() and mark the invite accepted.
//     If that call fails, the auth user now exists but was never
//     promoted -- logged as a manual-follow-up case, same as
//     admin-onboard-driver's own partial-failure branch.
//   * Never signs the driver in anywhere. A driver account cannot open an
//     admin_web session at all (AdminSession.fromProfile requires
//     role = 'admin'), and this app has no session of its own to offer --
//     apps/admin_web's confirmation screen instead tells the driver to
//     open the ArangCada mobile app and sign in there.

import { createClient } from "npm:@supabase/supabase-js@2.45.4";

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return jsonResponse(405, { error: "method not allowed" });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    console.error("accept-driver-invite: missing required configuration");
    return jsonResponse(500, { error: "server misconfigured" });
  }

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return jsonResponse(400, { error: "request body must be valid JSON" });
  }

  const {
    token,
    display_name: displayName,
    mobile_number: mobileNumber,
    password,
  } = (body ?? {}) as {
    token?: unknown;
    display_name?: unknown;
    mobile_number?: unknown;
    password?: unknown;
  };
  if (typeof token !== "string" || token.trim() === "") {
    return jsonResponse(400, { error: "token is required" });
  }
  if (typeof displayName !== "string" || displayName.trim() === "") {
    return jsonResponse(400, { error: "full name is required" });
  }
  if (typeof mobileNumber !== "string" || mobileNumber.trim() === "") {
    return jsonResponse(400, { error: "mobile number is required" });
  }
  // Same rules as the apps and Supabase Auth: 8+ characters, upper and lower
  // case, and a number.
  if (
    typeof password !== "string" || password.length < 8 ||
    !/[a-z]/.test(password) || !/[A-Z]/.test(password) || !/[0-9]/.test(password)
  ) {
    return jsonResponse(400, {
      error: "use at least 8 characters with uppercase and lowercase letters and a number",
    });
  }

  const serviceClient = createClient(supabaseUrl, serviceRoleKey);

  const { data: lookupRows, error: lookupError } = await serviceClient.rpc(
    "driver_invite_lookup",
    { p_token: token },
  );
  if (lookupError) {
    console.error("accept-driver-invite: invite lookup failed", lookupError.message);
    return jsonResponse(500, { error: "could not verify the invite" });
  }
  const email = (lookupRows as { email?: string }[] | null)?.[0]?.email;
  if (!email) {
    return jsonResponse(400, { error: "this invite is invalid or has expired" });
  }

  const { data: created, error: createError } = await serviceClient.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: {
      display_name: displayName.trim(),
      mobile_number: mobileNumber.trim(),
    },
  });
  if (createError || !created?.user) {
    // Most likely cause: this email already has an auth.users account.
    // Should not normally happen -- admin_create_driver_invite() already
    // refuses to invite an email that already has a profile -- but the
    // window between invite creation and acceptance is real, so this is
    // surfaced as a clear message rather than a crash.
    console.error("accept-driver-invite: createUser failed", createError?.message);
    return jsonResponse(409, {
      error: createError?.message?.includes("already been registered")
        ? "an account already exists for this email -- contact a developer"
        : "could not create the account",
    });
  }

  const { error: finalizeError } = await serviceClient.rpc("driver_finalize_invited_account", {
    p_invite_token: token,
    p_user_id: created.user.id,
  });
  if (finalizeError) {
    // The auth user now exists but was never promoted to driver. A human
    // must resolve this -- logged with an action tag an admin can search
    // for, never with the email (rule 10).
    console.error(
      "accept-driver-invite: account created but finalize failed -- MANUAL FOLLOW-UP REQUIRED",
      finalizeError.message,
      { new_user_id: created.user.id },
    );
    return jsonResponse(500, {
      error: "the account was created but could not be finalized -- contact a developer",
    });
  }

  return jsonResponse(200, { success: true });
});
