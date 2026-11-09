// The page owns permission prompts; the worker receives notifications while closed.
(() => {
  const installed = () => matchMedia('(display-mode: standalone)').matches || navigator.standalone === true;
  const ios = () => /iPhone|iPad|iPod/.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  const reason = () => !window.isSecureContext ? '请通过 HTTPS 打开下班王' : ios() && !installed()
    ? '在 Safari 点击分享 → 添加到主屏幕，再从桌面图标打开下班王并开启通知。'
    : !('serviceWorker' in navigator) || !('PushManager' in window) || !('Notification' in window)
      ? '当前浏览器不支持网页通知，请使用较新版本的 Safari、Chrome 或 Edge。' : '';
  const register = async () => {
    await navigator.serviceWorker.register('/sw.js', { scope: '/', updateViaCache: 'none' });
    return navigator.serviceWorker.ready;
  };
  const subscription = async () => {
    if (reason()) return null;
    const registration = await navigator.serviceWorker.getRegistration('/');
    return registration ? registration.pushManager.getSubscription() : null;
  };
  window.busPush = {
    reason,
    async permission() {
      if (reason()) throw new Error(reason());
      // Called immediately from the Flutter tap, before any network or await.
      const permission = Notification.permission === 'default' ? await Notification.requestPermission() : Notification.permission;
      if (permission !== 'granted') throw new Error('通知未获允许，请在系统设置中允许下班王通知后重试。');
      return permission;
    },
    async current() {
      const sub = await subscription();
      return JSON.stringify(sub ? sub.toJSON() : null);
    },
    async subscribe(key) {
      if (reason()) throw new Error(reason());
      const registration = await register();
      let sub = await registration.pushManager.getSubscription();
      const decoded = atob(key.replace(/-/g, '+').replace(/_/g, '/').padEnd(Math.ceil(key.length / 4) * 4, '='));
      const bytes = Uint8Array.from(decoded, c => c.charCodeAt(0));
      if (sub?.options.applicationServerKey && !new Uint8Array(sub.options.applicationServerKey).every((v, i) => v === bytes[i])) {
        throw new Error('通知密钥已变更，请先断开这台设备，再重新连接。');
      }
      sub ??= await registration.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: bytes });
      return JSON.stringify(sub.toJSON());
    },
    async hash(endpoint) {
      const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(endpoint));
      return [...new Uint8Array(digest)].map(v => v.toString(16).padStart(2, '0')).join('');
    },
    async disconnect() {
      const sub = await subscription();
      if (sub && !await sub.unsubscribe()) throw new Error('浏览器未能断开通知，请重试。');
      return 'ok';
    },
    async refreshWorker() { if (!reason()) await register(); return 'ok'; },
  };
})();
