import { CORS_HEADERS, jsonResponse } from "../_shared/http.ts";
import { sendInviteEmail } from "../_shared/invite_email.ts";
// send-driver-invite -- an LGU administrator invites a new driver by email.
//
// See .pipeline/specs.md Spec 20. Mirrors send-admin-invite (Spec 19)
// closely on purpose -- same shape, same risks, and every lesson that
// function's own live debugging surfaced is applied here from the start
// rather than rediscovered: CORS headers from the first deploy (their
// absence is what silently broke the admin invite from a real browser the
// first time), and user_metadata (never app_metadata) for anything
// handle_new_user() needs to read.
//
// WHAT THIS FUNCTION DOES AND DOES NOT DO
//
//   * Verifies the caller with a client scoped to the caller's OWN JWT --
//     never the service-role key.
//   * Calls admin_create_driver_invite() on that same caller-scoped client.
//     That RPC is the actual source of truth for "is this caller an LGU
//     admin, is the email valid, is the TODA zone active, does an account
//     already exist for this email" -- this function does not re-implement
//     any of that.
//   * Sends the invite email itself, via a direct fetch() to Resend's HTTP
//     API -- no SDK, same shape send-sms-hook/send-admin-invite both use.
//   * Never touches the service-role key. Account creation happens later,
//     in accept-driver-invite, once the driver accepts.

import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY") ?? "";
const ADMIN_WEB_BASE_URL = "https://admin.arangcada.app";

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
  if (!supabaseUrl || !anonKey || !RESEND_API_KEY) {
    console.error("send-driver-invite: missing required configuration");
    return jsonResponse(500, { error: "server misconfigured" });
  }

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return jsonResponse(400, { error: "request body must be valid JSON" });
  }

  const { email, toda_zone_id: todaZoneId, body_number: bodyNumber } = (body ?? {}) as {
    email?: unknown;
    toda_zone_id?: unknown;
    body_number?: unknown;
  };
  if (typeof email !== "string" || email.trim() === "") {
    return jsonResponse(400, { error: "email is required" });
  }
  if (typeof todaZoneId !== "string" || todaZoneId.trim() === "") {
    return jsonResponse(400, { error: "toda_zone_id is required" });
  }

  const callerClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });

  const { data: token, error: inviteError } = await callerClient.rpc("admin_create_driver_invite", {
    p_email: email,
    p_toda_zone_id: todaZoneId,
    p_body_number: typeof bodyNumber === "string" && bodyNumber.trim() !== "" ? bodyNumber : null,
  });

  if (inviteError || typeof token !== "string") {
    const status = inviteError?.code === "42501" ? 403 : 400;
    console.error("send-driver-invite: admin_create_driver_invite failed", inviteError?.message);
    return jsonResponse(status, {
      error: inviteError?.message ?? "could not create the invite",
    });
  }

  const link = `${ADMIN_WEB_BASE_URL}/accept-driver-invite?token=${token}`;

  try {
    await sendInviteEmail("driver", email, link, RESEND_API_KEY);
  } catch (error) {
    // The invite row already exists (admin_create_driver_invite() committed
    // it) but was never delivered. Not rolled back -- sending the same
    // invite again supersedes this one, same as send-admin-invite.
    console.error("send-driver-invite: email send failed", (error as Error).message);
    return jsonResponse(502, {
      error: "the invite was created but the email could not be sent -- try sending it again",
    });
  }

  return jsonResponse(200, { success: true });
});
