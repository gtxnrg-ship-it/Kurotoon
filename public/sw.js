const CACHE_NAME = 'kurotoon-shell-v1';
const SHELL_URLS = ['/', '/manifest.webmanifest', '/kurotoon-icon.svg'];
const MAX_CACHED_ASSETS = 24;

self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then(cache => cache.addAll(SHELL_URLS))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys()
      .then(keys => Promise.all(
        keys.filter(key => key.startsWith('kurotoon-shell-') && key !== CACHE_NAME)
          .map(key => caches.delete(key))
      ))
      .then(() => self.clients.claim())
  );
});

async function trimAssetCache(cache) {
  const keys = await cache.keys();
  const assets = keys.filter(request => new URL(request.url).pathname.startsWith('/assets/'));
  const overflow = assets.length - MAX_CACHED_ASSETS;
  if (overflow > 0) {
    await Promise.all(assets.slice(0, overflow).map(request => cache.delete(request)));
  }
}

self.addEventListener('fetch', event => {
  const request = event.request;
  if (request.method !== 'GET') return;

  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  if (request.mode === 'navigate') {
    event.respondWith(
      fetch(request)
        .then(response => {
          if (response.ok) {
            const copy = response.clone();
            void caches.open(CACHE_NAME).then(cache => cache.put('/', copy));
          }
          return response;
        })
        .catch(async () => (await caches.match('/')) || Response.error())
    );
    return;
  }

  // Cache only same-origin app code/styles/fonts. Comic artwork and provider
  // responses remain live and are deliberately excluded from this bounded cache.
  if (!url.pathname.startsWith('/assets/') || !/\.(js|css|woff2?|ttf|otf)$/i.test(url.pathname)) return;

  event.respondWith(
    caches.match(request).then(async cached => {
      if (cached) return cached;
      const response = await fetch(request);
      if (response.ok && response.type === 'basic') {
        const cache = await caches.open(CACHE_NAME);
        await cache.put(request, response.clone());
        await trimAssetCache(cache);
      }
      return response;
    })
  );
});
