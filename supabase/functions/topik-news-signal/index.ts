// Edge Function: how much the Korean news is talking about each phrase.
//
// The Q54 forecast weights current-affairs topics by news coverage, since a
// topic like 전동 킥보드 turns up after months of accidents in the papers.
// For each phrase this reads Google News' Korean RSS for the last 90 days and
// answers with ARTICLES PER DAY.
//
// The feed caps at 100 items, newest first, so a plain count saturates for
// anything widely covered. Density does not: when 100 come back, how far back
// the 100th one reaches is what says how busy the topic is (100 in 3 days is
// a story, 100 in 80 days is background). Fewer than 100 is simply n / 90.
//
// No auth and no writes: it proxies a public feed. Deployed with verify_jwt
// off, and only this site may call it from a browser.

const ALLOWED_ORIGINS = ["https://kristoffergt.com", "https://www.kristoffergt.com"];
function corsFor(req: Request): Record<string, string> {
  const origin = req.headers.get("Origin") || "";
  const ok = ALLOWED_ORIGINS.includes(origin) || /^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(origin);
  return ok
    ? {
      "Access-Control-Allow-Origin": origin,
      "Access-Control-Allow-Methods": "GET, OPTIONS",
      "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
      "Vary": "Origin",
    }
    : { "Vary": "Origin" };
}

const WINDOW_DAYS = 90;
const MAX_PHRASES = 80;
const CONCURRENCY = 6;
const DAY_MS = 86_400_000;

async function density(phrase: string): Promise<{ perDay: number; n: number } | null> {
  const q = encodeURIComponent(`"${phrase}" when:${WINDOW_DAYS}d`);
  const res = await fetch(`https://news.google.com/rss/search?q=${q}&hl=ko&gl=KR&ceid=KR:ko`, {
    headers: { "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36" },
  });
  if (!res.ok) return null;
  const xml = await res.text();
  const dates = [...xml.matchAll(/<pubDate>([^<]+)<\/pubDate>/g)]
    .map((m) => Date.parse(m[1]))
    .filter((t) => Number.isFinite(t))
    .sort((a, b) => b - a);
  const n = dates.length;
  if (n < 100) return { perDay: n / WINDOW_DAYS, n };
  // Saturated: the span the newest 100 cover. Never less than a day, so one
  // burst of syndicated copies cannot read as infinitely busy.
  const spanDays = Math.max(1, (Date.now() - dates[n - 1]) / DAY_MS);
  return { perDay: n / spanDays, n };
}

Deno.serve(async (req: Request) => {
  const CORS_HEADERS = corsFor(req);
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS_HEADERS });
  try {
    const url = new URL(req.url);
    const phrases = (url.searchParams.get("q") || "")
      .split("|").map((s) => s.trim()).filter(Boolean)
      .filter((s, i, a) => a.indexOf(s) === i)
      .slice(0, MAX_PHRASES)
      .filter((s) => s.length <= 40);
    const out: Record<string, { perDay: number; n: number } | null> = {};
    for (let i = 0; i < phrases.length; i += CONCURRENCY) {
      const batch = phrases.slice(i, i + CONCURRENCY);
      const got = await Promise.all(batch.map((p) => density(p).catch(() => null)));
      batch.forEach((p, k) => (out[p] = got[k]));
    }
    return new Response(JSON.stringify({ signals: out, at: new Date().toISOString() }), {
      headers: { ...CORS_HEADERS, "Content-Type": "application/json", "Cache-Control": "public, max-age=21600" },
    });
  } catch (err) {
    console.error("topik-news-signal", err);
    return new Response(JSON.stringify({ signals: {}, error: true }), {
      status: 200, headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }
});
