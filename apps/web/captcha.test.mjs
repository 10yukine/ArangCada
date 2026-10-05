import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import vm from 'node:vm';

const page = (name) => readFileSync(new URL(`./public/${name}`, import.meta.url), 'utf8');

test("the app's check page uses the widget Auth is set up for and runs no inline script", () => {
  const html = page('captcha.html');
  const key = (source) => source.match(/data-sitekey="([^"]+)"/)[1];
  // Supabase Auth holds one widget's secret. A different key here would make
  // every token the app sends invalid, and nobody could sign in.
  assert.equal(key(html), key(page('delete-account.html')));
  assert.doesNotMatch(html, /<script(?![^>]*\bsrc=)/);
  assert.match(html, /data-callback="captchaDone"/);
  assert.match(html, /data-error-callback="captchaFailed"/);
});

test('the token goes to the app, and nowhere in an ordinary browser', () => {
  const posted = [];
  const inApp = { ArangCaptcha: { postMessage: (message) => posted.push(message) } };
  vm.runInNewContext(page('captcha.js'), { window: inApp });
  inApp.captchaDone('a-token');
  assert.equal(inApp.captchaFailed(), true);
  assert.deepEqual(posted, ['a-token', '']);

  const browser = {};
  vm.runInNewContext(page('captcha.js'), { window: browser });
  browser.captchaDone('a-token'); // no channel: nothing sent, nothing thrown
});
