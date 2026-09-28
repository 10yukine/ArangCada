// Run: node --test supabase/functions/inbound-email/forward_test.ts
import { test } from "node:test";
import { strict as assert } from "node:assert";
import { createHmac } from "node:crypto";
import { Buffer } from "node:buffer";
import { decodeHtml, FORWARD_FROM, handle } from "./forward.ts";

const secret = "whsec_" + Buffer.from("synthetic-webhook-key").toString("base64");
const config = { apiKey: "synthetic-key", webhookSecret: secret, forwardTo: "owner@example.test" };

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
  data: { email_id: "em_1", from: "Ana <ana@example.test>", to: [to], subject: "Help", attachments: [], ...extra },
});

function mockFetch(responses: Record<string, unknown>) {
  const calls: { url: string; init: RequestInit }[] = [];
  globalThis.fetch = ((url: string, init: RequestInit = {}) => {
    calls.push({ url, init });
    const key = Object.keys(responses).find((k) => url.endsWith(k))!;
    return Promise.resolve(new Response(JSON.stringify(responses[key] ?? {}), { status: 200 }));
  }) as typeof fetch;
  return calls;
}

test("forwards privacy@ mail with reply-to, subject tag and attachments", async () => {
  const calls = mockFetch({
    "/emails/receiving/em_1": {
      from: "ana@example.test", subject: "Delete my data", html: "<p>Please delete</p>", text: "Please delete",
      headers: { from: "Ana <ana@example.test>" }, attachments: [{ id: "a1" }],
    },
    "/emails/receiving/em_1/attachments": { data: [{ filename: "id.pdf", download_url: "https://cdn.example.test/a1" }] },
    "/emails": { id: "sent" },
  });
  const res = await handle(signed(received("Privacy <PRIVACY@arangcada.app>")), config);
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), { forwarded: "privacy@arangcada.app" });
  const send = calls.at(-1)!;
  assert.equal(send.url, "https://api.resend.com/emails");
  assert.equal((send.init.headers as Record<string, string>)["Idempotency-Key"], "inbound-em_1");
  const payload = JSON.parse(send.init.body as string);
  assert.equal(payload.from, FORWARD_FROM);
  assert.deepEqual(payload.to, ["owner@example.test"]);
  assert.equal(payload.reply_to, "ana@example.test");
  assert.equal(payload.subject, "[privacy@arangcada.app] Delete my data");
  assert.match(payload.html, /Sent to privacy@arangcada\.app by Ana &lt;ana@example\.test&gt;/);
  assert.match(payload.html, /<p>Please delete<\/p>/);
  assert.deepEqual(payload.attachments, [{ filename: "id.pdf", path: "https://cdn.example.test/a1" }]);
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
