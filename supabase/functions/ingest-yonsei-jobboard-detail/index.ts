// Edge Function: receives the RAW HTML of one Yonsei GSIS CDC job posting's
// own detail page, extracts its full description text (everything below
// the metadata table) and stores it against that posting's existing
// yonsei_jobboard_items row -- and also extracts the "Next" link/date from
// the same HTML and hands it back, so the calling script knows where to
// navigate next without doing any parsing itself.
//
// Companion to ingest-yonsei-jobboard, not a replacement -- that one syncs
// the lightweight listing rows from the board's LIST pages; this one is
// called once per posting by scripts/yonsei_jobboard_detail_fetch.py,
// which walks each posting's own DETAIL page via its own "Next" link,
// since visiting every posting individually is a slower, deliberately
// separate operation from the quick listing sync. Parsing (not browser
// automation) lives here on purpose, same reasoning as the other two
// ingest functions: fixable without touching the local script or its
// Chrome profile.
//
// NOTE: unlike fetch-yonsei-board's and ingest-yonsei-jobboard's parsers,
// this one has NOT been verified against a real saved copy of a CDC
// detail page (that page is login-gated, so there was no HTML sample to
// test against while building this) -- it's a best-effort extraction based
// on the visible page layout (a Title/Type/Deadline/Date/Read metadata
// table, then free-text content, then a Prev/Next navigation table). If
// the first real run doesn't extract a Next link or grabs the wrong
// content region, that's expected on the first pass and just needs a
// tweak here, not a change to the Python side.
//
// Same auth pattern as ingest-yonsei-jobboard: shared secret (Vault:
// 'yonsei_jobboard_ingest_secret') in an X-Ingest-Secret header, checked
// via check_yonsei_jobboard_ingest_secret(). verify_jwt disabled for the
// same reason -- caller is a local script with only the anon key.

import { createClient } from "jsr:@supabase/supabase-js@2";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-ingest-secret",
};

const NAMED_ENTITIES: Record<string, string> = {
  "&lt;": "<", "&gt;": ">", "&quot;": '"', "&#39;": "'", "&apos;": "'", "&nbsp;": " ",
};
function decodeEntities(s: string): string {
  return s
    .replace(/&(?:lt|gt|quot|apos|nbsp|#39);/gi, (m) => NAMED_ENTITIES[m.toLowerCase()] ?? m)
    .replace(/&#(\d+);/g, (_, d) => {
      const code = Number(d);
      return code > 0 && code <= 0x10ffff ? String.fromCodePoint(code) : "";
    })
    .replace(/&amp;/gi, "&");
}
function htmlToText(html: string): string {
  const noTags = html
    .replace(/<script[\s\S]*?<\/script>/gi, " ")
    .replace(/<style[\s\S]*?<\/style>/gi, " ")
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<\/(p|div|tr|li)>/gi, "\n")
    .replace(/<[^>]+>/g, " ");
  return decodeEntities(noTags).replace(/[ \t]+/g, " ").replace(/\n\s*\n\s*\n+/g, "\n\n").trim();
}
function absolutize(href: string, base: string): string {
  if (/^https?:\/\//i.test(href)) return href;
  const origin = new URL(base).origin;
  if (href.startsWith("/")) return origin + href;
  const baseDir = base.slice(0, base.lastIndexOf("/") + 1);
  return baseDir + href;
}

// Everything between the end of the metadata table (marked by a "Read"
// label -- the last header in that table per the visible layout) and the
// start of the Prev/Next navigation table (marked by a "Next" label).
function extractDescription(html: string): string {
  const readIdx = html.search(/Read/i);
  let start = 0;
  if (readIdx !== -1) {
    const tableEnd = html.indexOf("</table>", readIdx);
    start = tableEnd !== -1 ? tableEnd + "</table>".length : readIdx;
  }
  const nextIdx = html.indexOf(">Next<", start);
  const nextLabelIdx = nextIdx !== -1 ? nextIdx : html.indexOf("Next", start);
  let end = html.length;
  if (nextLabelIdx !== -1) {
    const tableStart = html.lastIndexOf("<table", nextLabelIdx);
    end = tableStart !== -1 && tableStart > start ? tableStart : nextLabelIdx;
  }
  return htmlToText(html.slice(start, end));
}

// The "Next" row shows the next posting's title as a link and its date in
// parentheses, e.g. `Next | Toss Securities - ... (Aug 20, 2026)`. Scans a
// window after the "Next" label for the first <a href> and the first
// (Mon DD, YYYY)-shaped date near it.
function extractNext(html: string, baseUrl: string): { url: string; dateIso: string | null } | null {
  const nextIdx = html.search(/>Next</i);
  const searchFrom = nextIdx !== -1 ? nextIdx : html.search(/\bNext\b/i);
  if (searchFrom === -1) return null;
  const window = html.slice(searchFrom, searchFrom + 1500);
  const linkMatch = window.match(/<a\b[^>]*href="([^"]+)"[^>]*>/i);
  if (!linkMatch) return null;
  const url = absolutize(decodeEntities(linkMatch[1]), baseUrl);
  const dateMatch = window.match(/\(([A-Za-z]{3,9}\s+\d{1,2},\s+\d{4})\)/);
  let dateIso: string | null = null;
  if (dateMatch) {
    const parsed = new Date(dateMatch[1]);
    if (!isNaN(parsed.getTime())) dateIso = parsed.toISOString().slice(0, 10);
  }
  return { url, dateIso };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: CORS_HEADERS });
  }

  try {
    if (req.method !== "POST") {
      return new Response(JSON.stringify({ ok: false, message: "POST only" }), {
        status: 405,
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      });
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const providedSecret = req.headers.get("x-ingest-secret");
    const { data: secretOk, error: secretErr } = await supabase.rpc(
      "check_yonsei_jobboard_ingest_secret",
      { provided: providedSecret },
    );
    if (secretErr || !secretOk) {
      return new Response(JSON.stringify({ ok: false, message: "unauthorized" }), {
        status: 401,
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      });
    }

    const body = await req.json();
    const idx = Number(body?.idx);
    const html = typeof body?.html === "string" ? body.html : "";
    const url = typeof body?.url === "string" ? body.url : "";
    if (!Number.isFinite(idx) || !html || !url) {
      return new Response(JSON.stringify({ ok: false, message: "missing idx, html, or url" }), {
        status: 400,
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      });
    }

    const description = extractDescription(html);
    const next = extractNext(html, url);

    const { error: updateErr, count } = await supabase
      .from("yonsei_jobboard_items")
      .update({ full_description: description, updated_at: new Date().toISOString() }, { count: "exact" })
      .eq("idx", idx);
    if (updateErr) throw updateErr;

    return new Response(JSON.stringify({ ok: true, matched: count ?? 0, descriptionLength: description.length, next }), {
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : JSON.stringify(err);
    return new Response(JSON.stringify({ ok: false, message }), {
      status: 200,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }
});
