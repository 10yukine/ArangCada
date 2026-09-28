// Forwards mail sent to the public contact addresses on the Terms and
// Privacy pages (support@, legal@, privacy@arangcada.app) to a real inbox.
//
// arangcada.app's MX points at Resend receiving, which only STORES mail: the
// email.received webhook carries metadata, not the body. So this fetches the
// message from the Received Emails API and re-sends it through Resend to
// INBOUND_FORWARD_TO, with Reply-To set to the original sender.
//
// Kept free of Deno-only APIs so Node can test it (forward_test.ts).
import { createHmac, timingSafeEqual } from "node:crypto";
import { Buffer } from "node:buffer";

export const MAILBOXES = ["support", "legal", "privacy"] as const;
const DOMAIN = "arangcada.app";
// Same verified sending domain as the invite emails.
export const FORWARD_FROM = "ArangCada Inbox <inbox@info.arangcada.app>";
const API = "https://api.resend.com";

export type Config = { apiKey: string; webhookSecret: string; forwardTo: string };

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

/** Resend signs webhooks with Svix (the Standard Webhooks scheme). */
export function verifySignature(body: string, headers: Headers, secret: string, now = Date.now()): boolean {
  if (!secret) return false;
  const id = headers.get("svix-id") ?? headers.get("webhook-id") ?? "";
  const timestamp = headers.get("svix-timestamp") ?? headers.get("webhook-timestamp") ?? "";
  const signatures = headers.get("svix-signature") ?? headers.get("webhook-signature") ?? "";
  if (!id || !timestamp || !signatures) return false;
  // A captured request cannot be replayed later.
  const age = Math.abs(now / 1000 - Number(timestamp));
  if (!Number.isFinite(age) || age > 300) return false;
  const key = Buffer.from(secret.replace(/^whsec_/, ""), "base64");
  const expected = Buffer.from(
    createHmac("sha256", key).update(`${id}.${timestamp}.${body}`).digest("base64"),
  );
  return signatures.split(" ").some((part) => {
    const candidate = Buffer.from(part.replace(/^v1,/, ""));
    return candidate.length === expected.length && timingSafeEqual(candidate, expected);
  });
}

/** "Name <a@b.c>" or "a@b.c" -> "a@b.c" (lower case). */
export function address(value: string): string {
  return (value.match(/<([^>]+)>/)?.[1] ?? value).trim().toLowerCase();
}

function escapeHtml(value: string): string {
  return value.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

/** The API may return the HTML body as a data: URI (html_format). */
export function decodeHtml(html: string | null | undefined): string | null {
  if (!html) return null;
  const match = html.match(/^data:[^,]*?(;base64)?,(.*)$/s);
  if (!match) return html;
  return match[1]
    ? new TextDecoder().decode(Buffer.from(match[2], "base64"))
    : decodeURIComponent(match[2]);
}

async function resend(config: Config, path: string, init: RequestInit = {}): Promise<Response> {
  return await fetch(`${API}${path}`, {
    ...init,
    signal: AbortSignal.timeout(10_000),
    headers: {
      Authorization: `Bearer ${config.apiKey}`,
      "Content-Type": "application/json",
      ...(init.headers ?? {}),
    },
  });
}

export async function handle(req: Request, config: Config): Promise<Response> {
  if (req.method !== "POST") return json(405, { error: "method not allowed" });
  if (!config.apiKey || !config.webhookSecret || !config.forwardTo) {
    console.error("inbound-email: RESEND_API_KEY, RESEND_INBOUND_WEBHOOK_SECRET or INBOUND_FORWARD_TO is not set");
    return json(500, { error: "not configured" });
  }
  // Forwarding to an address on our own domain would loop back through here.
  const target = address(config.forwardTo);
  if (target.endsWith(`@${DOMAIN}`) || target.endsWith(`.${DOMAIN}`)) {
    console.error("inbound-email: INBOUND_FORWARD_TO must be an outside inbox");
    return json(500, { error: "forward target loops" });
  }

  const body = await req.text();
  if (!verifySignature(body, req.headers, config.webhookSecret)) {
    return json(401, { error: "invalid signature" });
  }
  const event = JSON.parse(body);
  if (event?.type !== "email.received") return json(200, { skipped: "not an email.received event" });
  const data = event.data ?? {};

  const recipients = [...(data.to ?? []), ...(data.cc ?? []), ...(data.received_for ?? [])].map(address);
  const mailbox = recipients.find((r) =>
    MAILBOXES.some((name) => r === `${name}@${DOMAIN}`)
  );
  if (!mailbox) return json(200, { skipped: "not a published contact address" });
  if (address(data.from ?? "") === address(FORWARD_FROM)) {
    return json(200, { skipped: "our own forward" });
  }

  const emailResponse = await resend(config, `/emails/receiving/${encodeURIComponent(data.email_id)}`);
  if (!emailResponse.ok) {
    console.error(`inbound-email: could not fetch the received email (HTTP ${emailResponse.status})`);
    return json(502, { error: "fetch failed" }); // Resend retries the webhook.
  }
  const email = await emailResponse.json();

  let attachments: { filename: string; path: string }[] = [];
  if ((email.attachments ?? data.attachments ?? []).length > 0) {
    const listResponse = await resend(config, `/emails/receiving/${encodeURIComponent(data.email_id)}/attachments`);
    if (!listResponse.ok) {
      console.error(`inbound-email: could not list attachments (HTTP ${listResponse.status})`);
      return json(502, { error: "attachments failed" });
    }
    const list = await listResponse.json();
    attachments = (list.data ?? []).map((a: { filename?: string; download_url: string }) => ({
      filename: a.filename ?? "attachment",
      path: a.download_url,
    }));
  }

  const sender = email.headers?.from ?? email.from ?? data.from ?? "unknown sender";
  const subject = email.subject ?? data.subject ?? "(no subject)";
  const note = `Sent to ${mailbox} by ${sender}. Replying answers the sender directly.`;
  const html = decodeHtml(email.html);
  const text = email.text ?? null;

  const sendResponse = await resend(config, "/emails", {
    method: "POST",
    // Resend retries webhooks; one received email is forwarded once.
    headers: { "Idempotency-Key": `inbound-${data.email_id}` },
    body: JSON.stringify({
      from: FORWARD_FROM,
      to: [config.forwardTo],
      reply_to: address(email.from ?? data.from ?? "") || undefined,
      subject: `[${mailbox}] ${subject}`,
      html: `<p style="margin:0 0 16px;padding:10px 12px;background:#eef3fa;border-radius:8px;font:13px Arial,sans-serif;color:#40546f">${escapeHtml(note)}</p>${
        html ?? `<pre style="white-space:pre-wrap;font:14px Arial,sans-serif">${escapeHtml(text ?? "")}</pre>`
      }`,
      text: `${note}\n\n${text ?? "(This message has no plain-text part. Open the HTML version.)"}`,
      ...(attachments.length ? { attachments } : {}),
    }),
  });
  if (!sendResponse.ok) {
    console.error(`inbound-email: Resend rejected the forward (HTTP ${sendResponse.status})`, await sendResponse.text());
    return json(502, { error: "forward failed" });
  }
  return json(200, { forwarded: mailbox });
}
