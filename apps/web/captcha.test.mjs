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
  assert.match(html, /data-size="compact"/);
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

// The in-screen page newer builds use. /captcha stays as it is for the builds
// already installed, which read every message as a token.
test('the in-screen check uses the same widget and tells the app what it needs', () => {
  const html = page('captcha-inline.html');
  const key = (source) => source.match(/data-sitekey="([^"]+)"/)[1];
  assert.equal(key(html), key(page('delete-account.html')));
  assert.doesNotMatch(html, /<script(?![^>]*\bsrc=)/);

  const posted = [];
  const resets = [];
  let options;
  const run = (width) => {
    const window = {
      ArangCaptcha: { postMessage: (message) => posted.push(message) },
      turnstile: {
        render: (_, given) => { options = given; return 'widget-1'; },
        reset: (id) => resets.push(id),
      },
    };
    const box = { clientWidth: width, dataset: { sitekey: 'the-key' } };
    vm.runInNewContext(page('captcha-inline.js'), { window, document: { getElementById: () => box } });
    window.captchaAgain(); // before the widget exists: nothing to reset
    window.captchaReady();
    return window;
  };

  const wide = run(320);
  assert.equal(options.sitekey, 'the-key');
  assert.equal(options.size, 'flexible');
  // Out of sight unless Cloudflare needs a tap.
  assert.equal(options.appearance, 'interaction-only');
  options['before-interactive-callback']();
  options.callback('a-token');
  options['after-interactive-callback']();
  options['expired-callback']();
  assert.equal(options['error-callback'](), true);
  wide.captchaAgain();
  assert.deepEqual(posted, ['interactive:81', 'token:a-token', 'idle', 'expired', 'failed']);
  assert.deepEqual(resets, ['widget-1']);

  // A phone too narrow for the wide box gets the compact one, and its height.
  posted.length = 0;
  run(280);
  assert.equal(options.size, 'compact');
  options['before-interactive-callback']();
  assert.deepEqual(posted, ['interactive:156']);
});
