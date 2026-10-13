import { strict as assert } from "node:assert";

async function load(mode?: string) {
  const originalServe = Deno.serve;
  const names = ['SMS_HOOK_MODE', 'SEND_SMS_HOOK_SECRET'];
  const previous = names.map(name => Deno.env.get(name));
  let handler: (req: Request) => Promise<Response> = () => { throw new Error('handler not loaded'); };
  try {
    if (mode === undefined) Deno.env.delete('SMS_HOOK_MODE');
    else Deno.env.set('SMS_HOOK_MODE', mode);
    Deno.env.delete('SEND_SMS_HOOK_SECRET');
    Deno.serve = ((fn: typeof handler) => { handler = fn; return {}; }) as unknown as typeof Deno.serve;
    await import(`./index.ts?test=${crypto.randomUUID()}`);
    return handler;
  } finally {
    Deno.serve = originalServe;
    names.forEach((name, i) => previous[i] === undefined ? Deno.env.delete(name) : Deno.env.set(name, previous[i]!));
  }
}
const request = (body: unknown) => new Request('https://example.test', {method: 'POST', body: JSON.stringify(body)});

Deno.test('SMS delivery fails closed when mode is missing or misspelled', async () => {
  for (const mode of [undefined, 'liv']) {
    assert.equal((await (await load(mode))(request({}))).status, 500);
  }
});
Deno.test('stub rejects malformed payloads and never logs OTPs', async () => {
  const handler = await load('stub');
  for (const body of [null, {}, {user: {phone: 123}, sms: {otp: '654321'}}, {user: {phone: '+639171234567'}, sms: {otp: 'malformed'}}]) {
    assert.equal((await handler(request(body))).status, 400);
  }
  const originalLog = console.log;
  const logs: string[] = [];
  try {
    console.log = (...values) => { logs.push(values.join(' ')); };
    assert.equal((await handler(request({user: {id: 'test', new_phone: '+639171234567'}, sms: {otp: '654321'}}))).status, 200);
  } finally { console.log = originalLog; }
  assert.equal(logs.length, 1);
  assert.ok(!logs[0].includes('654321'));
  assert.ok(!logs[0].includes('+639171234567'));
});
Deno.test('live mode rejects unsigned requests', async () => {
  assert.equal((await (await load('live'))(request({}))).status, 401);
});
Deno.test('email mode refuses unsigned requests like live mode', async () => {
  assert.equal((await (await load('email'))(request({}))).status, 401);
});
Deno.test('a send without a permit from the resend schedule is refused', async () => {
  const originalFetch = globalThis.fetch;
  const calls: string[] = [];
  Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', 'service');
  Deno.env.set('SUPABASE_URL', 'https://db.example.test');
  try {
    globalThis.fetch = ((input: string | URL) => {
      calls.push(String(input));
      return Promise.resolve(new Response('false', { status: 200 }));
    }) as typeof fetch;
    const handler = await load('stub');
    const res = await handler(request({user: {id: 'u1', new_phone: '+639171234567'}, sms: {otp: '654321'}}));
    assert.equal(res.status, 429);
    assert.equal(calls.length, 1);
    assert.ok(calls[0].endsWith('/rest/v1/rpc/otp_consume_permit'));
  } finally {
    globalThis.fetch = originalFetch;
    Deno.env.delete('SUPABASE_SERVICE_ROLE_KEY');
    Deno.env.delete('SUPABASE_URL');
  }
});

// Live mode, signed the way Supabase Auth signs. What reaches Semaphore must be
// the sender name and the sample the telcos approved (request #29111), and
// nothing may go out past the pilot's limits.
const hookSecret = btoa('test-secret-bytes');
const liveEnv = {
  SMS_HOOK_MODE: 'live',
  SEND_SMS_HOOK_SECRET: `v1,whsec_${hookSecret}`,
  SEMAPHORE_API_KEY: 'key',
  SEMAPHORE_SENDER_NAME: 'Arangcada',
  SUPABASE_URL: 'https://db.example.test',
  SUPABASE_SERVICE_ROLE_KEY: 'service',
};
const codeRequest = {user: {id: 'u1', new_phone: '+639171234567'}, sms: {otp: '654321'}};

