// Run: node --test supabase/functions/account-deletion/delete_test.ts
import { test } from "node:test";
import { strict as assert } from "node:assert";
import { credential, handle } from "./delete.ts";

const config = {
  supabaseUrl: "https://db.example.test", anonKey: "anon", serviceRoleKey: "service",
  turnstileSecret: "turnstile-secret", resendKey: "resend-key",
};
const uid = "11111111-1111-4111-8111-111111111111";
const passed: Record<string, [number, unknown]> = { "siteverify": [200, { success: true }] };

function mockFetch(routes: Record<string, [number, unknown]>) {
  const calls: { url: string; init: RequestInit }[] = [];
  globalThis.fetch = ((input: string | URL, init: RequestInit = {}) => {
    const url = String(input);
    calls.push({ url, init });
    const key = Object.keys(routes).find((k) => url.includes(k));
    const [status, body] = key ? routes[key] : [200, []];
    return Promise.resolve(new Response(JSON.stringify(body), { status }));
  }) as typeof fetch;
  return calls;
}

const post = (body: unknown, headers: Record<string, string> = {}) =>
  new Request("https://fn.example.test", { method: "POST", body: JSON.stringify(body), headers });
const web = (body: Record<string, unknown>) => post({ ...body, turnstile: "cf-token" });

test("credential accepts an email or a PH mobile number", () => {
  assert.deepEqual(credential(" Ana@Example.test "), { email: "ana@example.test" });
  for (const n of ["09171234567", "9171234567", "+639171234567", "63 917 123 4567"]) {
    assert.deepEqual(credential(n), { phone: "+639171234567" });
  }
  assert.equal(credential("0917123"), null);
  assert.equal(credential("not an email@"), null);
});

test("without a session or a passed Turnstile check, no sign-in is attempted", async () => {
  const calls = mockFetch({ "siteverify": [200, { success: false }] });
  const res = await handle(web({ identifier: "ana@example.test", password: "guess" }), config);
  assert.equal(res.status, 403);
  assert.ok(!calls.some((c) => c.url.includes("/auth/v1/token")));
  const noToken = await handle(post({ identifier: "ana@example.test", password: "guess" }), config);
  assert.equal(noToken.status, 403);
});

test("a wrong password deletes nothing", async () => {
  const calls = mockFetch({ ...passed, "/auth/v1/token": [400, { error: "invalid_grant" }] });
  const res = await handle(web({ identifier: "ana@example.test", password: "wrong" }), config);
  assert.equal(res.status, 401);
  assert.ok(!calls.some((c) => c.url.includes("delete_account")));
});

test("an app session can only delete its own account", async () => {
  const calls = mockFetch({
    "/auth/v1/user": [200, { id: "22222222-2222-4222-8222-222222222222" }],
    "/auth/v1/token": [200, { user: { id: uid } }],
  });
  const res = await handle(
    post({ identifier: "ana@example.test", password: "pw" }, { Authorization: "Bearer session-jwt" }),
    config,
  );
  assert.equal(res.status, 401);
  assert.ok(!calls.some((c) => c.url.includes("delete_account") || c.url.includes("siteverify")));
});

test("a blocker from the database reaches the person", async () => {
  mockFetch({
    ...passed,
    "/auth/v1/token": [200, { user: { id: uid } }],
    "delete_account": [400, { code: "55000", message: "Finish or cancel your current ride first." }],
  });
  const res = await handle(web({ identifier: "ana@example.test", password: "pw" }), config);
  assert.equal(res.status, 409);
  assert.equal((await res.json()).error, "Finish or cancel your current ride first.");
});

test("the app deletes its own account, then its files, then emails a notice", async () => {
  const calls = mockFetch({
    "/auth/v1/user": [200, { id: uid }],
    "/auth/v1/token": [200, { user: { id: uid, email: "ana@example.test" } }],
    "delete_account": [200, { "trip-voice-notes": ["t/u/m.m4a"], "profile-photos": [`${uid}/a.jpg`] }],
    "/object/list/profile-photos": [200, [{ id: "x", name: "a.jpg" }, { id: "y", name: "b.jpg" }]],
  });
  const res = await handle(
    post({ identifier: "09171234567", password: "pw" }, { Authorization: "Bearer session-jwt" }),
    config,
  );
  assert.equal(res.status, 200);
  assert.ok(!calls.some((c) => c.url.includes("siteverify")), "the app path needs no Turnstile");
  const signIn = calls.find((c) => c.url.includes("/auth/v1/token"))!;
  assert.deepEqual(JSON.parse(String(signIn.init.body)), { phone: "+639171234567", password: "pw" });
  assert.deepEqual(JSON.parse(String(calls.find((c) => c.url.includes("delete_account"))!.init.body)), { p_user_id: uid });
  const removals = calls.filter((c) => c.init.method === "DELETE").map((c) => [c.url.split("/").pop(), JSON.parse(String(c.init.body)).prefixes]);
  assert.deepEqual(removals, [
    ["trip-voice-notes", ["t/u/m.m4a"]],
    ["profile-photos", [`${uid}/a.jpg`, `${uid}/b.jpg`]],
  ]);
  const notice = calls.find((c) => c.url.includes("api.resend.com"))!;
  assert.deepEqual(JSON.parse(String(notice.init.body)).to, ["ana@example.test"]);
});

test("rejects missing credentials without calling anything", async () => {
  const calls = mockFetch({});
  assert.equal((await handle(post({ identifier: "ana@example.test" }), config)).status, 400);
  assert.equal(calls.length, 0);
});
