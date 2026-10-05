import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { test } from 'node:test';
import vm from 'node:vm';

// Exercise the actual handler with mocked external services. This does not
// replace a deployed JWT/Postgres integration check.
const source = stripTypeScriptTypes(
  readFileSync(new URL('./index.ts', import.meta.url), 'utf8')
    .replace(/^import .*from .*;\s*$/gm, ''),
);

function setup({ allowed = true, error = null, upstream = [], status = 200,
  configured = true, fetchThrows = false } = {}) {
  let handler;
  const calls = [];
  const env = { SUPABASE_URL: 'https://project.example.test',
    SUPABASE_ANON_KEY: 'synthetic-anon', LOCATIONIQ_API_KEY: 'synthetic-provider' };
  vm.runInNewContext(source, {
    Deno: { serve: (fn) => { handler = fn; }, env: { get: (key) => configured ? env[key] : undefined } },
    Request, Response, URL, URLSearchParams, AbortSignal,
    CORS_HEADERS: {}, console: { error() {} },
    jsonResponse: (code, body) => new Response(JSON.stringify(body), { status: code }),
    createClient: (url, key, options) => ({ rpc: async (name) => {
      calls.push({ kind: 'budget', url, key, options, name });
      return { data: allowed, error };
    } }),
    fetch: async (url) => {
      calls.push({ kind: 'provider', url: String(url) });
      if (fetchThrows) throw new Error('synthetic failure');
      return new Response(typeof upstream === 'string' ? upstream : JSON.stringify(upstream), { status });
    },
  });
  return { calls, request: (body = { q: 'Calamba' }, auth = 'Bearer synthetic-session', method = 'POST') =>
    handler(new Request('https://project.example.test/functions/v1/place-search', {
      method, headers: auth ? { Authorization: auth } : {},
      ...(method === 'POST' ? { body: JSON.stringify(body) } : {}),
    })) };
}

test('only POST with an authorization header reaches the budget', async () => {
  const app = setup();
  assert.equal((await app.request({}, null)).status, 401);
  assert.equal((await app.request({}, null, 'GET')).status, 405);
  assert.equal((await app.request({}, null, 'OPTIONS')).status, 200);
  assert.equal(app.calls.length, 0);
});

test('invalid query and missing configuration never spend provider calls', async () => {
  const app = setup();
  for (const q of ['', 'ab', 'x'.repeat(81), 123]) {
    assert.equal((await app.request({ q })).status, 400);
  }
  assert.equal(app.calls.length, 0);
  assert.equal((await setup({ configured: false }).request()).status, 500);
});

test('budget denial and RPC errors do not call LocationIQ', async () => {
  for (const [options, status] of [
    [{ allowed: false }, 429],
    [{ error: { code: '42501', message: 'synthetic' } }, 403],
    [{ error: { code: 'XX000', message: 'synthetic' } }, 500],
  ]) {
    const app = setup(options);
    assert.equal((await app.request()).status, status);
    assert.equal(app.calls.filter((c) => c.kind === 'provider').length, 0);
  }
});

test('caller JWT and server-only bounds are used; unexpected provider fields are removed', async () => {
  const app = setup({ upstream: [{ place_id: '1', lat: '14.2', lon: '121.1',
    display_name: 'Calamba', extra: 'unneeded' }] });
  const response = await app.request({ q: ' Calamba ', key: 'attacker', limit: 999, countrycodes: 'us' });
  assert.equal(response.status, 200);
  assert.equal(app.calls[0].options.global.headers.Authorization, 'Bearer synthetic-session');
  const url = new URL(app.calls[1].url);
  assert.equal(url.hostname, 'api.locationiq.com');
  assert.equal(url.searchParams.get('key'), 'synthetic-provider');
  assert.equal(url.searchParams.get('q'), 'Calamba');
  assert.equal(url.searchParams.get('limit'), '8');
  assert.equal(url.searchParams.get('countrycodes'), 'ph');
  assert.equal(url.searchParams.get('bounded'), '1');
  const text = await response.text();
  assert.equal(text.includes('extra'), false);
  assert.equal(text.includes('synthetic-provider'), false);
});

test('upstream statuses and timeout are handled without leaking response bodies', async () => {
  for (const [upstreamStatus, expected] of [[404, 200], [429, 429], [401, 502], [500, 502]]) {
    const app = setup({ status: upstreamStatus, upstream: 'synthetic-provider' });
    const response = await app.request();
    assert.equal(response.status, expected);
    assert.equal((await response.text()).includes('synthetic-provider'), false);
  }
  assert.equal((await setup({ fetchThrows: true }).request()).status, 504);
});

test('malformed provider data returns a controlled error', async () => {
  for (const upstream of ['bad JSON', {}, [null], [42], ['invalid']]) {
    assert.equal((await setup({ upstream }).request()).status, 502);
  }
});
