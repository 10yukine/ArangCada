import { CORS_HEADERS, jsonResponse } from "../_shared/http.ts";
import { sendInviteEmail } from "../_shared/invite_email.ts";
// send-admin-invite -- an LGU administrator invites a new LGU or TODA admin.
//
// See .pipeline/specs.md Spec 19.
//
// WHAT THIS FUNCTION DOES AND DOES NOT DO
//
//   * Verifies the caller with a client scoped to the caller's OWN JWT --
//     never the service-role key -- exactly like admin-onboard-driver.
//   * Calls admin_create_invite() on that same caller-scoped client. That
//     RPC is the actual source of truth for "is this caller an LGU admin,
//     is the email valid, does the scope/zone pair make sense" -- this
//     function does not re-implement any of that, only the bare presence
//     checks needed to return a useful 400 instead of a raw Postgres error.
//   * Sends the invite email itself, via a direct fetch() to Resend's HTTP
//     API -- no SDK, same shape send-sms-hook uses for Semaphore. This is
//     the one thing an RPC cannot do.
//   * Never touches the service-role key. There is nothing in this flow
//     that requires the Auth Admin API -- account creation happens later,
//     in accept-admin-invite, once the recipient accepts.

import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY") ?? "";
const ADMIN_WEB_BASE_URL = "https://admin.arangcada.app";

Deno.serve(async (req: Request) => {
  // The browser's CORS preflight -- must return before any auth/config
  // check below, or the preflight itself gets rejected and the real
  // request is never even sent.
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
  if (!supabaseUrl || !anonKey || !RESEND_API_KEY) {
    console.error("send-admin-invite: missing required configuration");
    return jsonResponse(500, { error: "server misconfigured" });
  }

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return jsonResponse(400, { error: "request body must be valid JSON" });
  }

  const { email, scope, toda_zone_id: todaZoneId } = (body ?? {}) as {
    email?: unknown;
    scope?: unknown;
    toda_zone_id?: unknown;
  };
  if (typeof email !== "string" || email.trim() === "") {
    return jsonResponse(400, { error: "email is required" });
  }
  if (scope !== "lgu" && scope !== "toda") {
    return jsonResponse(400, { error: "scope must be lgu or toda" });
  }
  if (scope === "toda" && (typeof todaZoneId !== "string" || todaZoneId.trim() === "")) {
    return jsonResponse(400, { error: "toda_zone_id is required for a toda invite" });
  }

  // Scoped to the CALLER's own JWT -- admin_create_invite() re-checks
  // is_admin() itself server-side, so this client never needs the
  // service-role key at all.
  const callerClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });

  const { data: token, error: inviteError } = await callerClient.rpc("admin_create_invite", {
    p_email: email,
    p_scope: scope,
    p_toda_zone_id: scope === "toda" ? todaZoneId : null,
  });

  if (inviteError || typeof token !== "string") {
    const status = inviteError?.code === "42501" ? 403 : 400;
    console.error("send-admin-invite: admin_create_invite failed", inviteError?.message);
    return jsonResponse(status, {
      error: inviteError?.message ?? "could not create the invite",
    });
  }

  const link = `${ADMIN_WEB_BASE_URL}/accept-invite?token=${token}`;

  try {
    await sendInviteEmail("admin", email, link, RESEND_API_KEY);
  } catch (error) {
    // The invite row already exists at this point (admin_create_invite()
    // committed it), but it was never delivered. Not rolled back -- sending
    // the same invite again supersedes this one (admin_create_invite()'s own
    // "a resend supersedes rather than piling up dead rows" behaviour), so
    // no compensating-transaction machinery is needed here.
    console.error("send-admin-invite: email send failed", (error as Error).message);
    return jsonResponse(502, {
      error: "the invite was created but the email could not be sent -- try sending it again",
    });
  }

  return jsonResponse(200, { success: true });
});
