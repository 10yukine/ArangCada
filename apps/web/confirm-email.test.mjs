import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import vm from 'node:vm';

test('confirmation waits for a click and removes the token from the address', async () => {
  const source = readFileSync(new URL('./public/confirm-email.js', import.meta.url), 'utf8');
  for (const fragment of [true, false]) {
    let click;
    let calls = 0;
    let cleanUrl;
    const button = { addEventListener: (_, fn) => { click = fn; } };
    const status = { dataset: {} };
    vm.runInNewContext(source, {
      document: { getElementById: (id) => id === 'confirm-button' ? button : status },
      window: {
        location: { hash: fragment ? '#token=synthetic-token' : '', search: fragment ? '' : '?token=synthetic-token', pathname: '/confirm-email' },
        history: { replaceState: (_, __, path) => { cleanUrl = path; } },
      },
      URLSearchParams,
      fetch: async (_, options) => {
        calls++;
        assert.equal(JSON.parse(options.body).token, 'synthetic-token');
        return { ok: true, json: async () => ({ confirmed: true }) };
      },
    });
    assert.equal(cleanUrl, '/confirm-email');
    assert.equal(calls, 0);
    await click();
    assert.equal(calls, 1);
    assert.equal(button.hidden, true);
    assert.match(status.textContent, /confirmed/);
  }
});
