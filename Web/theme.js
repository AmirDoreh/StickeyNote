// Loaded before styles so the saved appearance is applied before the first paint.
(() => {
  const storageKey = 'stickeynote.theme';
  const normalize = value => ['light', 'dark', 'auto'].includes(value) ? value : 'auto';
  const system = window.matchMedia('(prefers-color-scheme: dark)');
  let preference = 'auto';
  try { preference = normalize(window.localStorage.getItem(storageKey)); } catch {}

  function apply() {
    const theme = preference === 'auto' ? (system.matches ? 'dark' : 'light') : preference;
    document.documentElement.dataset.theme = theme;
    document.querySelector('meta[name="theme-color"]')?.setAttribute('content', theme === 'dark' ? '#20221d' : '#fafaf7');
    window.dispatchEvent(new Event('themechange'));
  }

  window.StickeyTheme = Object.freeze({
    get preference() { return preference; },
    setPreference(value) {
      preference = normalize(value);
      let saved = true;
      try { window.localStorage.setItem(storageKey, preference); } catch { saved = false; }
      apply();
      return saved;
    }
  });
  system.addEventListener('change', () => { if (preference === 'auto') apply(); });
  window.addEventListener('storage', event => {
    if (event.key !== storageKey && event.key !== null) return;
    // Ignore sessionStorage events, which can use the same key in another frame.
    try { if (event.storageArea && event.storageArea !== window.localStorage) return; } catch { return; }
    preference = normalize(event.newValue);
    apply();
  });
  apply();
})();
