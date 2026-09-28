// Forwards mail sent to the public contact addresses on the Terms and
// Privacy pages (support@, legal@, privacy@arangcada.app) to a real inbox.
//
// arangcada.app's MX points at Resend receiving, which only STORES mail: the
// email.received webhook carries metadata, not the body. So this fetches the
// message from the Received Emails API and re-sends it through Resend to
// INBOUND_FORWARD_TO. Gmail replies return through a private address so the
// customer sees the matching public mailbox rather than the owner's Gmail.
//
// Kept free of Deno-only APIs so Node can test it (forward_test.ts).
import { createHmac, timingSafeEqual } from "node:crypto";
import { Buffer } from "node:buffer";

export const MAILBOXES = ["support", "legal", "privacy"] as const;
const DOMAIN = "arangcada.app";
// Same verified sending domain as the invite emails.
export const FORWARD_FROM = "ArangCada Inbox <inbox@info.arangcada.app>";
const API = "https://api.resend.com";

export type Config = {
  apiKey: string; webhookSecret: string; forwardTo: string;
  supabaseUrl: string; serviceRoleKey: string;
};

type Route = {
  inbound_email_id: string; customer_email: string; mailbox: string;
  original_subject: string; original_message_id: string | null;
};

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const MESSAGE_ID = /^<[^<>\r\n]{1,200}>$/;

function replyAddress(id: string, secret: string): string {
  const signature = createHmac("sha256", secret).update(`contact-reply:${id}`).digest("hex").slice(0, 16);
  return `reply+${id}.${signature}@${DOMAIN}`;
}

function replyId(recipient: string, secret: string): string | null {
  const match = recipient.match(/^reply\+([0-9a-f-]{36})\.([0-9a-f]{16})@arangcada\.app$/i);
  if (!match || !UUID.test(match[1])) return null;
  const expected = replyAddress(match[1].toLowerCase(), secret);
  const received = Buffer.from(recipient.toLowerCase());
  const valid = Buffer.from(expected);
  return received.length === valid.length && timingSafeEqual(received, valid) ? match[1].toLowerCase() : null;
}

async function routeStore(config: Config, id: string, route?: Route): Promise<Response> {
  const url = new URL(`${config.supabaseUrl}/rest/v1/contact_email_reply_routes`);
  if (!route) url.searchParams.set("inbound_email_id", `eq.${id}`);
  if (!route) url.searchParams.set("select", "customer_email,mailbox,original_subject,original_message_id");
  return await fetch(url, {
    method: route ? "POST" : "GET",
    signal: AbortSignal.timeout(10_000),
    headers: {
      apikey: config.serviceRoleKey,
      Authorization: `Bearer ${config.serviceRoleKey}`,
      "Content-Type": "application/json",
      ...(route ? { Prefer: "resolution=merge-duplicates" } : {}),
    },
    ...(route ? { body: JSON.stringify(route) } : {}),
  });
}

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
  if (!config.apiKey || !config.webhookSecret || !config.forwardTo || !config.supabaseUrl || !config.serviceRoleKey) {
    console.error("inbound-email: required email or Supabase configuration is not set");
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
  const replyRecipient = recipients.find((r) => r.startsWith("reply+"));
  if (replyRecipient) {
    const id = replyId(replyRecipient, config.webhookSecret);
    if (!id || address(data.from ?? "") !== target) {
      return json(200, { skipped: "invalid reply route or sender" });
    }
    const routeResponse = await routeStore(config, id);
    if (!routeResponse.ok) return json(502, { error: "reply route lookup failed" });
    const route = (await routeResponse.json() as Route[])[0];
    if (!route) return json(200, { skipped: "unknown reply route" });
    const replyResponse = await resend(config, `/emails/receiving/${encodeURIComponent(data.email_id)}`);
    if (!replyResponse.ok) return json(502, { error: "reply fetch failed" });
    const reply = await replyResponse.json();
    if (address(reply.from ?? "") !== target) return json(200, { skipped: "reply sender mismatch" });
    // ponytail: handles this Gmail account's English quote markers; use MIME parsing if its locale changes.
    const answer = String(reply.text ?? "")
      .split(/^On .+wrote:\s*$/m)[0]
      .split(/^On (?:Mon|Tue|Wed|Thu|Fri|Sat|Sun), .+$/m)[0]
      .split(/^[- ]*Original Message[- ]*$/im)[0]
      .split(/^\s*>?\s*Sent to (?:support|legal|privacy)@arangcada\.app by /m)[0]
      .split(/^>/m)[0].trim();
    if (!answer) return json(502, { error: "reply has no plain-text answer" });
    let attachments: { filename: string; path: string }[] = [];
    if ((reply.attachments ?? data.attachments ?? []).length > 0) {
      const listResponse = await resend(config, `/emails/receiving/${encodeURIComponent(data.email_id)}/attachments`);
      if (!listResponse.ok) return json(502, { error: "reply attachments failed" });
      const list = await listResponse.json();
      attachments = (list.data ?? []).map((a: { filename?: string; download_url: string }) => ({
        filename: a.filename ?? "attachment", path: a.download_url,
      }));
    }
    const headers = route.original_message_id && MESSAGE_ID.test(route.original_message_id)
      ? { "In-Reply-To": route.original_message_id, References: route.original_message_id }
      : undefined;
    const sent = await resend(config, "/emails", {
      method: "POST",
      headers: { "Idempotency-Key": `contact-reply-${data.email_id}` },
      body: JSON.stringify({
        from: route.mailbox,
        to: [route.customer_email],
        reply_to: route.mailbox,
        subject: /^re:/i.test(route.original_subject) ? route.original_subject : `Re: ${route.original_subject}`,
        text: answer,
        ...(headers ? { headers } : {}),
        ...(attachments.length ? { attachments } : {}),
      }),
    });
    if (!sent.ok) {
      console.error(`inbound-email: Resend rejected reply (HTTP ${sent.status})`, await sent.text());
      return json(502, { error: "reply send failed" });
    }
    return json(200, { replied: route.mailbox });
  }
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
  const customer = address(email.from ?? data.from ?? "");
  if (!UUID.test(data.email_id ?? "") || !/^[^\s@<>]+@[^\s@<>]+$/.test(customer)) {
    return json(200, { skipped: "invalid email identity" });
  }
  const route: Route = {
    inbound_email_id: data.email_id,
    customer_email: customer,
    mailbox,
    original_subject: subject,
    original_message_id: MESSAGE_ID.test(email.message_id ?? data.message_id ?? "")
      ? (email.message_id ?? data.message_id) : null,
  };
  const stored = await routeStore(config, data.email_id, route);
  if (!stored.ok) return json(502, { error: "reply route storage failed" });

  const note = `Sent to ${mailbox} by ${sender}. Reply in Gmail to answer from ${mailbox}.`;
  const html = decodeHtml(email.html);
  const text = email.text ?? null;

  const sendResponse = await resend(config, "/emails", {
    method: "POST",
    // Resend retries webhooks; one received email is forwarded once.
    headers: { "Idempotency-Key": `inbound-${data.email_id}` },
    body: JSON.stringify({
      from: FORWARD_FROM,
      to: [config.forwardTo],
      reply_to: replyAddress(data.email_id.toLowerCase(), config.webhookSecret),
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
