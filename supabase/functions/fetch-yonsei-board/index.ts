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
    // articleLimit asks the board's own server to return everything in one
    // response instead of its default ~10-per-page slice -- confirmed live
    // that it honors this (478 items back in a single ~1MB response, and the
    // response doesn't grow past that either -- 478 is just every article
    // that currently exists). 1000 gives years of headroom past the current
    // count before this needs raising again; a real pagination loop across
    // the board's own "pages" isn't needed.
    const res = await fetch(`${YONSEI_BOARD_URL}?mode=list&articleLimit=1000`, {
      headers: {
        // Yonsei's server has been observed serving a different (non-list)
        // response to requests with no browser-like User-Agent.
        "User-Agent":
          "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36",
      },
    });
    if (!res.ok) throw new Error(`upstream status ${res.status}`);
    const html = await res.text();
    const items = parseYonseiBoardHtml(html);
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
