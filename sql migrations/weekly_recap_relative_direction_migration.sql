-- Adds a coming/passed toggle to the weekly recap, same idea as daily
-- recap's on_day/day_before: 'coming' (default, unchanged behavior) covers
-- the 7 days starting on the day it fires; 'passed' covers the 7 days
-- ending the day before it fires -- a genuine look-back at the week that
-- just happened, with no overlap with 'coming'.

ALTER TABLE profiles ADD COLUMN IF NOT EXISTS weekly_recap_relative text NOT NULL DEFAULT 'coming';

CREATE OR REPLACE FUNCTION send_weekly_recap()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  api_key text;
  today date := (now() AT TIME ZONE 'Asia/Seoul')::date;
  today_dow int := extract(dow from (now() AT TIME ZONE 'Asia/Seoul'))::int;
  week_start date;
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
           p.notify_weekly_recap_email, p.notify_weekly_recap_inapp, p.weekly_recap_relative
    FROM profiles p
    JOIN auth.users u ON u.id = p.id
    WHERE (p.notify_weekly_recap_email OR p.notify_weekly_recap_inapp)
      AND p.weekly_recap_day = today_dow
  LOOP
    week_start := CASE WHEN rec.weekly_recap_relative = 'passed' THEN today - 7 ELSE today END;
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
