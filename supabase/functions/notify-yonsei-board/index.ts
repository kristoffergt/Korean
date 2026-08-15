// Edge Function: fetches+parses the public Yonsei GSIS "Official Notices"
// board (same as fetch-yonsei-board) and hands the current item list to the
// notify_yonsei_board_new_items SQL function, which does the actual
// new-item bookkeeping and email sending (see
// sql migrations/yonsei_boards_notify_migration.sql for that logic and why
// it lives in SQL rather than here -- short version: it needs the
// 'resend_api_key' Vault secret, and email-sending was already established
// there by the pre-existing send_due_reminders() function).
//
// Invoked on a schedule by pg_cron (every 30 minutes, see the migration
// above), not by end users -- verify_jwt is disabled the same way it is on
// fetch-yonsei-board, since this proxies a public page and every write it
// triggers is idempotent (new-item detection is keyed on Yonsei's own
// article numbers), so nothing bad happens if it's ever invoked out of
// band.

import { parseYonseiBoardHtml, YONSEI_BOARD_URL } from "./parse.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

Deno.serve(async (req: Request) => {
  try {
    const res = await fetch(YONSEI_BOARD_URL, {
      headers: {
        "User-Agent":
          "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36",
      },
    });
    if (!res.ok) throw new Error(`upstream status ${res.status}`);
    const html = await res.text();
    const items = parseYonseiBoardHtml(html);

    if (items.length === 0) {
      return new Response(JSON.stringify({ ok: true, checked: 0 }), {
        headers: { "Content-Type": "application/json" },
      });
    }

    // Service-role client: bypasses RLS so it can call the SECURITY DEFINER
    // notify function regardless of who (if anyone) is "logged in" to this
    // request -- there isn't a logged-in user, this is a cron-driven job.
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );
    const { error } = await supabase.rpc("notify_yonsei_board_new_items", { items });
    if (error) throw error;

    return new Response(JSON.stringify({ ok: true, checked: items.length }), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : JSON.stringify(err);
    return new Response(JSON.stringify({ ok: false, message }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  }
});
