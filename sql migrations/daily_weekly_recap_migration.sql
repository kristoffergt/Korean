-- ============================================================================
-- Daily/weekly recap: an opt-in email + in-app notification listing
-- everything on the calendar for today (daily) or the coming week (weekly),
-- reusing the existing Resend/notifications-bell pipeline (send_due_reminders(),
-- notify_yonsei_board_new_items()) rather than inventing a new delivery path.
--
-- Opt-in is a dedicated blanket column per type (profiles.notify_daily_recap /
-- notify_weekly_recap, default false), same pattern as profiles.notify_yonsei_board
-- -- NOT the generic notification_prefs table, since that table's per-type rows
-- default to email:true/in_app:true when absent (fine for fine-tuning an
-- already-on feature like reminders, but wrong as the master switch for a new
-- proactive email nobody has asked for yet).
--
-- event_occurs_on(): a server-side port of the client's expandOccurrences()
-- (index.html) recurrence stepping -- same day/week/month/year loop, same
-- excluded_dates and recur_end_date checks, same 2000-iteration safety cap --
-- needed because next_occurrence() only answers "what's the next occurrence
-- from today", not "does this event occur on this specific date", and doesn't
-- handle recur_freq='year' at all (birthdays use 'year' recurrence client-side).
--
-- Visibility mirrors the events_select RLS policy exactly (own row, or
-- shared_circle_cat(..., 'calendar') and not private) so a recap never lists
-- anything the recipient couldn't already see by opening Calendar themselves.
--
-- Cron: both fire once daily at 07:00 KST (22:00 UTC) -- daily every day,
-- weekly only Sunday 22:00 UTC (=Monday 07:00 KST), covering the week that
-- just started. Safe to re-run (guarded cron.schedule, CREATE OR REPLACE).
-- ============================================================================

ALTER TABLE profiles ADD COLUMN IF NOT EXISTS notify_daily_recap boolean NOT NULL DEFAULT false;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS notify_weekly_recap boolean NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION event_occurs_on(
  p_event_date date,
  p_freq text,
  p_interval integer,
  p_end_type text,
  p_end_date date,
  p_excluded_dates jsonb,
  p_target date
) RETURNS boolean
LANGUAGE plpgsql
AS $$
DECLARE
  cur date := p_event_date;
  interval_n integer := greatest(coalesce(p_interval, 1), 1);
  safety integer := 0;
BEGIN
  IF p_target < p_event_date THEN
    RETURN false;
  END IF;
  IF p_end_type = 'date' AND p_end_date IS NOT NULL AND p_target > p_end_date THEN
    RETURN false;
  END IF;
  IF p_excluded_dates IS NOT NULL AND p_excluded_dates ? to_char(p_target, 'YYYY-MM-DD') THEN
    RETURN false;
  END IF;
  IF p_freq IS NULL THEN
    RETURN p_target = p_event_date;
  END IF;
  WHILE cur <= p_target AND safety < 2000 LOOP
    safety := safety + 1;
    IF cur = p_target THEN
      RETURN true;
    END IF;
    IF p_freq = 'day' THEN cur := cur + (interval_n || ' days')::interval;
    ELSIF p_freq = 'week' THEN cur := cur + (interval_n*7 || ' days')::interval;
    ELSIF p_freq = 'month' THEN cur := (cur + (interval_n || ' months')::interval)::date;
    ELSIF p_freq = 'year' THEN cur := (cur + (interval_n || ' years')::interval)::date;
    ELSE RETURN false;
    END IF;
  END LOOP;
  RETURN false;
END;
$$;

CREATE OR REPLACE FUNCTION send_daily_recap()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  api_key text;
  today date := (now() AT TIME ZONE 'Asia/Seoul')::date;
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
    SELECT p.id AS uid, u.email AS user_email, p.display_name
    FROM profiles p
    JOIN auth.users u ON u.id = p.id
    WHERE p.notify_daily_recap = true
  LOOP
    list_html := '';
    item_count := 0;
    FOR ev IN
      SELECT e.title, e.event_time
      FROM events e
      WHERE (e.user_id = rec.uid OR (shared_circle_cat(rec.uid, e.user_id, 'calendar') AND coalesce(e.is_private, false) = false))
        AND event_occurs_on(e.event_date, e.recur_freq, e.recur_interval, e.recur_end_type, e.recur_end_date, e.excluded_dates, today)
      ORDER BY e.event_time NULLS LAST, e.title
    LOOP
      item_count := item_count + 1;
      list_html := list_html || '<li style="margin-bottom:6px;">' ||
        (CASE WHEN ev.event_time IS NOT NULL THEN '<strong>' || to_char(ev.event_time, 'HH12:MI AM') || '</strong> &ndash; ' ELSE '' END) ||
        ev.title || '</li>';
    END LOOP;

    IF item_count = 0 THEN
      CONTINUE;
    END IF;

    PERFORM net.http_post(
      url := 'https://api.resend.com/emails',
      headers := jsonb_build_object('Authorization', 'Bearer ' || api_key, 'Content-Type', 'application/json'),
      body := jsonb_build_object(
        'from', 'Calendar Reminders <noreply@kristoffergt.com>',
        'to', rec.user_email,
        'subject', 'Your day: ' || to_char(today, 'Mon DD'),
        'html', email_shell(
          'You''re receiving this because Daily recap is turned on in Notifications settings.',
          '<p style="margin:0 0 14px;">Hi ' || coalesce(rec.display_name, 'there') || ',</p>' ||
          '<p style="margin:0 0 10px;">Here''s what''s on for ' || to_char(today, 'YYYY-MM-DD') || ':</p>' ||
          '<ul style="margin:0 0 4px;padding-left:20px;">' || list_html || '</ul>' ||
          email_button('Open Productivity Tracker', 'https://kristoffergt.com/?go=calendar&date=' || to_char(today, 'YYYY-MM-DD'))
        )
      )
    );

    IF wants_in_app_notification(rec.uid, 'daily_recap') THEN
      INSERT INTO notifications(user_id, type, title, body, params)
      VALUES (
        rec.uid, 'daily_recap',
        'Your day: ' || item_count || ' thing' || (CASE WHEN item_count = 1 THEN '' ELSE 's' END),
        to_char(today, 'YYYY-MM-DD'),
        jsonb_build_object('date', to_char(today, 'YYYY-MM-DD'), 'count', item_count)
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
    SELECT p.id AS uid, u.email AS user_email, p.display_name
    FROM profiles p
    JOIN auth.users u ON u.id = p.id
    WHERE p.notify_weekly_recap = true
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

    IF item_count = 0 THEN
      CONTINUE;
    END IF;

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

    IF wants_in_app_notification(rec.uid, 'weekly_recap') THEN
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
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'send-daily-recap') THEN
    PERFORM cron.schedule('send-daily-recap', '0 22 * * *', 'SELECT send_daily_recap();');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'send-weekly-recap') THEN
    PERFORM cron.schedule('send-weekly-recap', '0 22 * * 0', 'SELECT send_weekly_recap();');
  END IF;
END
$do$;
