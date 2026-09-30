// Tests for the public ride-tracking page's pure logic.
//
//   node --test apps/track_web/
//
// No browser, no bundler, no dependency. That is why render.js holds no DOM or
// network code: this page is public and unauthenticated, so its behaviour --
// especially its failure behaviour -- deserves real coverage, and coverage that
// needs a headless browser would never actually be run.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

import {
  parseToken,
  statusText,
  statusTone,
  timeAgo,
  isStale,
  toViewModel,
  focusPoint,
  chooseInitialState,
} from './public/render.js';

const HERE = dirname(fileURLToPath(import.meta.url));

// A representative row, shaped exactly as ride_share_view() returns it.
const ROW = {
  status: 'in_progress',
  pickup_label: 'SM Calamba',
  destination_label: 'Calamba Crossing',
  driver_display_name: 'Marco Dela Cruz',
  driver_body_number: 'POB-042',
  toda_name: 'Poblacion TODA',
  pickup_lat: 14.215,
  pickup_lng: 121.165,
  destination_lat: 14.22,
  destination_lng: 121.17,
  driver_lat: 14.2155,
  driver_lng: 121.1652,
  position_updated_at: '2026-08-31T10:00:00.000Z',
  requested_at: '2026-08-31T09:55:00.000Z',
};

const NOW = Date.parse('2026-08-31T10:00:05.000Z');

// ---------------------------------------------------------------------------
// Token parsing
// ---------------------------------------------------------------------------

test('reads the token from the /t/<token> path', () => {
  assert.equal(parseToken('/t/abc123DEF', ''), 'abc123DEF');
  assert.equal(parseToken('/t/abc123DEF/', ''), 'abc123DEF');
});

test('reads the token from ?t= as a fallback for hosts without rewrites', () => {
  assert.equal(parseToken('/', '?t=abc123DEF'), 'abc123DEF');
});

test('returns null rather than a bad request when there is no token', () => {
  // The caller shows the expired state instead of firing a pointless fetch.
  for (const [path, search] of [
    ['/', ''],
    ['/t/', ''],
    ['/index.html', ''],
    ['/t/has spaces', ''],
    ['/t/<script>', ''],
    ['/', '?t='],
  ]) {
    assert.equal(parseToken(path, search), null, `${path}${search}`);
  }
});

// ---------------------------------------------------------------------------
// Status wording
// ---------------------------------------------------------------------------

test('translates statuses into sentences a stranger can read', () => {
  assert.equal(statusText('searching_driver'), 'Looking for a driver');
  assert.equal(statusText('arrived'), 'The driver has arrived at the pickup point');
  assert.equal(statusText('in_progress'), 'The trip is in progress');
});

test('an unknown status degrades instead of printing a raw enum', () => {
  // A later migration could add a status this page has never heard of. Showing
  // "driver_reassigned_pending_v2" to a worried parent is worse than a generic
  // but truthful line.
  assert.equal(statusText('something_new_entirely'), 'Trip in progress');
  assert.equal(statusText(undefined), 'Trip status unavailable');
});

test('only an emergency gets the alert tone', () => {
  assert.equal(statusTone('emergency_reported'), 'alert');
  assert.equal(statusTone('in_progress'), 'normal');
});

// ---------------------------------------------------------------------------
// Staleness, which stands in for an ETA
// ---------------------------------------------------------------------------

test('describes how old the position is', () => {
  const t = (iso) => timeAgo(iso, NOW);
  assert.equal(t('2026-08-31T10:00:03.000Z'), 'just now');
  assert.equal(t('2026-08-31T09:59:35.000Z'), '30s ago');
  assert.equal(t('2026-08-31T09:55:05.000Z'), '5m ago');
  assert.equal(t('2026-08-31T08:00:05.000Z'), '2h ago');
  assert.equal(t('2026-08-29T10:00:00.000Z'), 'over a day ago');
});

test('missing or unparseable timestamps do not produce NaN on screen', () => {
  assert.equal(timeAgo(null, NOW), 'no location yet');
  assert.equal(timeAgo('not a date', NOW), 'no location yet');
});

test('a clock skew into the future reads as just now, not a negative age', () => {
  assert.equal(timeAgo('2026-08-31T10:05:00.000Z', NOW), 'just now');
});

test('flags a position old enough to be misleading', () => {
  // A stale dot presented as current reads as "the tricycle stopped" when it
  // usually means the phone lost signal.
  assert.equal(isStale('2026-08-31T10:00:00.000Z', NOW), false);
  assert.equal(isStale('2026-08-31T09:55:00.000Z', NOW), true);
  assert.equal(isStale(null, NOW), true);
});

// ---------------------------------------------------------------------------
// View model
// ---------------------------------------------------------------------------

test('an empty array is the expiry signal', () => {
  // ride_share_view() returns zero rows for an unknown token, a revoked link,
  // and a finished trip. The server decides; the page only reports.
  assert.deepEqual(toViewModel([], NOW), { kind: 'expired' });
  assert.deepEqual(toViewModel(null, NOW), { kind: 'expired' });
  assert.deepEqual(toViewModel(undefined, NOW), { kind: 'expired' });
});

