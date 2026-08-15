-- ============================================================================
-- Adds one-click email notifications for new posts on the public Yonsei GSIS
-- "Official Notices" board (see yonsei_boards_migration.sql for the display
-- toggle this sits alongside).
--
-- profiles.notify_yonsei_board: own-row-only opt-in, same pattern as
-- show_yonsei_boards/hide_from_leaderboards -- plain client .update() on the
-- caller's own row, no new RLS policy needed (profiles already has an
-- own-row UPDATE policy, see privacy_rls_migration.sql).
--
-- yonsei_board_seen: server-side dedup log of article numbers we've already
-- emailed about, keyed by the numeric articleNo pulled out of the notice
-- link. No RLS policies -- only ever touched by notify_yonsei_board_new_items
-- below (SECURITY DEFINER) and the notify-yonsei-board edge function's
-- service-role client, both of which bypass RLS anyway; leaving it
-- policy-less keeps it unreadable/unwritable from anon or authenticated
-- clients.
--
-- notify_yonsei_board_new_items(items jsonb): called by the notify-yonsei-
-- board edge function (via its service-role client, so no extra GRANT is
-- needed) with the board's current items ({title,link,date}[], same shape
-- fetch-yonsei-board already returns). Atomically figures out which ones are
-- actually new (INSERT ... ON CONFLICT DO NOTHING RETURNING), and if any are,
-- sends ONE digest email per subscriber -- not one email per item, so a run
-- that finds several new notices at once doesn't spam. Mirrors the existing
-- send_due_reminders() function's Resend-via-vault approach exactly (same
-- 'resend_api_key' vault secret, same net.http_post call shape, same
-- noreply@kristoffergt.com sender); send_due_reminders() itself predates this
-- repo's migration files, so there's no earlier .sql file to point to for
-- that pattern.
--
-- A pg_cron job (added by this migration) invokes the notify-yonsei-board
-- edge function every 30 minutes, matching the existing send-due-reminders
-- cadence. The cron job only fires the edge function; the edge function does
-- the actual fetch+parse+RPC call.
--
-- Safe to re-run.
-- ============================================================================

ALTER TABLE profiles ADD COLUMN IF NOT EXISTS notify_yonsei_board boolean NOT NULL DEFAULT false;

CREATE TABLE IF NOT EXISTS yonsei_board_seen (
  article_no text PRIMARY KEY,
  first_seen_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE yonsei_board_seen ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION notify_yonsei_board_new_items(items jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  api_key text;
  item jsonb;
  v_article_no text;
  new_items jsonb := '[]'::jsonb;
  rec record;
  list_html text;
BEGIN
  FOR item IN SELECT * FROM jsonb_array_elements(items)
  LOOP
    v_article_no := substring(item->>'link' FROM 'articleNo=(\d+)');
    IF v_article_no IS NULL THEN
      CONTINUE;
    END IF;

    INSERT INTO yonsei_board_seen (article_no)
    VALUES (v_article_no)
    ON CONFLICT (article_no) DO NOTHING;

    IF FOUND THEN
      new_items := new_items || jsonb_build_array(item);
    END IF;
  END LOOP;

  IF jsonb_array_length(new_items) = 0 THEN
    RETURN;
  END IF;

  SELECT decrypted_secret INTO api_key
  FROM vault.decrypted_secrets
  WHERE name = 'resend_api_key';

  IF api_key IS NULL THEN
    RAISE NOTICE 'No Resend API key found in vault';
    RETURN;
  END IF;

  list_html := (
    SELECT string_agg(
      '<li><a href="' || (elem->>'link') || '">' || (elem->>'title') || '</a> (' || (elem->>'date') || ')</li>',
      ''
    )
    FROM jsonb_array_elements(new_items) elem
  );

  FOR rec IN
    SELECT u.email AS user_email, p.display_name
    FROM profiles p
    JOIN auth.users u ON u.id = p.id
    WHERE p.notify_yonsei_board = true
  LOOP
    PERFORM net.http_post(
      url := 'https://api.resend.com/emails',
      headers := jsonb_build_object(
        'Authorization', 'Bearer ' || api_key,
        'Content-Type', 'application/json'
      ),
      body := jsonb_build_object(
        'from', 'Yonsei Notices <noreply@kristoffergt.com>',
        'to', rec.user_email,
        'subject', 'New Yonsei GSIS notice' || (CASE WHEN jsonb_array_length(new_items) > 1 THEN 's' ELSE '' END),
        'html',
          '<p>Hi ' || coalesce(rec.display_name, 'there') || ',</p>' ||
          '<p>New on the Yonsei GSIS Official Notices board:</p>' ||
          '<ul>' || list_html || '</ul>'
      )
    );
  END LOOP;
END;
$function$;

GRANT EXECUTE ON FUNCTION notify_yonsei_board_new_items(jsonb) TO service_role;

DO $do$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'notify-yonsei-board-subscribers') THEN
    PERFORM cron.schedule(
      'notify-yonsei-board-subscribers',
      '*/30 * * * *',
      $cron$
      SELECT net.http_post(
        url := 'https://kbqwitmxpmkueryjsyip.supabase.co/functions/v1/notify-yonsei-board',
        headers := '{"Content-Type": "application/json"}'::jsonb,
        body := '{}'::jsonb
      );
      $cron$
    );
  END IF;
END
$do$;
