import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, mkdtempSync, mkdirSync, copyFileSync, existsSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';

const jwt = (role) => `eyJhbGciOiJIUzI1NiJ9.${Buffer.from(JSON.stringify({role})).toString('base64url')}.test-signature`;
for (const [key, accepted] of [[jwt('service_role'), false], ['sb_secret_synthetic', false], ['malformed', false], [jwt('anon'), true], ['sb_publishable_synthetic', true]]) {
  test(`config builder ${accepted ? 'accepts public' : 'rejects unsafe'} key ${key.split('.')[0]}`, () => {
    const dir = mkdtempSync(join(tmpdir(), 'arangcada-config-'));
    try {
      mkdirSync(join(dir, 'public'));
      copyFileSync(new URL('./build-config.js', import.meta.url), join(dir, 'build-config.mjs'));
      const result = spawnSync(process.execPath, [join(dir, 'build-config.mjs')], {
        encoding: 'utf8', env: { ...process.env, SUPABASE_URL: 'https://example.supabase.co', SUPABASE_ANON_KEY: key, MAPTILER_STYLE_URL: 'https://example.test/style.json' },
      });
      assert.equal(result.status, accepted ? 0 : 1);
      assert.equal(existsSync(join(dir, 'public/config.js')), accepted);
      assert.ok(!`${result.stdout}${result.stderr}`.includes(key));
    } finally { rmSync(dir, {recursive: true, force: true}); }
  });
}

test('shared path and trailing slash load assets from the site root', () => {
  const html = readFileSync(new URL('./public/index.html', import.meta.url), 'utf8');
  for (const path of ['/t/example-token', '/t/example-token/']) {
    for (const [, asset] of html.matchAll(/(?:src|href)="([^"#]+)"/g)) {
      const resolved = new URL(asset, `https://track.example.test${path}`);
      if (resolved.origin !== 'https://track.example.test') continue;
      assert.ok(['/favicon.ico', '/style.css', '/config.js', '/track.js'].includes(resolved.pathname));
    }
  }
});

test('the page cannot be framed and never sends its address as a referrer', () => {
  const rules = readFileSync(new URL('./public/_headers', import.meta.url), 'utf8');
  const everyPath = rules.slice(rules.indexOf('\n/*'));
  assert.match(everyPath, /^\s+X-Frame-Options: DENY$/m);
  assert.match(everyPath, /^\s+Content-Security-Policy: .*frame-ancestors 'none'/m);
  assert.match(everyPath, /^\s+X-Content-Type-Options: nosniff$/m);
  // The address is /t/<share token>.
  assert.match(everyPath, /^\s+Referrer-Policy: no-referrer$/m);
});

test('only this site and the pinned map library may run script, and nothing inline', () => {
  const rules = readFileSync(new URL('./public/_headers', import.meta.url), 'utf8');
  const csp = rules.match(/^\s+Content-Security-Policy: (.*)$/m)[1];
  assert.match(csp, /default-src 'none'/);
  assert.match(csp, /script-src 'self' https:\/\/unpkg\.com;/);
  assert.doesNotMatch(csp, /unsafe-inline|unsafe-eval/);
  // The policy above only holds while the page itself has nothing inline.
  const html = readFileSync(new URL('./public/index.html', import.meta.url), 'utf8');
  assert.doesNotMatch(html, /<script(?![^>]*\bsrc=)|\sstyle="|\son[a-z]+="/);
});

test('the map library is pinned to exact bytes and its attribution control is off', () => {
  const js = readFileSync(new URL('./public/track.js', import.meta.url), 'utf8');
  assert.match(js, /maplibre-gl@\d+\.\d+\.\d+\//);
  assert.equal(js.match(/'sha384-[A-Za-z0-9+/]{64}'/g).length, 2);
  assert.equal(js.match(/integrity: MAPLIBRE_INTEGRITY\.(css|js), crossOrigin: 'anonymous'/g).length, 2);
  // GHSA-jrc7-96c5-q579: the library's HTML sanitizer is broken before 6.4.1,
  // and this page stays on 4.7.1 so that older phones keep their map (decided
  // again on 5 Oct 2026). So nothing here may hand the library HTML to clean:
  // no attribution control, no popup HTML.
  assert.match(js, /attributionControl: false/);
  assert.doesNotMatch(js, /AttributionControl|innerHTML|setHTML/);
});