test('renders driver and vehicle from a live row', () => {
  const vm = toViewModel([ROW], NOW);
  assert.equal(vm.kind, 'active');
  assert.equal(vm.driverName, 'Marco Dela Cruz');
  assert.equal(vm.bodyNumber, 'POB-042');
  assert.equal(vm.todaName, 'Poblacion TODA');
  assert.equal(vm.statusText, 'The trip is in progress');
  assert.equal(vm.hasDriverPosition, true);
  assert.deepEqual(vm.driver, { lat: 14.2155, lng: 121.1652 });
});

test('copes with a trip that has no driver assigned yet', () => {
  const vm = toViewModel([{
    ...ROW,
    status: 'searching_driver',
    driver_display_name: null,
    driver_body_number: null,
    driver_lat: null,
    driver_lng: null,
    position_updated_at: null,
  }], NOW);

  assert.equal(vm.hasDriverPosition, false);
  assert.equal(vm.driver, null);
  assert.equal(vm.driverName, 'Driver not yet assigned');
  assert.equal(vm.bodyNumber, null);
  // No map until the driver shares a position.
  assert.equal(focusPoint(vm), null);
});

test('never exposes pickup or destination, which may come from Google', () => {
  const vm = toViewModel([ROW], NOW);
  assert.deepEqual(focusPoint(vm), { lat: 14.2155, lng: 121.1652 });
  const shown = JSON.stringify(vm);
  assert.equal(shown.includes('SM Calamba'), false);
  assert.equal(shown.includes('Calamba Crossing'), false);
  assert.equal('pickup' in vm || 'destination' in vm, false);
  assert.equal(focusPoint({ kind: 'expired' }), null);
});

// ---------------------------------------------------------------------------
// Initial state
// ---------------------------------------------------------------------------

test('the bare domain shows a landing page, NOT an expired link', () => {
  // Regression guard for a real defect: arangcada.app with no token used to
  // render "This tracking link has expired". Someone typing the domain -- a
  // panelist, an LGU officer, a curious driver -- has done nothing wrong, and
  // that message is both false and a poor first impression of the project.
  assert.equal(chooseInitialState(null, true), 'landing');
  assert.equal(chooseInitialState(null, false), 'landing');
});

test('a token with working config goes straight to loading', () => {
  assert.equal(chooseInitialState('abc123', true), 'loading');
});

test('a token with no config shows the neutral expired screen', () => {
  // A deploy missing config.js cannot fetch anything. The visitor gets the
  // neutral message; the console gets the real reason, for whoever deployed it.
  assert.equal(chooseInitialState('abc123', false), 'expired');
});

test('index.html carries all four states', () => {
  const html = readFileSync(join(HERE, 'public', 'index.html'), 'utf8');
  for (const id of ['state-loading', 'state-landing', 'state-expired', 'state-active']) {
    assert.ok(html.includes(`id="${id}"`), `index.html is missing #${id}`);
  }
});

// ---------------------------------------------------------------------------
// Privacy
// ---------------------------------------------------------------------------

test('the view model exposes no rider-identifying field', () => {
  // Belt and braces. ride_share_view() does not return these, but a future
  // migration could widen the payload, and this page must not start rendering
  // a name or a phone number just because one appeared in the response.
  const vm = toViewModel([{
    ...ROW,
    rider_display_name: 'Juana Dela Cruz',
    rider_phone: '+639171234567',
    rider_email: 'juana@example.test',
    final_fare: 85.0,
  }], NOW);

  const serialised = JSON.stringify(vm);
  for (const leak of ['Juana', '639171234567', 'juana@example.test', '85']) {
    assert.ok(
      !serialised.includes(leak),
      `view model leaked "${leak}" — the tracking page must never carry rider identity or fare`,
    );
  }
});

test('render.js never references a rider or fare field by name', () => {
  // Source-level check: catches someone adding `row.rider_display_name` in a
  // hurry. Cheap, and the failure message says exactly what is wrong.
  //
  // Comments are stripped first. An earlier version of this test scanned the
  // raw file and failed on the word "phone" inside the sentence "the phone lost
  // signal" -- a false positive that would have trained the next reader to
  // ignore this assertion, which is the worst thing a security test can do.
  const raw = readFileSync(join(HERE, 'public', 'render.js'), 'utf8');
  const code = raw
    .replace(/\/\*[\s\S]*?\*\//g, ' ')   // block comments
    .replace(/(^|[^:])\/\/.*$/gm, '$1 '); // line comments, leaving URLs alone

  for (const forbidden of ['rider_', 'phone', 'email', 'final_fare', 'fare_estimate']) {
    assert.ok(
      !code.includes(forbidden),
      `render.js references "${forbidden}" in code — this page must not read rider identity, contact details, or fare`,
    );
  }
});

test('the page asks not to be indexed and not to leak the token via Referer', () => {
  // Without no-referrer, every map tile request carries the full tracking URL --
  // token included -- to the tile provider.
  const html = readFileSync(join(HERE, 'public', 'index.html'), 'utf8');
  assert.ok(/name="referrer"\s+content="no-referrer"/.test(html), 'missing no-referrer meta');
  assert.ok(/name="robots"[^>]*noindex/.test(html), 'missing noindex meta');
});
