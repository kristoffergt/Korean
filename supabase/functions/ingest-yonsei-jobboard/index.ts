// Edge Function: receives already-fetched HTML of the login-gated Yonsei
// GSIS CDC "Job/Internship Board" (see parse.ts for why this can't be a
// server-side scheduled fetch like fetch-yonsei-board) and upserts the
// parsed listings into yonsei_jobboard_items (see
// sql migrations/yonsei_jobboard_migration.sql).
//
// Invoked by a bookmarklet the user clicks while logged into the board in
// their own browser -- their login never reaches this function or this
// codebase at all, only the resulting page HTML does.
//
// verify_jwt is disabled (the bookmarklet only has the publishable anon key
// available to it, not a full user session), but unlike fetch-yonsei-board
// this function WRITES data, so it can't rely on verify_jwt:false alone the
// same way -- anyone with the (intentionally public) anon key could
// otherwise inject fake listings. Custom auth instead: the caller must send
// the shared secret (stored only in Vault as 'yonsei_jobboard_ingest_secret'
// and in the bookmarklet's own source, never in this repo) in an
// X-Ingest-Secret header, checked via check_yonsei_jobboard_ingest_secret().

import { parseYonseiJobBoardHtml } from "./parse.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-ingest-secret",
};

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
    const html = typeof body?.html === "string" ? body.html : "";
    if (!html) {
      return new Response(JSON.stringify({ ok: false, message: "missing html" }), {
        status: 400,
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      });
    }

    const items = parseYonseiJobBoardHtml(html);
    if (items.length === 0) {
      return new Response(JSON.stringify({ ok: true, count: 0 }), {
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      });
    }

    const rows = items.map((it) => ({
      idx: it.idx,
      link: it.link,
      title: it.title,
      industry: it.industry,
      type: it.type,
      date_posted: it.datePosted,
      deadline: it.deadline,
      updated_at: new Date().toISOString(),
    }));

    const { error: upsertErr } = await supabase
      .from("yonsei_jobboard_items")
      .upsert(rows, { onConflict: "idx" });
    if (upsertErr) throw upsertErr;

    return new Response(JSON.stringify({ ok: true, count: items.length }), {
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
