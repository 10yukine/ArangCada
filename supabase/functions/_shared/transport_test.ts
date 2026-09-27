import { strict as assert } from "node:assert";
import { sendInviteEmail } from "./invite_email.ts";

for (const kind of ["admin", "driver"] as const) {
  Deno.test(`${kind} invite preserves email payload and provider errors`, async () => {
    const originalFetch = globalThis.fetch;
    const originalError = console.error;
    const calls: RequestInit[] = [];
    const logs: unknown[][] = [];
    let fail = false;
    try {
      globalThis.fetch = ((url: string | URL | Request, options?: RequestInit) => {
        assert.equal(url, "https://api.resend.com/emails");
        calls.push(options!);
        return Promise.resolve(new Response(fail ? "provider detail" : "{}", {status: fail ? 429 : 200}));
      }) as typeof fetch;
      console.error = (...values: unknown[]) => { logs.push(values); };
      await sendInviteEmail(kind, "person@example.test", 'https://example.test/?token=<a&b"', "synthetic-key");
      assert.equal(calls[0].method, "POST");
      assert.deepEqual(calls[0].headers, {Authorization: "Bearer synthetic-key", "Content-Type": "application/json"});
      assert.ok(calls[0].signal instanceof AbortSignal);
      const payload = JSON.parse(calls[0].body as string);
      assert.deepEqual({ ...payload, html: undefined, text: undefined }, {
        from: "ArangCada <services@info.arangcada.app>",
        to: ["person@example.test"],
        subject: kind === "admin" ? "You're invited to the ArangCada admin console" : "You're invited to drive for ArangCada",
        html: undefined,
        text: undefined,
      });
      assert.match(payload.html, /You're invited to ArangCada/);
      assert.match(payload.html, /https:\/\/arangcada\.app\/apple-touch-icon\.png/);
      assert.match(payload.html, new RegExp(kind === "admin" ? "LGU/TODA administrator" : "as a driver"));
      assert.match(payload.html, /Create your account/);
      assert.match(payload.html, /expires in 7 days/);
      assert.equal((payload.html.match(/href="https:\/\/example\.test\/\?token=&lt;a&amp;b&quot;"/g) ?? []).length, 2);
      assert.ok(!payload.html.includes('href="https://example.test/?token=<a&b"'));
      assert.match(payload.text, /https:\/\/example\.test\/\?token=<a&b"/);
      fail = true;
      await assert.rejects(sendInviteEmail(kind, "person@example.test", "link", "synthetic-key"), {message: "Resend HTTP 429"});
      assert.deepEqual(logs, [[`send-${kind}-invite: Resend rejected the send (HTTP 429)`, "provider detail"]]);
    } finally {
      globalThis.fetch = originalFetch;
      console.error = originalError;
    }
  });
}

for (const name of ["admin-onboard-driver", "send-admin-invite", "send-driver-invite", "accept-admin-invite", "accept-driver-invite"]) {
  Deno.test(`${name} retains preflight and rejection responses`, async () => {
    const originalServe = Deno.serve;
    const names = ["SUPABASE_URL", "SUPABASE_ANON_KEY", "SUPABASE_SERVICE_ROLE_KEY", "RESEND_API_KEY", "SET_PASSWORD_REDIRECT_URL"];
    const previous = names.map(key => Deno.env.get(key));
    let handler: (req: Request) => Promise<Response> = () => { throw new Error("missing handler"); };
    try {
      names.forEach(key => Deno.env.delete(key));
      Deno.serve = ((fn: typeof handler) => { handler = fn; return {}; }) as unknown as typeof Deno.serve;
      await import(`../${name}/index.ts`);
      for (const method of ["OPTIONS", "GET", "POST"]) {
        const response = await handler(new Request("https://example.test", {method}));
        assert.equal(response.headers.get("Access-Control-Allow-Origin"), "*");
        assert.equal(response.headers.get("Access-Control-Allow-Headers"), "authorization, x-client-info, apikey, content-type");
        assert.equal(response.headers.get("Access-Control-Allow-Methods"), "POST, OPTIONS");
        if (method === "OPTIONS") {
          assert.equal(response.status, 200);
          assert.equal(await response.text(), "ok");
        } else {
          assert.equal(response.headers.get("content-type"), "application/json");
          const accepting = name.startsWith("accept-");
          assert.equal(response.status, method === "GET" ? 405 : accepting ? 500 : 401);
          assert.deepEqual(await response.json(), {error: method === "GET" ? "method not allowed" : accepting ? "server misconfigured" : "missing Authorization header"});
        }
      }
    } finally {
      Deno.serve = originalServe;
      names.forEach((key, i) => previous[i] === undefined ? Deno.env.delete(key) : Deno.env.set(key, previous[i]!));
    }
  });
}
