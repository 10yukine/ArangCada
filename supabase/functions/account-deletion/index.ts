import { createClient } from "npm:@supabase/supabase-js@2.45.4";
import { escapeHtml, hashToken, newToken, validToken } from "./helpers.ts";

const url = Deno.env.get("SUPABASE_URL") ?? "";
const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const resendKey = Deno.env.get("RESEND_API_KEY") ?? "";
const origin = "https://arangcada.app/delete-account";
const service = url && serviceKey ? createClient(url, serviceKey) : null;
const cors = {
  "access-control-allow-origin": origin.replace("/delete-account", ""),
  "access-control-allow-methods": "POST, OPTIONS",
  "access-control-allow-headers": "authorization, apikey, content-type",
};

function json(status: number, value: Record<string, unknown>): Response {
  return new Response(JSON.stringify(value), {
    status,
    headers: { ...cors, "content-type": "application/json", "cache-control": "no-store" },
  });
}

async function sendEmail(to: string, subject: string, html: string): Promise<void> {
  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    signal: AbortSignal.timeout(10_000),
    headers: { Authorization: `Bearer ${resendKey}`, "Content-Type": "application/json" },
    body: JSON.stringify({ from: "ArangCada <services@info.arangcada.app>", to: [to], subject, html }),
  });
  if (!response.ok) throw new Error(`Resend HTTP ${response.status}`);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });
  if (req.method !== "POST") return json(405, { error: "method not allowed" });
  if (!url || !anonKey || !service || !resendKey) return json(500, { error: "service unavailable" });
  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "invalid JSON" });
  }
  if (body.token !== undefined) {
    if (!validToken(body.token)) return json(400, { error: "invalid link" });
    const token = body.token;
    let { data, error } = await service.from("account_deletion_requests")
      .update({ status: "confirmed", confirmed_at: new Date().toISOString() })
      .eq("token_hash", await hashToken(token)).eq("status", "pending_email")
      .gt("expires_at", new Date().toISOString()).select("id,email").maybeSingle();
    if (!error && !data) {
      const retry = await service.from("account_deletion_requests").select("id,email")
        .eq("token_hash", await hashToken(token)).eq("status", "confirmed")
        .is("notified_at", null).gt("expires_at", new Date().toISOString()).maybeSingle();
      data = retry.data;
      error = retry.error;
    }
    if (error || !data) return json(410, { error: "link expired or already used" });
    try {
      await sendEmail("privacy@arangcada.app", "Verified account deletion request", `<p>Request ${data.id} was confirmed by ${escapeHtml(data.email)}.</p><p>Review active trips and retention obligations, process deletion, then reply to the requester.</p>`);
      await service.from("account_deletion_requests").update({ notified_at: new Date().toISOString() }).eq("id", data.id);
    } catch (error) {
      console.error("account-deletion: privacy notification failed", error);
      return json(503, { error: "request saved, but notification failed; retry this link or email privacy@arangcada.app", request_id: data.id });
    }
    return json(200, { success: true });
  }

  const jwt = req.headers.get("authorization")?.replace(/^Bearer /i, "") ?? "";
  if (!jwt) return json(401, { error: "sign in first" });
  const caller = createClient(url, anonKey, { global: { headers: { Authorization: `Bearer ${jwt}` } } });
  const { data: { user }, error: authError } = await caller.auth.getUser(jwt);
  if (authError || !user?.email) return json(401, { error: "sign in first" });
  const { data: recent } = await service.from("account_deletion_requests").select("id")
    .eq("user_id", user.id).eq("status", "pending_email")
    .gt("requested_at", new Date(Date.now() - 5 * 60_000).toISOString()).maybeSingle();
  if (recent) return json(200, { success: true });
  const token = newToken();
  const { data: request, error: insertError } = await service.from("account_deletion_requests")
    .insert({ user_id: user.id, email: user.email, token_hash: await hashToken(token) }).select("id").single();
  if (insertError) return json(500, { error: "could not create request" });
  const link = `${origin}?token=${token}`;
  const html = `<!doctype html><html lang="en"><body style="margin:0;padding:0;background:#eef3fa;font-family:Arial,sans-serif;color:#17305b"><table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr><td align="center" style="padding:40px 16px"><table role="presentation" width="100%" style="max-width:560px"><tr><td align="center" style="padding-bottom:22px"><img src="https://arangcada.app/apple-touch-icon.png" width="64" height="64" alt="ArangCada logo" style="border-radius:14px;vertical-align:middle"> <strong style="font-size:22px">ArangCada</strong></td></tr><tr><td style="background:white;border:1px solid #d8e3f0;border-radius:18px;padding:40px 36px"><p style="color:#b42318;font-size:12px;font-weight:bold;letter-spacing:1.5px;text-transform:uppercase">Account privacy</p><h1>Confirm account deletion</h1><p style="color:#40546f;line-height:1.65">We received a request to delete your ArangCada account. Confirm it using the button below. We review trip and safety records that must be retained and email you when processing is complete.</p><p style="text-align:center;margin:32px 0"><a href="${link}" style="display:inline-block;background:#b42318;color:white;border-radius:10px;padding:16px 24px;text-decoration:none;font-weight:bold">Confirm deletion request</a></p><p style="color:#63758f;font-size:12px">This link expires in 24 hours. If you did not request this, ignore this email; your account will stay active.</p></td></tr><tr><td align="center" style="padding:22px;color:#71819a;font-size:12px">ArangCada · Calamba City</td></tr></table></td></tr></table></body></html>`;
  try {
    await sendEmail(user.email, "Confirm your ArangCada account deletion request", html);
  } catch (error) {
    console.error("account-deletion: confirmation email failed", error);
    await service.from("account_deletion_requests").delete().eq("id", request.id);
    return json(502, { error: "could not send email" });
  }
  return json(200, { success: true });
});
