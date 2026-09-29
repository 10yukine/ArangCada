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
