const CACHE = 'korean-tracker-v1';

self.addEventListener('install', (e) => {
  self.skipWaiting();
});

self.addEventListener('activate', (e) => {
  self.clients.claim();
});

// Network-first: the app relies on live data from Supabase, so we don't want
// to serve a stale cached page. We only fall back to cache if fully offline.
self.addEventListener('fetch', (e) => {
  e.respondWith(
    fetch(e.request).catch(() =>
      caches.match(e.request).then((cached) => cached || Response.error())
    )
  );
});
