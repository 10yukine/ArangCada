import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { test } from 'node:test';
import vm from 'node:vm';

// Runs the real handler with the database call mocked. It does not replace a
// check against the deployed function.
const source = stripTypeScriptTypes(
  readFileSync(new URL('./index.ts', import.meta.url), 'utf8')
    .replace(/^import .*from .*;\s*$/gm, ''),
);

const token = 'a'.repeat(43);

function setup({ confirmed = true, error = null, configured = true } = {}) {
  let handler;
  const calls = [];
  const env = { SUPABASE_URL: 'https://project.example.test', SUPABASE_SERVICE_ROLE_KEY: 'synthetic-service' };
  vm.runInNewContext(source, {
    Deno: { serve: (fn) => { handler = fn; }, env: { get: (key) => configured ? env[key] : undefined } },
    Request, Response, crypto, TextEncoder, Uint8Array,
    CORS_HEADERS: {}, console: { error() {} },
    jsonResponse: (code, body) => new Response(JSON.stringify(body), { status: code }),
    createClient: (url, key) => ({ rpc: async (name, params) => {
      calls.push({ key, name, params });
      return { data: error ? null : confirmed, error };
    } }),
  });
  return { calls, request: (body = { token }, method = 'POST') =>
    handler(new Request('https://project.example.test/functions/v1/confirm-email', {
      method, ...(method === 'POST' ? { body: typeof body === 'string' ? body : JSON.stringify(body) } : {}),
    })) };
}

test('only a POST with a plausible token reaches the database', async () => {
  const app = setup();
  assert.equal((await app.request({}, 'GET')).status, 405);
  assert.equal((await app.request({}, 'OPTIONS')).status, 200);
  assert.equal((await app.request('not json')).status, 400);
  for (const bad of [undefined, '', 'short', 'x'.repeat(201), 42]) {
    assert.equal((await app.request({ token: bad })).status, 400);
  }
  assert.equal(app.calls.length, 0);
  assert.equal((await setup({ configured: false }).request()).status, 500);
});

test('a good link is redeemed by its hash, on the service role', async () => {
  const app = setup();
  const response = await app.request();
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { confirmed: true });
  assert.equal(app.calls[0].key, 'synthetic-service');
  assert.equal(app.calls[0].name, 'confirm_email');
  assert.equal(app.calls[0].params.p_token_hash, createHash('sha256').update(token).digest('hex'));
});

test('every link that does not work gets the same answer', async () => {
  const response = await setup({ confirmed: false }).request();
  assert.equal(response.status, 400);
  assert.match((await response.json()).error, /expired or was already used/);
});

test('a database failure is not reported as a bad link', async () => {
  assert.equal((await setup({ error: { message: 'synthetic' } }).request()).status, 500);
});