async function signed(body: unknown) {
  const text = JSON.stringify(body);
  const id = 'msg_1';
  const timestamp = String(Math.floor(Date.now() / 1000));
  const key = await crypto.subtle.importKey(
    'raw', Uint8Array.from(atob(hookSecret), c => c.charCodeAt(0)),
    {name: 'HMAC', hash: 'SHA-256'}, false, ['sign']);
  const mac = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(`${id}.${timestamp}.${text}`));
  return new Request('https://example.test', {
    method: 'POST',
    body: text,
    headers: {
      'webhook-id': id,
      'webhook-timestamp': timestamp,
      'webhook-signature': `v1,${btoa(String.fromCharCode(...new Uint8Array(mac)))}`,
    },
  });
}

/** Sends one signed code request in live mode; `permit` is what the database answers. */
async function sendLive(env: Record<string, string>, permit: string) {
  const originalServe = Deno.serve;
  const originalFetch = globalThis.fetch;
  const names = Object.keys(liveEnv);
  const previous = names.map(name => Deno.env.get(name));
  const calls: {url: string; body: string}[] = [];
  let handler: (req: Request) => Promise<Response> = () => { throw new Error('handler not loaded'); };
  try {
    names.forEach(name => name in env ? Deno.env.set(name, env[name]) : Deno.env.delete(name));
    Deno.serve = ((fn: typeof handler) => { handler = fn; return {}; }) as unknown as typeof Deno.serve;
    globalThis.fetch = ((input: string | URL, init?: RequestInit) => {
      calls.push({url: String(input), body: String(init?.body ?? '')});
      return Promise.resolve(new Response(
        String(input).includes('/rest/v1/rpc/') ? JSON.stringify(permit) : '[{"status":"Pending"}]',
        {status: 200}));
    }) as typeof fetch;
    await import(`./index.ts?test=${crypto.randomUUID()}`);
    const res = await handler(await signed(codeRequest));
    return {res, calls};
  } finally {
    Deno.serve = originalServe;
    globalThis.fetch = originalFetch;
    names.forEach((name, i) => previous[i] === undefined ? Deno.env.delete(name) : Deno.env.set(name, previous[i]!));
  }
}

Deno.test('a live text is the approved sample under the approved sender name', async () => {
  const {res, calls} = await sendLive(liveEnv, 'ok');
  assert.equal(res.status, 200);
  assert.equal(calls.length, 2);
  assert.ok(calls[0].url.endsWith('/rest/v1/rpc/sms_send_permit'));
  assert.equal(calls[1].url, 'https://api.semaphore.co/api/v4/priority');
  const sent = new URLSearchParams(calls[1].body);
  assert.equal(sent.get('sendername'), 'Arangcada');
  assert.equal(sent.get('number'), '639171234567');
  assert.equal(
    sent.get('message'),
    'Arangcada: Your ArangCada verification code is 654321. Do not share this code with anyone.',
  );
});
Deno.test('live mode without the sender name sends nothing and spends no permit', async () => {
  const {SEMAPHORE_SENDER_NAME: _, ...unnamed} = liveEnv;
  const {res, calls} = await sendLive(unnamed, 'ok');
  assert.equal(res.status, 500);
  assert.equal(calls.length, 0);
});
Deno.test('a text past the pilot limits is refused and not sent', async () => {
  for (const reason of ['recipient_cap', 'account_cap', 'month_cap', 'ended', 'no_permit']) {
    const {res, calls} = await sendLive(liveEnv, reason);
    assert.equal(res.status, 429);
    assert.equal(calls.length, 1);
    assert.ok((await res.json()).error.message.length > 10);
  }
});
