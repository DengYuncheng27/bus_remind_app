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
  if (/iPhone|iPad|iPod/i.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1)) {
    select('ios');
    const hero = document.getElementById('hero-download');
    hero.href = '#install';
    hero.textContent = '添加到主屏幕 ↗';
    hero.addEventListener('click', () => select('ios'));
  }
})();
