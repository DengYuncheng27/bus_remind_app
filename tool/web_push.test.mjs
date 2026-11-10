import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import test from 'node:test';
import assert from 'node:assert/strict';
const source = readFileSync(new URL('../web/web-push.js', import.meta.url), 'utf8');
test('iPhone tab gives installation guidance before requesting permission', async () => {
  const window = { isSecureContext: true, PushManager: class {}, Notification: {} };
  const context = { window, navigator: { userAgent: 'iPhone', serviceWorker: {} }, matchMedia: () => ({ matches: false }) };
  vm.runInNewContext(source, context);
  assert.match(window.busPush.reason(), /添加到主屏幕/);
  await assert.rejects(window.busPush.permission(), /添加到主屏幕/);
});
test('permission request occurs synchronously within click; denied permission does not subscribe', async () => {
  let prompted = false;
  const Notification = { permission: 'default', requestPermission: () => { prompted = true; return Promise.resolve('denied'); } };
  const window = { isSecureContext: true, PushManager: class {}, Notification };
  vm.runInNewContext(source, { window, Notification, navigator: { userAgent: 'iPhone', standalone: true, serviceWorker: {} }, matchMedia: () => ({ matches: true }) });
  const promise = window.busPush.permission();
  assert.equal(prompted, true);
  await assert.rejects(promise, /通知未获允许/);
});
test('worker displays push with a safe deep link and never navigates admin windows', async () => {
  const handlers = {}, shown = [], opened = [];
  const self = { location: { origin: 'https://bus.example.com' }, addEventListener: (n, h) => handlers[n] = h,
    registration: { showNotification: async (...args) => shown.push(args) },
    clients: { matchAll: async () => [{ url:'https://bus.example.com/admin/' }, { url:'https://bus.example.com/' }], openWindow: async url => opened.push(url) } };
  vm.runInNewContext(readFileSync(new URL('../web/sw.js', import.meta.url),'utf8'), { self, URL });
  let pending;
  handlers.push({ data: { json: () => ({ title:'到站提醒', body:'还有两站', reminderId:42, url:'https://evil.example/' }) }, waitUntil: p => pending=p });
  await pending;
  assert.equal(shown[0][1].data.url,'/app/?reminder=42');
  handlers.notificationclick({ notification:{data:{url:'https://evil.example/'},close(){}},waitUntil:p=>pending=p });
  await pending;
  assert.deepEqual(opened,['https://bus.example.com/app/']);
});

test('notification click focuses the app and preserves its reminder without navigating the landing page', async () => {
  const handlers = {}, navigated = [];
  let focused = false;
  const self = { location: { origin: 'https://bus.example.com' }, addEventListener: (n, h) => handlers[n] = h,
    clients: { matchAll: async () => [
      { url: 'https://bus.example.com/', navigate: () => assert.fail('landing page must stay open') },
      { url: 'https://bus.example.com/app/', navigate: async url => navigated.push(url), focus: async () => focused = true },
    ], openWindow: () => assert.fail('reuse the existing app window') } };
  vm.runInNewContext(readFileSync(new URL('../web/sw.js', import.meta.url), 'utf8'), { self, URL });
  let pending;
  handlers.notificationclick({ notification: { data: { url: '/app/?reminder=42' }, close() {} }, waitUntil: p => pending = p });
  await pending;
  assert.deepEqual(navigated, ['https://bus.example.com/app/?reminder=42']);
  assert.equal(focused, true);
});
