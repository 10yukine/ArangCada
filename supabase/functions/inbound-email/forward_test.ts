// Run: node --test supabase/functions/inbound-email/forward_test.ts
import { test } from "node:test";
import { strict as assert } from "node:assert";
import { createHmac } from "node:crypto";
import { Buffer } from "node:buffer";
import { decodeHtml, FORWARD_FROM, handle } from "./forward.ts";

const secret = "whsec_" + Buffer.from("synthetic-webhook-key").toString("base64");
const config = {
  apiKey: "synthetic-key", webhookSecret: secret, forwardTo: "owner@example.test",
  supabaseUrl: "https://db.example.test", serviceRoleKey: "synthetic-service-key",
};
const emailId = "11111111-1111-4111-8111-111111111111";

function signed(payload: unknown, sign = secret): Request {
  const body = JSON.stringify(payload);
  const id = "msg_1";
  const ts = String(Math.floor(Date.now() / 1000));
  const key = Buffer.from(sign.replace(/^whsec_/, ""), "base64");
  const sig = createHmac("sha256", key).update(`${id}.${ts}.${body}`).digest("base64");
  return new Request("https://fn.example.test", {
    method: "POST",
    body,
    headers: { "svix-id": id, "svix-timestamp": ts, "svix-signature": `v1,${sig}` },
  });
}

const received = (to: string, extra: Record<string, unknown> = {}) => ({
  type: "email.received",
  data: { email_id: emailId, from: "Ana <ana@example.test>", to: [to], subject: "Help", attachments: [], ...extra },
});

function mockFetch(responses: Record<string, unknown>) {
  const calls: { url: string; init: RequestInit }[] = [];
  globalThis.fetch = ((input: string | URL, init: RequestInit = {}) => {
    const url = String(input);
    calls.push({ url, init });
    const key = Object.keys(responses).find((k) => url.includes(k))!;
    return Promise.resolve(new Response(JSON.stringify(responses[key] ?? {}), { status: 200 }));
  }) as typeof fetch;
  return calls;
}

test("forwards privacy@ mail with private reply route and attachments", async () => {
  const calls = mockFetch({
    [`/emails/receiving/${emailId}/attachments`]: { data: [{ filename: "id.pdf", download_url: "https://cdn.example.test/a1" }] },
    [`/emails/receiving/${emailId}`]: {
      from: "ana@example.test", subject: "Delete my data", html: "<p>Please delete</p>", text: "Please delete",
      headers: { from: "Ana <ana@example.test>" }, message_id: "<original@example.test>", attachments: [{ id: "a1" }],
    },
    "/contact_email_reply_routes": {},
    "/emails": { id: "sent" },
  });
  const res = await handle(signed(received("Privacy <PRIVACY@arangcada.app>")), config);
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), { forwarded: "privacy@arangcada.app" });
  const send = calls.at(-1)!;
  assert.equal(send.url, "https://api.resend.com/emails");
  assert.equal((send.init.headers as Record<string, string>)["Idempotency-Key"], `inbound-${emailId}`);
  const payload = JSON.parse(send.init.body as string);
  assert.equal(payload.from, FORWARD_FROM);
  assert.deepEqual(payload.to, ["owner@example.test"]);
  assert.match(payload.reply_to, new RegExp(`^reply\\+${emailId}\\.[0-9a-f]{16}@arangcada\\.app$`));
  assert.equal(payload.subject, "[privacy@arangcada.app] Delete my data");
  assert.match(payload.html, /Sent to privacy@arangcada\.app by Ana &lt;ana@example\.test&gt;/);
  assert.match(payload.html, /<p>Please delete<\/p>/);
  assert.deepEqual(payload.attachments, [{ filename: "id.pdf", path: "https://cdn.example.test/a1" }]);
  const stored = calls.find((call) => call.url.includes("/contact_email_reply_routes"))!;
  assert.deepEqual(JSON.parse(stored.init.body as string), {
    inbound_email_id: emailId, customer_email: "ana@example.test", mailbox: "privacy@arangcada.app",
    original_subject: "Delete my data", original_message_id: "<original@example.test>",
  });
});

test("Gmail reply sends from the matching mailbox in the customer's thread", async () => {
  const routeAddress = `reply+${emailId}.${createHmac("sha256", secret).update(`contact-reply:${emailId}`).digest("hex").slice(0, 16)}@arangcada.app`;
  const calls = mockFetch({
    "/contact_email_reply_routes": [{ customer_email: "ana@example.test", mailbox: "legal@arangcada.app", original_subject: "Policy", original_message_id: "<original@example.test>" }],
    [`/emails/receiving/${emailId}/attachments`]: { data: [{ filename: "answer.pdf", download_url: "https://cdn.example.test/answer" }] },
    [`/emails/receiving/${emailId}`]: { from: "owner@example.test", text: "We can help.\n\nOn Mon, Sep 28, 2026 at 9:06 PM ArangCada Inbox <inbox@info.arangcada.app>\nwrote:\n> private forwarded note", attachments: [{ id: "a1" }] },
    "/emails": { id: "sent" },
  });
  const res = await handle(signed(received(routeAddress, { from: "owner@example.test" })), config);
  assert.deepEqual(await res.json(), { replied: "legal@arangcada.app" });
  const send = JSON.parse(calls.at(-1)!.init.body as string);
  assert.equal(send.from, "legal@arangcada.app");
  assert.deepEqual(send.to, ["ana@example.test"]);
  assert.equal(send.reply_to, "legal@arangcada.app");
  assert.equal(send.subject, "Re: Policy");
  assert.equal(send.text, "We can help.");
  assert.deepEqual(send.headers, { "In-Reply-To": "<original@example.test>", References: "<original@example.test>" });
  assert.deepEqual(send.attachments, [{ filename: "answer.pdf", path: "https://cdn.example.test/answer" }]);
});

test("rejects guessed reply routes and other senders", async () => {
  const calls = mockFetch({});
  const guessed = await handle(signed(received(`reply+${emailId}.0000000000000000@arangcada.app`, { from: "owner@example.test" })), config);
  assert.equal(guessed.status, 200);
  assert.equal(calls.length, 0);
  const routeAddress = `reply+${emailId}.${createHmac("sha256", secret).update(`contact-reply:${emailId}`).digest("hex").slice(0, 16)}@arangcada.app`;
  const stranger = await handle(signed(received(routeAddress)), config);
  assert.equal(stranger.status, 200);
  assert.equal(calls.length, 0);
});

test("rejects unsigned or wrongly signed webhooks", async () => {
  mockFetch({});
  const bad = await handle(signed(received("support@arangcada.app"), "whsec_" + Buffer.from("other").toString("base64")), config);
  assert.equal(bad.status, 401);
  const unsigned = await handle(new Request("https://fn.example.test", { method: "POST", body: "{}" }), config);
  assert.equal(unsigned.status, 401);
});

test("ignores other addresses and refuses a looping forward target", async () => {
  const calls = mockFetch({});
  const other = await handle(signed(received("random@arangcada.app")), config);
  assert.deepEqual(await other.json(), { skipped: "not a published contact address" });
  assert.equal(calls.length, 0);
  const loop = await handle(signed(received("support@arangcada.app")), { ...config, forwardTo: "me@arangcada.app" });
  assert.equal(loop.status, 500);
});

test("decodes a data: URI html body", () => {
  const html = "<p>Kumusta ñ</p>";
  assert.equal(decodeHtml(`data:text/html;base64,${Buffer.from(html).toString("base64")}`), html);
  assert.equal(decodeHtml(html), html);
  assert.equal(decodeHtml(null), null);
});
