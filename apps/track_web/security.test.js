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
      assert.ok(['/style.css', '/config.js', '/track.js'].includes(resolved.pathname));
    }
  }
});
