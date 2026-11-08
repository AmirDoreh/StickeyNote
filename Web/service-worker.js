const CACHE = 'stickeynote-v2';
const SHELL = ['./', './index.html', './styles.css', './app.js', './core.js', './cloud.js', './cloud-archive.js', './config.js', './icon.svg', './icon-192.png', './icon-512.png', './apple-touch-icon.png', './manifest.json', './vendor/qrcode.js', './vendor/jsqr.js', './vendor/dm-sans-latin.woff2', './vendor/manrope-latin.woff2'];
self.addEventListener('install', event => event.waitUntil(caches.open(CACHE).then(cache => cache.addAll(SHELL)).then(() => self.skipWaiting())));
self.addEventListener('activate', event => event.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(key => key.startsWith('stickeynote-') && key !== CACHE).map(key => caches.delete(key)))).then(() => self.clients.claim())));
self.addEventListener('fetch', event => {
  const url = new URL(event.request.url);
  if (event.request.method !== 'GET' || url.origin !== location.origin) return;
  if (!SHELL.some(path => new URL(path, self.registration.scope).pathname === url.pathname)) return;
  event.respondWith(fetch(event.request).then(response => {
    if (response.ok) { const copy = response.clone(); caches.open(CACHE).then(cache => cache.put(event.request, copy)); }
    return response;
  }).catch(() => caches.match(event.request)));
});
