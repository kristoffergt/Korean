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

// The strings a push is rendered with (see the push handler below). Its own
// cache so a new shell version does not throw it away with the old shell.
const NOTIF_I18N_CACHE = 'pt-notif-i18n';
const NOTIF_I18N_URL = './__notif-i18n.json';

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== CACHE && k !== NOTIF_I18N_CACHE).map((k) => caches.delete(k)))
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

// ---------------------------------------------------------------------------
// Push notifications. The server sends a notification's type and params, not
// finished text (supabase/functions/send-push), and the text is built here in
// the phone's own language, from strings the app hands over on every load
// and language change -- the same strings, and the same rules, the bell uses
// in renderNotifText(). Anything unrecognised falls back to the stored
// English title and body, exactly as the bell does.
// ---------------------------------------------------------------------------
self.addEventListener('message', (e) => {
  const d = e.data;
  if (!d || d.type !== 'pt-notif-i18n') return;
  const body = JSON.stringify({ lang: d.lang || 'en', strings: d.strings || {} });
  e.waitUntil(caches.open(NOTIF_I18N_CACHE).then((c) =>
    c.put(NOTIF_I18N_URL, new Response(body, { headers: { 'Content-Type': 'application/json' } }))));
});

async function readNotifI18n() {
  try {
    const c = await caches.open(NOTIF_I18N_CACHE);
    const r = await c.match(NOTIF_I18N_URL);
    if (r) return await r.json();
  } catch (_) { /* fall through to English */ }
  return { lang: 'en', strings: {} };
}

// localDateStr() in index.html, which reads the day from a YYYY-MM-DD string.
function pushDate(iso, lang) {
  const parts = String(iso).split('-');
  if (parts.length !== 3) return String(iso);
  return lang === 'ko' ? parts[0] + '/' + parts[1] + '/' + parts[2] : parts[2] + '/' + parts[1] + '/' + parts[0];
}

function pushText(n, i18n) {
  const s = i18n.strings || {};
  const p = n.params || {};
  const lang = i18n.lang;
  if (n.type === 'push_test') return { title: s.testTitle || 'Push notifications are on', body: s.testBody || '' };
  if (n.type === 'system' && p.key === 'site_pin_required' && s.pinTitle) return { title: s.pinTitle, body: s.pinBody || '' };
  if (n.type === 'reminder' && p.event_title && s.reminderTitleTpl) {
    return { title: s.reminderTitleTpl.replace('{title}', p.event_title), body: p.date ? pushDate(p.date, lang) : (n.body || '') };
  }
  if (n.type === 'yonsei_board' && typeof p.count === 'number' && s.yonseiOne) {
    return { title: p.count > 1 ? s.yonseiMany : s.yonseiOne, body: n.body || '' };
  }
  if (n.type === 'link_accepted' && p.name && s.linkAcceptedTpl) {
    return { title: s.linkAcceptedTpl.replace('{name}', p.name), body: n.body || '' };
  }
  if ((n.type === 'daily_recap' || n.type === 'weekly_recap') && typeof p.count === 'number') {
    const daily = n.type === 'daily_recap';
    const tpl = p.count === 1 ? (daily ? s.dailyOne : s.weeklyOne) : (daily ? s.dailyMany : s.weeklyMany);
    if (tpl) return { title: tpl.replace('{n}', String(p.count)), body: n.body || (p.date ? pushDate(p.date, lang) : '') };
  }
  return { title: n.title || 'kristoffergt', body: n.body || '' };
}

self.addEventListener('push', (e) => {
  let n = {};
  try { n = e.data ? e.data.json() : {}; } catch (_) { n = { title: e.data ? e.data.text() : '' }; }
  // Every push has to show something: iOS withdraws push from a web app that
  // receives one and draws nothing.
  e.waitUntil(readNotifI18n().then((i18n) => {
    const text = pushText(n, i18n);
    return self.registration.showNotification(text.title, {
      body: text.body,
      icon: 'icon-192.png',
      badge: 'icon-192.png',
      lang: i18n.lang,
      tag: n.id ? 'pt-notif-' + n.id : 'pt-notif',
      data: { id: n.id || null },
    });
  }));
});

// A tap opens the thing the notification is about. An app already open is
// brought forward and told which one; otherwise the app opens cold with
// ?notif=<id>, which handleDeepLinkParam() in index.html follows once signed in.
self.addEventListener('notificationclick', (e) => {
  e.notification.close();
  const id = e.notification.data && e.notification.data.id;
  const url = new URL(id ? './?notif=' + encodeURIComponent(id) : './', self.registration.scope).href;
  e.waitUntil((async () => {
    const all = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    const open = all.find((c) => c.url.startsWith(self.registration.scope));
    if (open) {
      await open.focus();
      if (id) open.postMessage({ type: 'pt-open-notif', id });
      return;
    }
    await self.clients.openWindow(url);
  })());
});
