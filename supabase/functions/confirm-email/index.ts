import { CORS_HEADERS, jsonResponse } from "../_shared/http.ts";
// confirm-email -- redeems the link sent by send-email-confirmation.
//
// Called from arangcada.app/confirm-email with no session at all: the person
// opening the email may not be signed in on that device, so the token in the
// link is the only credential (verify_jwt = false in config.toml).
//
// WHAT THIS FUNCTION DOES AND DOES NOT DO
//
//   * Hashes the token and hands the hash to confirm_email() on the service
//     role. That RPC is the source of truth: single use, 24 hours, and only
//     for the address the link was sent to.
//   * Answers the same way for every link that does not work (unknown, used,
//     expired, address since changed), so it cannot be used to test tokens or
//     learn anything about an account.
//   * Takes POST only. The page asks for a button press before calling it, so
//     a mail scanner that merely opens the link does not use it up.

import { createClient } from "npm:@supabase/supabase-js@2.45.4";

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

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    console.error("confirm-email: missing required configuration");
    return jsonResponse(500, { error: "server misconfigured" });
  }

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return jsonResponse(400, { error: "request body must be valid JSON" });
  }
  const raw = (body ?? {}) as { token?: unknown };
  const token = typeof raw.token === "string" ? raw.token.trim() : "";
  // A real token is 43 characters. Anything far from that is not worth a
  // database call.
  if (token.length < 20 || token.length > 200) {
    return jsonResponse(400, { error: "This link is not valid." });
  }

  const serviceClient = createClient(supabaseUrl, serviceRoleKey);
  const { data: confirmed, error } = await serviceClient.rpc(
    "confirm_email",
    { p_token_hash: await sha256Hex(token) },
  );
  if (error) {
    console.error("confirm-email: confirm_email failed", error.message);
    return jsonResponse(500, { error: "The email could not be confirmed. Try again later." });
  }
  if (confirmed !== true) {
    return jsonResponse(400, {
      error: "This link has expired or was already used. Open the app and ask for a new one.",
    });
  }
  return jsonResponse(200, { confirmed: true });
});
