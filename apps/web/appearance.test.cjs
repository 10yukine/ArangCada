const { test } = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { runInNewContext } = require('node:vm');

test('appearance icons select, persist, and restore all three modes', () => {
  let stored = 'invalid';
  const load = () => {
    const controls = ['system'].map(appearance => ({
      parentElement: { dataset: {} },
      dataset: { appearance },
      setAttribute(name, value) { this[name] = value; },
      addEventListener(event, handler) { this.click = handler; },
    }));
    const document = {
      documentElement: { dataset: {} },
      addEventListener(event, handler) { handler(); },
      querySelectorAll(selector) { return selector === '[data-appearance]' ? controls : []; },
    };
    runInNewContext(readFileSync(__dirname + '/public/appearance.js', 'utf8'), {
      document, window: {}, matchMedia: () => ({ matches: false }),
      localStorage: { getItem: () => stored, setItem: (_, value) => { stored = value; } },
    });
    return { controls, document };
  };
  let page = load();
  assert.equal(page.controls[0].value, 'system');
  for (const mode of ['dark', 'light', 'system']) {
    page.controls[0].value = mode;
    page.controls[0].click();
    assert.equal(stored, mode);
    page = load();
    assert.equal(page.document.documentElement.dataset.theme, mode === 'system' ? undefined : mode);
    assert.equal(page.controls[0].parentElement.dataset.mode, mode);
  }
});
