// Edge Function: weekly Korean news counts for phrases.
//
// The Q54 forecast weights current-affairs topics by a news SPIKE: what
// predicted 전동 킥보드 was that its coverage jumped to ~40 articles a week in
// the six weeks before the exam against its usual ~13, after a run of
// accidents -- not how much it was covered overall. The spike is computed in
// the browser from weekly counts; this function only counts.
//
// It has to be WEEKLY. Google News' Korean RSS samples each search and caps
// it at 100 items, so one search over six weeks returns far fewer articles
// than six one-week searches added up, and that undercount flattened the very
// spike being looked for (measured: x1.55 for 킥보드 one way, x2.78 the other).
//
// ?q=phrase|phrase&w=YYYY-MM-DD,YYYY-MM-DD  (w = week starts; each week is 7
// days from that date). Answers { counts: { phrase: { week: n } } }, n capped
// at 100 by the feed. A failed count is left out so the caller asks again.
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

const MAX_PAIRS = 120;
const CONCURRENCY = 8;
const DAY_MS = 86_400_000;
const iso = (t: number) => new Date(t).toISOString().slice(0, 10);

async function weekCount(phrase: string, week: string): Promise<number | null> {
  const from = Date.parse(week + "T00:00:00Z");
  const q = encodeURIComponent(`"${phrase}" after:${week} before:${iso(from + 7 * DAY_MS)}`);
  const res = await fetch(`https://news.google.com/rss/search?q=${q}&hl=ko&gl=KR&ceid=KR:ko`, {
    headers: { "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36" },
  });
  if (!res.ok) return null;
  const xml = await res.text();
  if (!xml.includes("<rss")) return null;
  return (xml.match(/<item>/g) || []).length;
}

Deno.serve(async (req: Request) => {
  const CORS_HEADERS = corsFor(req);
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS_HEADERS });
  try {
    const url = new URL(req.url);
    const phrases = (url.searchParams.get("q") || "")
      .split("|").map((s) => s.trim()).filter((s) => s && s.length <= 40)
      .filter((s, i, a) => a.indexOf(s) === i);
    const weeks = (url.searchParams.get("w") || "")
      .split(",").map((s) => s.trim()).filter((s) => /^\d{4}-\d{2}-\d{2}$/.test(s))
      .filter((s, i, a) => a.indexOf(s) === i);
    const pairs = phrases.flatMap((p) => weeks.map((w) => [p, w] as const)).slice(0, MAX_PAIRS);
    const counts: Record<string, Record<string, number>> = {};
    for (let i = 0; i < pairs.length; i += CONCURRENCY) {
      const batch = pairs.slice(i, i + CONCURRENCY);
      const got = await Promise.all(batch.map(([p, w]) => weekCount(p, w).catch(() => null)));
      batch.forEach(([p, w], k) => {
        if (got[k] === null) return;
        (counts[p] = counts[p] || {})[w] = got[k] as number;
      });
    }
    return new Response(JSON.stringify({ counts, at: new Date().toISOString() }), {
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error("topik-news-signal", err);
    return new Response(JSON.stringify({ counts: {}, error: true }), {
      status: 200, headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }
});
