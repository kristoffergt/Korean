// App-shell caching for offline resilience / fast repeat loads. This is
// NOT full offline data support -- the app's actual data all lives behind
// authenticated Supabase calls with nothing static to fall back to, so
// there's no meaningful "offline mode" to build the way a static dataset
// would allow. What this buys instead: the shell (this HTML file, its
// icons, and the pinned-version CDN scripts/fonts it loads) survives a
// flaky connection or a fully offline app-switcher relaunch, while data
// calls still go live over the network exactly as before.
const CACHE = 'productivity-tracker-shell-v3';
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

// Whether two responses for the same URL are the same document. The etag is
// what the host actually varies (GitHub Pages sends one per content hash);
// last-modified and the length are there for a host that does not.
function sameDoc(a, b) {
  if (!a || !b) return false;
  const tag = (r) => r.headers.get('etag') || '';
  if (tag(a) && tag(b)) return tag(a) === tag(b);
  const mod = (r) => r.headers.get('last-modified') || '';
  if (mod(a) && mod(b)) return mod(a) === mod(b);
  const len = (r) => r.headers.get('content-length') || '';
  return len(a) !== '' && len(a) === len(b);
}

async function tellClients(msg) {
  const all = await self.clients.matchAll({ type: 'window' });
  all.forEach((c) => c.postMessage(msg));
}

self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (isSupabase(url)) return; // let the browser handle it, untouched

  // Navigations (the HTML document itself). This file is 2.3 MB, 640 KB of it
  // over the wire, so network-first meant every single open -- including an
  // app-switcher relaunch from the home screen -- waited for the whole
  // document before it could draw anything. That is most of what "loads for a
  // while when opening the app" is.
  //
  // So: the cached copy is served AT ONCE and the network copy is fetched
  // alongside it and cached for next time. The old comment here warned that a
  // cache-first document is how a service worker bricks an app after a real
  // deploy, and that is still true of cache-ONLY -- the revalidate half is
  // what answers it. When the copy that lands differs from the one that was
  // served, the page is told, and it offers a reload rather than taking one:
  // never pull the document out from under somebody mid-sentence.
  if (req.mode === 'navigate') {
    e.respondWith(
      caches.open(CACHE).then((c) =>
        // ignoreSearch, because a ?go=... deep link out of an email is the same
        // document as a plain open. The copy is stored under the bare path for
        // the same reason: otherwise every distinct query string would write
        // its own entry and the plain open would go on being served an old one.
        // A plain Request is the right key even though this is a navigation --
        // mode 'navigate' cannot be constructed from script, and Cache.match
        // compares the URL rather than the mode.
        c.match(req, { ignoreSearch: true }).then((cached) => {
          const key = url.origin + url.pathname;
          const fresh = fetch(req)
            .then((res) => {
              if (res && res.ok) {
                c.put(new Request(key), res.clone());
                if (cached && !sameDoc(cached, res)) tellClients({ type: 'wk-shell-updated' });
              }
              return res;
            })
            .catch(() => null);
          // Nothing cached yet (a first visit) means there is nothing to be
          // instant with, so that one load waits for the network as before,
          // with the precached shell as the offline fallback it always had.
          if (!cached) {
            return fresh.then((res) => res || c.match('index.html'));
          }
          e.waitUntil(fresh);
          return cached;
        })
      )
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
