const { test } = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { runInNewContext } = require('node:vm');

test('reveals run once, cancel for reduced motion, and leave unsupported browsers alone', () => {
  for (const mode of ['normal', 'reduced', 'unsupported']) {
    let observer, change, played = 0, cancelled = 0;
    const preference = { matches: mode === 'reduced', addEventListener: (_, fn) => { change = fn; } };
    const element = { animate: () => { played++; return { cancel: () => cancelled++ }; } };
    class Observer {
      targets = new Set();
      constructor(callback) { this.callback = callback; observer = this; }
      observe(target) { this.targets.add(target); }
      unobserve(target) { this.targets.delete(target); }
      disconnect() { this.targets.clear(); }
    }
    runInNewContext(readFileSync(__dirname + '/public/home-motion.js', 'utf8'), {
      matchMedia: () => preference,
      window: mode === 'unsupported' ? {} : { IntersectionObserver: Observer },
      IntersectionObserver: Observer,
      document: { querySelectorAll: () => [element] },
    });
    if (mode !== 'normal') {
      assert.equal(observer, undefined);
      assert.equal(played, 0);
      continue;
    }
    observer.callback([{ target: element, isIntersecting: false }]);
    assert.equal(played, 0);
    observer.callback([{ target: element, isIntersecting: true }]);
    assert.equal(played, 1);
    assert.equal(observer.targets.size, 0);
    preference.matches = true;
    change();
    assert.equal(cancelled, 1);
  }
});
