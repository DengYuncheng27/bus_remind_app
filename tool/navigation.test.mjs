import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import test from 'node:test';
import assert from 'node:assert/strict';

const source = readFileSync(new URL('../web/navigation.js', import.meta.url), 'utf8');
function browser({ userAgent = 'iPhone', standalone = true, displayMode = false, platform = '', maxTouchPoints = 1 } = {}) {
  const listeners = [];
  vm.runInNewContext(source, {
    navigator: { userAgent, standalone, platform, maxTouchPoints },
    window: { innerWidth: 390, matchMedia: () => ({ matches: displayMode }) },
    document: { addEventListener: (...args) => listeners.push(args) },
  });
  return (x, { count = 1, flutter = true, cancelable = true } = {}) => {
    let prevented = false;
    const event = {
      cancelable, touches: Array.from({ length: count }, () => ({ clientX: x })),
      composedPath: () => [{ tagName: 'CANVAS' }, { tagName: flutter ? 'FLUTTER-VIEW' : 'BODY' }],
      preventDefault: () => { prevented = true; },
      stopPropagation: () => assert.fail('Flutter must still receive the gesture'),
    };
    for (const [name, listener, options] of listeners) {
      assert.equal(name, 'touchstart');
      assert.equal(options.passive, false);
      assert.equal(options.capture, true);
      listener(event);
    }
    return prevented;
  };
}

test('installed iPhone cancels only browser edge gestures over Flutter', () => {
  const touch = browser();
  assert.equal(touch(0), true);
  assert.equal(touch(20), true);
  assert.equal(touch(370), true);
  assert.equal(touch(389), true);
  assert.equal(touch(21), false);
  assert.equal(touch(195), false);
  assert.equal(touch(369), false);
  assert.equal(touch(0, { count: 2 }), false);
  assert.equal(touch(0, { flutter: false }), false);
  assert.equal(touch(0, { cancelable: false }), false);
});

test('ordinary Safari, Android and desktop keep browser navigation', () => {
  assert.equal(browser({ standalone: false })(0), false);
  assert.equal(browser({ userAgent: 'Android' })(0), false);
  assert.equal(browser({ userAgent: 'Macintosh', platform: 'MacIntel', maxTouchPoints: 0 })(0), false);
});

test('installed iPad desktop user agent and display-mode detection are supported', () => {
  assert.equal(browser({ userAgent: 'Macintosh', platform: 'MacIntel', maxTouchPoints: 5 })(0), true);
  assert.equal(browser({ standalone: false, displayMode: true })(0), true);
});
