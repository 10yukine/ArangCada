import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import * as render from './public/render.js';

function boot(fetch) {
  const elements = new Map();
  const listeners = {};
  const timers = new Map();
  let timerId = 0;
  const document = {
    hidden: false,
    getElementById(id) {
      if (!elements.has(id)) {
        const classes = new Set(['hidden']);
        const paragraph = {};
        elements.set(id, {classList: {add: c => classes.add(c), remove: c => classes.delete(c), contains: c => classes.has(c)}, querySelector: () => paragraph});
      }
      return elements.get(id);
    },
    addEventListener: (name, fn) => { listeners[name] = fn; },
  };
  const source = readFileSync(new URL('./public/track.js', import.meta.url), 'utf8')
    .replace(/import \{[\s\S]*?\} from '.\/render.js';/, '');
  runInNewContext(source, {
    ...render, document, console, fetch, AbortSignal,
    window: {ARANGCADA_CONFIG: {supabaseUrl: 'https://example.test', supabaseAnonKey: 'synthetic'}, location: {pathname: '/t/test', search: ''}},
    setTimeout: (fn) => { timers.set(++timerId, fn); return timerId; },
    clearTimeout: id => timers.delete(id),
  });
  return {document, elements, listeners, timers};
}
const flush = () => new Promise(resolve => setImmediate(resolve));

test('visibility changes cannot overlap an outstanding poll', async () => {
  let finish;
  let calls = 0;
  const state = boot(() => { calls++; return new Promise(resolve => { finish = resolve; }); });
  state.listeners.visibilitychange();
  state.listeners.visibilitychange();
  assert.equal(calls, 1);
  finish({ok: true, json: async () => []});
  await flush();
  assert.equal(state.timers.size, 0);
  assert.equal(state.elements.get('state-expired').classList.contains('hidden'), false);
});

test('initial network failures keep retrying rather than declaring expiry', async () => {
  const state = boot(async () => { throw new Error('offline'); });
  await flush();
  const retry = [...state.timers.values()][0];
  state.timers.clear();
  await retry();
  assert.equal(state.elements.get('state-loading').querySelector('p').textContent, 'Unable to connect. Retrying…');
  assert.equal(state.timers.size, 1);
  assert.equal(state.elements.get('state-expired')?.classList.contains('hidden') ?? true, true);
});
