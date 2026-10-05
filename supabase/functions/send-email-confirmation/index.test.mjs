import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { test } from 'node:test';
import vm from 'node:vm';

// Runs the real handler with Supabase and the mail sender mocked. It does not
// replace a check against the deployed function.
const source = stripTypeScriptTypes(
  readFileSync(new URL('./index.ts', import.meta.url), 'utf8')
    .replace(/^import .*from .*;\s*$/gm, ''),
);

function setup({ user = { id: 'user-1' }, userError = null, email = 'rider@example.test',
  rpcError = null, configured = true, mailFails = false } = {}) {
  let handler;
  const calls = [];
  const env = { SUPABASE_URL: 'https://project.example.test', SUPABASE_ANON_KEY: 'synthetic-anon',
    SUPABASE_SERVICE_ROLE_KEY: 'synthetic-service', RESEND_API_KEY: 'synthetic-resend' };
  vm.runInNewContext(source, {
    Deno: { serve: (fn) => { handler = fn; }, env: { get: (key) => configured ? env[key] : undefined } },
    Request, Response, crypto, TextEncoder, btoa, Uint8Array,
    CORS_HEADERS: {}, console: { error() {} },
    jsonResponse: (code, body) => new Response(JSON.stringify(body), { status: code }),
    createClient: (url, key, options) => ({
      auth: { getUser: async () => {
        calls.push({ kind: 'who', key, authorization: options?.global?.headers?.Authorization });
        return { data: { user: userError ? null : user }, error: userError };
      } },
      rpc: async (name, params) => {
        calls.push({ kind: 'rpc', key, name, params });
        return { data: rpcError ? null : email, error: rpcError };
      },
    }),
    sendConfirmationEmail: async (to, link, apiKey) => {
      calls.push({ kind: 'mail', to, link, apiKey });
      if (mailFails) throw new Error('synthetic failure');
    },
  });
  return { calls, request: (auth = 'Bearer synthetic-session', method = 'POST', body = {}) =>
    handler(new Request('https://project.example.test/functions/v1/send-email-confirmation', {
      method, headers: auth ? { Authorization: auth } : {},
      ...(method === 'POST' ? { body: JSON.stringify(body) } : {}),
    })) };
}

test('only a signed-in POST gets anywhere', async () => {
  const app = setup();
  assert.equal((await app.request(null)).status, 401);
  assert.equal((await app.request(null, 'GET')).status, 405);
  assert.equal((await app.request(null, 'OPTIONS')).status, 200);
  assert.equal(app.calls.length, 0);
  assert.equal((await setup({ configured: false }).request()).status, 500);
});

test('an unrecognised session makes no link and sends nothing', async () => {
  const app = setup({ userError: { message: 'synthetic' } });
  assert.equal((await app.request()).status, 401);
  assert.deepEqual(app.calls.map((c) => c.kind), ['who']);
});

test('the link goes to the address on file, and the caller gets neither token nor address', async () => {
  const app = setup();
  const response = await app.request('Bearer synthetic-session', 'POST',
    { user_id: 'someone-else', email: 'attacker@example.test' });
  assert.equal(response.status, 200);
  const [who, rpc, mail] = app.calls;
  assert.equal(who.key, 'synthetic-anon');
  assert.equal(who.authorization, 'Bearer synthetic-session');
  assert.equal(rpc.key, 'synthetic-service');
  assert.equal(rpc.name, 'create_email_confirmation');
  // The account comes from the session, never from the request body.
  assert.equal(rpc.params.p_user_id, 'user-1');
  assert.match(rpc.params.p_token_hash, /^[0-9a-f]{64}$/);
  assert.equal(mail.to, 'rider@example.test');
  const link = new URL(mail.link);
  assert.equal(link.origin + link.pathname, 'https://arangcada.app/confirm-email');
  assert.equal(link.search, '');
  const token = new URLSearchParams(link.hash.slice(1)).get('token');
  assert.ok(token.length >= 40);
  // Only the hash is stored, and it is the hash of the token that was mailed.
  assert.equal(createHash('sha256').update(token).digest('hex'), rpc.params.p_token_hash);
  const text = await response.text();
  assert.equal(text.includes(token), false);
  assert.equal(text.includes('rider@example.test'), false);
  assert.equal(text.includes('synthetic-service'), false);
});

test('two requests never share a token', async () => {
  const app = setup();
  await app.request();
  await app.request();
  const hashes = app.calls.filter((c) => c.kind === 'rpc').map((c) => c.params.p_token_hash);
  assert.equal(new Set(hashes).size, 2);
});

test('a refusal from the database is passed on and nothing is mailed', async () => {
  for (const [rpcError, status] of [
    [{ code: '22023', message: 'Please wait a minute before asking for another link.' }, 429],
    [{ code: 'P0002', message: 'no such account' }, 500],
    [{ code: 'XX000', message: 'synthetic' }, 500],
  ]) {
    const app = setup({ rpcError });
    const response = await app.request();
    assert.equal(response.status, status);
    if (status === 429) assert.equal((await response.json()).error, rpcError.message);
    assert.equal(app.calls.filter((c) => c.kind === 'mail').length, 0);
  }
});

test('a failed send is reported, not hidden', async () => {
  assert.equal((await setup({ mailFails: true }).request()).status, 502);
});
