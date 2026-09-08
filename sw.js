// Prelimsify service worker.
// Strategy: NETWORK-FIRST for everything. This exists only to make the site
// installable and to give a basic offline fallback — it must never cause an
// old, buggy version of index.html/app.js/admin.js to be served over a newer
// deployed one. Bump CACHE_VERSION whenever you want to force clients to
// drop old cached files.
const CACHE_VERSION = 'prelimsify-v1';
const OFFLINE_URL = 'offline.html';

const PRECACHE = [
  './',
  'index.html',
  'admin.html',
  'offline.html',
  'css/styles.css',
  'js/app.js',
  'js/admin.js',
  'manifest.json',
  'icons/icon-192.png',
  'icons/icon-512.png'
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_VERSION)
      .then((cache) => cache.addAll(PRECACHE.map(u => new Request(u, { cache: 'reload' }))))
      .catch(() => {}) // don't block install if a file 404s
  );
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== CACHE_VERSION).map((k) => caches.delete(k)))
    )
  );
  self.clients.claim();
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;

  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return; // let Supabase/API calls pass straight through

  // Page navigations: always try the network first (so fixes/deploys show
  // up immediately); fall back to cache, then to the offline page.
  if (req.mode === 'navigate') {
    event.respondWith(
      fetch(req)
        .then((res) => {
          caches.open(CACHE_VERSION).then((c) => c.put(req, res.clone()));
          return res;
        })
        .catch(() =>
          caches.match(req).then((cached) => cached || caches.match(OFFLINE_URL))
        )
    );
    return;
  }

  // Static assets (css/js/icons): network-first, cached as a fallback for
  // offline use only.
  event.respondWith(
    fetch(req)
      .then((res) => {
        caches.open(CACHE_VERSION).then((c) => c.put(req, res.clone()));
        return res;
      })
      .catch(() => caches.match(req))
  );
});
