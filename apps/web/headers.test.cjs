const { test } = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync, readdirSync } = require('node:fs');

// /delete-account deletes an account from a form. If another site could frame
// it, that site could dress the form up as something else.
test('no page on the site can be framed by another site', () => {
  const rules = readFileSync(__dirname + '/public/_headers', 'utf8');
  const everyPath = rules.slice(rules.indexOf('\n/*'));
  assert.match(everyPath, /^\s+X-Frame-Options: DENY$/m);
  assert.match(everyPath, /^\s+Content-Security-Policy: .*frame-ancestors 'none'/m);
  assert.match(everyPath, /^\s+X-Content-Type-Options: nosniff$/m);
});

test('only this site and Turnstile may run script, and nothing inline', () => {
  const rules = readFileSync(__dirname + '/public/_headers', 'utf8');
  const csp = rules.match(/^\s+Content-Security-Policy: (.*)$/m)[1];
  assert.match(csp, /default-src 'none'/);
  assert.match(csp, /script-src 'self' https:\/\/challenges\.cloudflare\.com;/);
  assert.doesNotMatch(csp, /unsafe-inline|unsafe-eval/);
  // The policy above only holds while no page has anything inline.
  for (const page of readdirSync(__dirname + '/public').filter((name) => name.endsWith('.html'))) {
    const html = readFileSync(`${__dirname}/public/${page}`, 'utf8');
    assert.doesNotMatch(html, /<script(?![^>]*\bsrc=)|<style|\sstyle="|\son[a-z]+="/, page);
  }
});
