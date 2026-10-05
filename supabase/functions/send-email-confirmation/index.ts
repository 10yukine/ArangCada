import { CORS_HEADERS, jsonResponse } from "../_shared/http.ts";
import { sendConfirmationEmail } from "../_shared/confirmation_email.ts";
// send-email-confirmation -- emails the signed-in user a link that confirms
// the email address on their account.
//
// WHAT THIS FUNCTION DOES AND DOES NOT DO
//
//   * Runs only for a signed-in caller (verify_jwt = true in config.toml) and
//     asks Supabase Auth who that caller is. The account is never taken from
//     the request body.
//   * Makes the link's token here and stores only its SHA-256 hash, through
//     create_email_confirmation() on the service role. That RPC decides
//     whether a link may be sent at all (verified number, not yet confirmed,
//     one a minute, five a day) and answers with the address on file.
//   * Sends the link to that address and nowhere else. The token and the
//     address are never returned to the caller: holding the session must not
//     be enough to confirm the email.

import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const CONFIRM_PAGE = "https://arangcada.app/confirm-email";

function base64Url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, "0")).join("");
}

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
  const resendKey = Deno.env.get("RESEND_API_KEY");
  if (!supabaseUrl || !anonKey || !serviceRoleKey || !resendKey) {
    console.error("send-email-confirmation: missing required configuration");
    return jsonResponse(500, { error: "server misconfigured" });
  }

  const callerClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: caller, error: callerError } = await callerClient.auth.getUser();
  const userId = caller?.user?.id;
  if (callerError || typeof userId !== "string") {
    return jsonResponse(401, { error: "sign in again to continue" });
  }

  const token = base64Url(crypto.getRandomValues(new Uint8Array(32)));
  const serviceClient = createClient(supabaseUrl, serviceRoleKey);
  const { data: email, error: createError } = await serviceClient.rpc(
    "create_email_confirmation",
    { p_user_id: userId, p_token_hash: await sha256Hex(token) },
  );
  if (createError || typeof email !== "string" || email === "") {
    // 22023 carries a sentence written for the user (wait a minute, already
    // confirmed, verify your number first).
    if (createError?.code === "22023") {
      return jsonResponse(429, { error: createError.message });
    }
    console.error("send-email-confirmation: create_email_confirmation failed", createError?.message);
    return jsonResponse(500, { error: "could not prepare the confirmation email" });
  }

  try {
    await sendConfirmationEmail(email, `${CONFIRM_PAGE}#token=${token}`, resendKey);
  } catch {
    return jsonResponse(502, { error: "could not send the confirmation email" });
  }
  return jsonResponse(200, { sent: true });
});
