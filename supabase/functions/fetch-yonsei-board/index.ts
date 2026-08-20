// Edge Function: server-side fetch + parse of the public Yonsei GSIS
// "Official Notices" board, replacing the r.jina.ai reader-proxy the client
// used previously (see index.html's fetchYonseiBoards()).
//
// No auth required: the board itself is public and unauthenticated, and this
// function does no writes -- it only proxies+parses a public page. Deployed
// with verify_jwt disabled for that reason.

import { parseYonseiBoardHtml, YONSEI_BOARD_URL } from "./parse.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: CORS_HEADERS });
  }

  try {
    // articleLimit asks the board's own server for its top N items in one
    // response instead of its default ~10-per-page slice -- confirmed live
    // that it honors this (up to the 478 that currently exist). The caller
    // passes ?limit= sized to whatever it actually needs right now (e.g.
    // just enough for the page it's displaying) rather than this function
    // always requesting everything -- a bigger articleLimit takes
    // meaningfully longer upstream (~0.1s for 10 items vs ~1.7s for 1000),
    // and there's no reason to pay that for history nobody's paging into.
    //
    // article.offset (which the site's own pagination links use) was tried
    // here too, hoping to fetch only a fresh slice when paging deeper
    // instead of re-requesting everything up to that point -- confirmed
    // live that it has NO effect on a plain unauthenticated request (same
    // top items come back regardless of offset), so windowed/incremental
    // fetching isn't available; "ask for the top N" is the only lever.
    const url = new URL(req.url);
    const requestedLimit = parseInt(url.searchParams.get("limit") || "", 10);
    const limit = Number.isFinite(requestedLimit) && requestedLimit > 0
      ? Math.min(requestedLimit, 1000)
      : 50;
    const res = await fetch(`${YONSEI_BOARD_URL}?mode=list&articleLimit=${limit}`, {
      headers: {
        // Yonsei's server has been observed serving a different (non-list)
        // response to requests with no browser-like User-Agent.
        "User-Agent":
          "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36",
      },
    });
    if (!res.ok) throw new Error(`upstream status ${res.status}`);
    const html = await res.text();
    const items = parseYonseiBoardHtml(html, limit);
    return new Response(JSON.stringify({ items, error: items.length === 0 }), {
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  } catch (err) {
    return new Response(
      JSON.stringify({ items: [], error: true, message: String(err) }),
      { status: 200, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } },
    );
  }
});
