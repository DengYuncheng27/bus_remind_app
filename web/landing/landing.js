(() => {
  const tabs = [...document.querySelectorAll('[data-platform]')];
  function select(platform, focus = false) {
    tabs.forEach(tab => {
      const active = tab.dataset.platform === platform;
      tab.setAttribute('aria-selected', String(active));
      tab.tabIndex = active ? 0 : -1;
      document.getElementById(tab.getAttribute('aria-controls')).hidden = !active;
      if (active && focus) tab.focus();
    });
  }
  tabs.forEach((tab, index) => {
    tab.addEventListener('click', () => select(tab.dataset.platform));
    tab.addEventListener('keydown', event => {
      let next;
      if (['ArrowRight', 'ArrowDown'].includes(event.key)) next = (index + 1) % tabs.length;
      if (['ArrowLeft', 'ArrowUp'].includes(event.key)) next = (index + tabs.length - 1) % tabs.length;
      if (event.key === 'Home') next = 0;
      if (event.key === 'End') next = tabs.length - 1;
      if (next !== undefined) { event.preventDefault(); select(tabs[next].dataset.platform, true); }
    });
  });
  document.querySelectorAll('[data-platform-link]').forEach(link => {
    link.addEventListener('click', () => select(link.dataset.platformLink));
  });
  const ios = /iPhone|iPad|iPod/i.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  const platform = ios ? 'ios' : /Android/i.test(navigator.userAgent) ? 'android' : 'web';
  select(platform);
  const hero = document.getElementById('hero-download');
  const notice = document.getElementById('hero-notice');
  if (platform === 'ios') {
    hero.href = '#install';
    hero.textContent = '查看主屏幕安装步骤 ↗';
    hero.addEventListener('click', () => select('ios'));
    notice.textContent = '通知需 iOS / iPadOS 16.4 或以上：用 Safari 打开网页版，添加到主屏幕后开启并测试通知。';
    document.querySelector('.ios-shortcut').remove();
  } else if (platform === 'web') {
    hero.href = '/app/';
    hero.textContent = '打开网页版 ↗';
    const secondary = document.getElementById('hero-secondary');
    secondary.href = '#install';
    secondary.textContent = '其他设备下载与安装 →';
    notice.textContent = '查公交可直接使用。接收提醒需允许浏览器通知，并发送测试通知。';
  }
})();
