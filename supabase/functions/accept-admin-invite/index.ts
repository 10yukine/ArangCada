// accept-admin-invite -- the recipient of an admin invite creates their own
// account. Called with no session at all: the token in the link is the only
// credential.
//
// See .pipeline/specs.md Spec 19.
//
// WHAT THIS FUNCTION DOES AND DOES NOT DO
//
//   * Uses a SEPARATE, freshly constructed service-role client -- never
//     derived from anything, because there is no caller session to derive
//     it from. Same reasoning admin-onboard-driver documents for its own
//     service-role client.
//   * Looks up the invite by token first (admin_invite_lookup), purely to
//     resolve the locked email -- the caller cannot supply their own email,
//     only the token.
//   * Creates the auth user via the Auth Admin API -- only that API can do
//     this outside a public signUp() call, and signUp() would produce a
//     phone-required, non-admin commuter account instead.
//   * Sets invited_admin: true in user_metadata (raw_user_meta_data), NOT
//     app_metadata. An earlier version used app_metadata, reasoning that
//     only the Admin API can set it. That was true but irrelevant: live
//     verification proved GoTrue writes the auth.users row with only its
//     own default app_metadata first and merges in the caller-supplied
//     app_metadata as a separate follow-up step, by which point
//     handle_new_user()'s AFTER INSERT trigger has already fired and
//     already raised for a missing phone. user_metadata does not have this
//     problem -- confirmed present on the very first insert. This is safe,
//     not a spoofing risk reopened: the flag only ever waives the phone
//     requirement, never admin status -- see the migration comment
//     (20260908030000) for why that distinction matters.
//   * Calls admin_finalize_invited_account() to promote the new profile to
//     admin (and TODA scope, if any) and mark the invite accepted. If that
//     call fails, the auth user now exists but was never promoted -- logged
//     as a manual-follow-up case, same as admin-onboard-driver's own
//     partial-failure branch.
//   * Never signs the new user in. apps/admin_web does that itself,
//     afterwards, by calling the same signIn() the login screen already uses.

import { createClient } from "npm:@supabase/supabase-js@2.45.4";

function jsonResponse(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return jsonResponse(405, { error: "method not allowed" });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    console.error("accept-admin-invite: missing required configuration");
    return jsonResponse(500, { error: "server misconfigured" });
  }

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return jsonResponse(400, { error: "request body must be valid JSON" });
  }

  const { token, first_name: firstName, last_name: lastName, password } = (body ?? {}) as {
    token?: unknown;
    first_name?: unknown;
    last_name?: unknown;
    password?: unknown;
  };
  if (typeof token !== "string" || token.trim() === "") {
    return jsonResponse(400, { error: "token is required" });
  }
  if (typeof firstName !== "string" || firstName.trim() === "") {
    return jsonResponse(400, { error: "first name is required" });
  }
  if (typeof lastName !== "string" || lastName.trim() === "") {
    return jsonResponse(400, { error: "last name is required" });
  }
  if (typeof password !== "string" || password.length < 8) {
    return jsonResponse(400, { error: "password must be at least 8 characters" });
  }

  const serviceClient = createClient(supabaseUrl, serviceRoleKey);

  const { data: lookupRows, error: lookupError } = await serviceClient.rpc(
    "admin_invite_lookup",
    { p_token: token },
  );
  if (lookupError) {
    console.error("accept-admin-invite: invite lookup failed", lookupError.message);
    return jsonResponse(500, { error: "could not verify the invite" });
  }
  const email = (lookupRows as { email?: string }[] | null)?.[0]?.email;
  if (!email) {
    return jsonResponse(400, { error: "this invite is invalid or has expired" });
  }

  const displayName = `${firstName.trim()} ${lastName.trim()}`.trim();
  const { data: created, error: createError } = await serviceClient.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: { display_name: displayName, invited_admin: true },
  });
  if (createError || !created?.user) {
    // Most likely cause: this email already has an auth.users account (e.g.
    // an existing commuter/driver signup). Promoting an existing account
    // through this flow is out of scope for this pass (.pipeline/specs.md
    // Spec 19 section 6) -- surfaced as a clear message rather than a crash.
    console.error("accept-admin-invite: createUser failed", createError?.message);
    return jsonResponse(409, {
      error: createError?.message?.includes("already been registered")
        ? "an account already exists for this email -- contact a developer"
        : "could not create the account",
    });
  }

  const { error: finalizeError } = await serviceClient.rpc("admin_finalize_invited_account", {
    p_invite_token: token,
    p_user_id: created.user.id,
    p_first_name: firstName.trim(),
    p_last_name: lastName.trim(),
  });
  if (finalizeError) {
    // The auth user now exists but was never promoted to admin or marked
    // against the invite. A human must resolve this -- logged with an
    // action tag an admin can search for, never with the email (rule 10).
    console.error(
      "accept-admin-invite: account created but finalize failed -- MANUAL FOLLOW-UP REQUIRED",
      finalizeError.message,
      { new_user_id: created.user.id },
    );
    return jsonResponse(500, {
      error: "the account was created but could not be finalized -- contact a developer",
    });
  }

  return jsonResponse(200, { success: true });
});
