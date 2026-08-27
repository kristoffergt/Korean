// App-shell caching for offline resilience / fast repeat loads. This is
// NOT full offline data support -- the app's actual data all lives behind
// authenticated Supabase calls with nothing static to fall back to, so
// there's no meaningful "offline mode" to build the way a static dataset
// would allow. What this buys instead: the shell (this HTML file, its
// icons, and the pinned-version CDN scripts/fonts it loads) survives a
// flaky connection or a fully offline app-switcher relaunch, while data
// calls still go live over the network exactly as before.
const CACHE = 'productivity-tracker-shell-v2';
const SHELL_URLS = [
  './',
  'index.html',
  'manifest.json',
  'icon-192.png',
  'icon-512.png',
  'icon-maskable-512.png',
  'apple-touch-icon.png',
];

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(SHELL_URLS)));
  self.skipWaiting();
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)))
    )
  );
  self.clients.claim();
});

// Never intercept Supabase -- every account-scoped read/write lives there,
// and a service-worker cache is exactly how a shared or later-signed-out
// device could hand someone else a previous session's response. Letting
// the request pass through untouched is the safe default; this line exists
// so nobody "fixes" the fetch handler below into covering it by accident.
function isSupabase(url) {
  return url.hostname.endsWith('.supabase.co');
}

self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (isSupabase(url)) return; // let the browser handle it, untouched

  // Navigations (the HTML document itself): network-first. A cache-first
  // document is how a service worker bricks an app after a real deploy --
  // the cached copy would stay on screen forever with no way back to the
  // new one. Cache is only ever the offline fallback here.
  if (req.mode === 'navigate') {
    e.respondWith(
      fetch(req)
        .then((res) => {
          const copy = res.clone();
          caches.open(CACHE).then((c) => c.put(req, copy));
          return res;
        })
        .catch(() => caches.match(req).then((cached) => cached || caches.match('index.html')))
    );
    return;
  }

  // Everything else this app actually loads (this file's own static
  // assets, plus the pinned-version CDN scripts/fonts) is effectively
  // immutable per URL -- cache-first, network as the fallback/backfill.
  e.respondWith(
    caches.match(req).then((cached) => {
      if (cached) return cached;
      return fetch(req).then((res) => {
        if (res && res.ok) {
          const copy = res.clone();
          caches.open(CACHE).then((c) => c.put(req, copy));
        }
        return res;
      }).catch(() => cached);
    })
  );
});
