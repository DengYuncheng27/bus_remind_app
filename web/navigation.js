(() => {
  const appleTouch = /iPhone|iPad|iPod/.test(navigator.userAgent) ||
    (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  const standalone = () => navigator.standalone === true ||
    window.matchMedia('(display-mode: standalone)').matches;
  if (!appleTouch) return;

  // WebKit's history swipe and Flutter's Cupertino route swipe otherwise run
  // together. In the installed app, keep Flutter in charge of edge gestures.
  // Do not stop propagation: Flutter still needs its pointer/touch events.
  // https://github.com/flutter/flutter/issues/114324
  document.addEventListener('touchstart', event => {
    if (!standalone() || !event.cancelable || event.touches.length !== 1) return;
    if (!event.composedPath().some(node => node.tagName === 'FLUTTER-VIEW')) return;
    const x = event.touches[0].clientX;
    if (x <= 20 || x >= window.innerWidth - 20) event.preventDefault();
  }, { capture: true, passive: false });
})();
