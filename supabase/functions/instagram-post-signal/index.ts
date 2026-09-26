// Edge Function: receives a webhook call from a third-party page-monitoring
// service (Visualping) watching the Yonsei GSIS CDC Instagram
// (@yonseigsis_cdc) for changes on its own schedule/infrastructure -- this
// app never visits Instagram itself. On any call that passes the shared
// secret, upserts today's date into jobboard_instagram_signal (see
// sql migrations/jobboard_instagram_signal_migration.sql).
// maybeAutoTriggerJobBoardSync() in index.html checks that table before
// firing the local job board sync script.
//
// Deliberately doesn't try to interpret Visualping's payload (what changed,
// a screenshot, etc.) -- any call that's authenticated is treated as "a
// change was detected," since the monitored region is the CDC account's
// post grid and Visualping's own diffing already decided something in it
// changed.
//
// Auth: the secret is passed as a query param (?secret=...) rather than a
// header, since a generic "Webhook URL" field is the most universally
// supported option across monitoring services, and not all of them let you
// set custom headers. Checked via check_instagram_signal_secret(), same
// Vault-secret pattern as check_yonsei_jobboard_ingest_secret. Accepts
// GET or POST, since different services default to one or the other for
// plain webhook notifications.
//
// The secret is ALSO accepted as an X-Signal-Secret header (or a Bearer
// token), which keeps it out of URLs and so out of request logs. The query
// form stays because Visualping's webhook field is a bare URL; the most a
// leaked secret can do is mark "a new post today", which only prompts a job
// board sync. No CORS: nothing calls this from a browser.

import { createClient } from "jsr:@supabase/supabase-js@2";

const CORS_HEADERS = {};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: CORS_HEADERS });
  }

  try {
    if (req.method !== "GET" && req.method !== "POST") {
      return new Response(JSON.stringify({ ok: false, message: "GET or POST only" }), {
        status: 405,
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      });
    }

    const url = new URL(req.url);
    const bearer = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
    const providedSecret = req.headers.get("X-Signal-Secret") || (bearer && !bearer.startsWith("eyJ") ? bearer : "") ||
      url.searchParams.get("secret");

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const { data: secretOk, error: secretErr } = await supabase.rpc(
      "check_instagram_signal_secret",
      { provided: providedSecret },
    );
    if (secretErr || !secretOk) {
      return new Response(JSON.stringify({ ok: false, message: "unauthorized" }), {
        status: 401,
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      });
    }

    const today = new Date().toISOString().slice(0, 10);
    const { error: upsertErr } = await supabase
      .from("jobboard_instagram_signal")
      .upsert({ signal_date: today }, { onConflict: "signal_date" });
    if (upsertErr) throw upsertErr;

    return new Response(JSON.stringify({ ok: true, signal_date: today }), {
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error("instagram-post-signal", err);
    return new Response(JSON.stringify({ ok: false, message: "internal error" }), {
      status: 200,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }
});
