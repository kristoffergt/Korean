-- ============================================================================
-- Expands the daily/weekly recap (see daily_weekly_recap_migration.sql) with
-- real customization instead of one blanket on/off switch:
--
-- - Per-channel control (separate Email / In-app booleans, both default
--   false) instead of one flag gating both -- matches the visual format of
--   the other notification rows, and lets you e.g. get the in-app bell
--   without the email.
-- - daily_recap_time ('morning'|'noon'|'evening'): which of three fixed
--   daily send slots you're on.
-- - daily_recap_relative ('on_day'|'day_before'): whether the recap
--   describes the day it's sent on, or previews the day after (natural
--   pairing with an 'evening' slot -- today's agenda is stale by evening).
-- - daily_recap_days (0=Sun..6=Sat array): which days of the week you want
--   it at all, default every day.
-- - weekly_recap_day (0=Sun..6=Sat): which weekday the weekly recap fires
--   on, no longer hardcoded to Monday.
--
-- The old blanket notify_daily_recap/notify_weekly_recap columns are
-- dropped -- this feature was only added minutes before this migration in
-- the same session, nobody has real settings stored in them yet.
--
-- Cron: daily recap now needs three schedules (one per time slot, each
-- passing its slot to send_daily_recap()); weekly recap now fires once a
-- day (checking each user's own weekly_recap_day) instead of Sunday-only.
-- Safe to re-run (CREATE OR REPLACE, guarded cron.schedule, unschedule-then-
-- reschedule for the ones whose cadence changed).
-- ============================================================================

ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS notify_daily_recap_email boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS notify_daily_recap_inapp boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS notify_weekly_recap_email boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS notify_weekly_recap_inapp boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS daily_recap_time text NOT NULL DEFAULT 'morning',
  ADD COLUMN IF NOT EXISTS daily_recap_relative text NOT NULL DEFAULT 'on_day',
  ADD COLUMN IF NOT EXISTS daily_recap_days integer[] NOT NULL DEFAULT '{0,1,2,3,4,5,6}',
  ADD COLUMN IF NOT EXISTS weekly_recap_day integer NOT NULL DEFAULT 1;

ALTER TABLE profiles DROP COLUMN IF EXISTS notify_daily_recap;
ALTER TABLE profiles DROP COLUMN IF EXISTS notify_weekly_recap;

CREATE OR REPLACE FUNCTION send_daily_recap(p_time_slot text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  api_key text;
  today date := (now() AT TIME ZONE 'Asia/Seoul')::date;
  today_dow int := extract(dow from (now() AT TIME ZONE 'Asia/Seoul'))::int;
  target_date date;
  rec record;
  ev record;
  list_html text;
  item_count int;
BEGIN
  SELECT decrypted_secret INTO api_key FROM vault.decrypted_secrets WHERE name = 'resend_api_key';
  IF api_key IS NULL THEN
    RAISE NOTICE 'No Resend API key found in vault';
    RETURN;
  END IF;

  FOR rec IN
    SELECT p.id AS uid, u.email AS user_email, p.display_name,
           p.notify_daily_recap_email, p.notify_daily_recap_inapp, p.daily_recap_relative
    FROM profiles p
    JOIN auth.users u ON u.id = p.id
    WHERE p.daily_recap_time = p_time_slot
      AND (p.notify_daily_recap_email OR p.notify_daily_recap_inapp)
      AND today_dow = ANY(p.daily_recap_days)
  LOOP
    target_date := CASE WHEN rec.daily_recap_relative = 'day_before' THEN today + 1 ELSE today END;
    list_html := '';
    item_count := 0;
    FOR ev IN
      SELECT e.title, e.event_time
      FROM events e
      WHERE (e.user_id = rec.uid OR (shared_circle_cat(rec.uid, e.user_id, 'calendar') AND coalesce(e.is_private, false) = false))
        AND event_occurs_on(e.event_date, e.recur_freq, e.recur_interval, e.recur_end_type, e.recur_end_date, e.excluded_dates, target_date)
      ORDER BY e.event_time NULLS LAST, e.title
    LOOP
      item_count := item_count + 1;
      list_html := list_html || '<li style="margin-bottom:6px;">' ||
        (CASE WHEN ev.event_time IS NOT NULL THEN '<strong>' || to_char(ev.event_time, 'HH12:MI AM') || '</strong> &ndash; ' ELSE '' END) ||
        ev.title || '</li>';
    END LOOP;

    -- Nothing on the calendar that day -- don't send an empty recap.
    IF item_count = 0 THEN
      CONTINUE;
    END IF;

    IF rec.notify_daily_recap_email THEN
      PERFORM net.http_post(
        url := 'https://api.resend.com/emails',
        headers := jsonb_build_object('Authorization', 'Bearer ' || api_key, 'Content-Type', 'application/json'),
        body := jsonb_build_object(
          'from', 'Calendar Reminders <noreply@kristoffergt.com>',
          'to', rec.user_email,
          'subject', 'Your day: ' || to_char(target_date, 'Mon DD'),
          'html', email_shell(
            'You''re receiving this because Daily recap is turned on in Notifications settings.',
            '<p style="margin:0 0 14px;">Hi ' || coalesce(rec.display_name, 'there') || ',</p>' ||
            '<p style="margin:0 0 10px;">Here''s what''s on for ' || to_char(target_date, 'YYYY-MM-DD') || ':</p>' ||
            '<ul style="margin:0 0 4px;padding-left:20px;">' || list_html || '</ul>' ||
            email_button('Open Productivity Tracker', 'https://kristoffergt.com/?go=calendar&date=' || to_char(target_date, 'YYYY-MM-DD'))
          )
        )
      );
    END IF;

    IF rec.notify_daily_recap_inapp THEN
      INSERT INTO notifications(user_id, type, title, body, params)
      VALUES (
        rec.uid, 'daily_recap',
        'Your day: ' || item_count || ' thing' || (CASE WHEN item_count = 1 THEN '' ELSE 's' END),
        to_char(target_date, 'YYYY-MM-DD'),
        jsonb_build_object('date', to_char(target_date, 'YYYY-MM-DD'), 'count', item_count)
      );
    END IF;
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION send_weekly_recap()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  api_key text;
  week_start date := (now() AT TIME ZONE 'Asia/Seoul')::date;
  today_dow int := extract(dow from (now() AT TIME ZONE 'Asia/Seoul'))::int;
  d date;
  rec record;
  ev record;
  day_html text;
  list_html text;
  item_count int;
  day_count int;
BEGIN
  SELECT decrypted_secret INTO api_key FROM vault.decrypted_secrets WHERE name = 'resend_api_key';
  IF api_key IS NULL THEN
    RAISE NOTICE 'No Resend API key found in vault';
    RETURN;
  END IF;

  FOR rec IN
    SELECT p.id AS uid, u.email AS user_email, p.display_name,
           p.notify_weekly_recap_email, p.notify_weekly_recap_inapp
    FROM profiles p
    JOIN auth.users u ON u.id = p.id
    WHERE (p.notify_weekly_recap_email OR p.notify_weekly_recap_inapp)
      AND p.weekly_recap_day = today_dow
  LOOP
    list_html := '';
    item_count := 0;
    FOR d IN SELECT generate_series(week_start, week_start + 6, interval '1 day')::date LOOP
      day_html := '';
      day_count := 0;
      FOR ev IN
        SELECT e.title, e.event_time
        FROM events e
        WHERE (e.user_id = rec.uid OR (shared_circle_cat(rec.uid, e.user_id, 'calendar') AND coalesce(e.is_private, false) = false))
          AND event_occurs_on(e.event_date, e.recur_freq, e.recur_interval, e.recur_end_type, e.recur_end_date, e.excluded_dates, d)
        ORDER BY e.event_time NULLS LAST, e.title
      LOOP
        day_count := day_count + 1;
        item_count := item_count + 1;
        day_html := day_html || '<li style="margin-bottom:4px;">' ||
          (CASE WHEN ev.event_time IS NOT NULL THEN '<strong>' || to_char(ev.event_time, 'HH12:MI AM') || '</strong> &ndash; ' ELSE '' END) ||
          ev.title || '</li>';
      END LOOP;
      IF day_count > 0 THEN
        list_html := list_html || '<p style="margin:12px 0 4px;font-weight:700;">' || to_char(d, 'Dy, Mon DD') || '</p><ul style="margin:0 0 4px;padding-left:20px;">' || day_html || '</ul>';
      END IF;
    END LOOP;

    -- Nothing on the calendar all week -- don't send an empty recap.
    IF item_count = 0 THEN
      CONTINUE;
    END IF;

    IF rec.notify_weekly_recap_email THEN
      PERFORM net.http_post(
        url := 'https://api.resend.com/emails',
        headers := jsonb_build_object('Authorization', 'Bearer ' || api_key, 'Content-Type', 'application/json'),
        body := jsonb_build_object(
          'from', 'Calendar Reminders <noreply@kristoffergt.com>',
          'to', rec.user_email,
          'subject', 'Your week: ' || to_char(week_start, 'Mon DD'),
          'html', email_shell(
            'You''re receiving this because Weekly recap is turned on in Notifications settings.',
            '<p style="margin:0 0 14px;">Hi ' || coalesce(rec.display_name, 'there') || ',</p>' ||
            '<p style="margin:0 0 10px;">Here''s your week starting ' || to_char(week_start, 'YYYY-MM-DD') || ':</p>' ||
            list_html ||
            email_button('Open Productivity Tracker', 'https://kristoffergt.com/?go=calendar&date=' || to_char(week_start, 'YYYY-MM-DD') || '&view=week')
          )
        )
      );
    END IF;

    IF rec.notify_weekly_recap_inapp THEN
      INSERT INTO notifications(user_id, type, title, body, params)
      VALUES (
        rec.uid, 'weekly_recap',
        'Your week: ' || item_count || ' thing' || (CASE WHEN item_count = 1 THEN '' ELSE 's' END),
        to_char(week_start, 'YYYY-MM-DD'),
        jsonb_build_object('date', to_char(week_start, 'YYYY-MM-DD'), 'count', item_count)
      );
    END IF;
  END LOOP;
END;
$$;

DO $do$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'send-daily-recap') THEN
    PERFORM cron.unschedule('send-daily-recap');
  END IF;
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'send-weekly-recap') THEN
    PERFORM cron.unschedule('send-weekly-recap');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'send-daily-recap-morning') THEN
    PERFORM cron.schedule('send-daily-recap-morning', '0 22 * * *', $c$SELECT send_daily_recap('morning');$c$);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'send-daily-recap-noon') THEN
    PERFORM cron.schedule('send-daily-recap-noon', '0 3 * * *', $c$SELECT send_daily_recap('noon');$c$);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'send-daily-recap-evening') THEN
    PERFORM cron.schedule('send-daily-recap-evening', '0 10 * * *', $c$SELECT send_daily_recap('evening');$c$);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'send-weekly-recap') THEN
    PERFORM cron.schedule('send-weekly-recap', '0 22 * * *', 'SELECT send_weekly_recap();');
  END IF;
END
$do$;
