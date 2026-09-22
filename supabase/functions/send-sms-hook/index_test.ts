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
