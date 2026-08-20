-- Lets a user exclude whole event kinds (birthdays, courses, etc.) from
-- BOTH daily and weekly recaps -- one shared setting, not per-recap, since
-- "I don't want birthdays cluttering my recap" applies the same way to
-- either one.

ALTER TABLE profiles ADD COLUMN IF NOT EXISTS recap_excluded_kinds text[] NOT NULL DEFAULT '{}';

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
           p.notify_daily_recap_email, p.notify_daily_recap_inapp, p.daily_recap_relative, p.recap_excluded_kinds
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
        AND NOT (e.kind = ANY(rec.recap_excluded_kinds))
        AND event_occurs_on(e.event_date, e.recur_freq, e.recur_interval, e.recur_end_type, e.recur_end_date, e.excluded_dates, target_date)
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
  today date := (now() AT TIME ZONE 'Asia/Seoul')::date;
  today_dow int := extract(dow from (now() AT TIME ZONE 'Asia/Seoul'))::int;
  passed_start date := today - 7;
  coming_start date := today;
  d date;
  rec record;
  ev record;
  day_html text;
  list_html text;
  item_count int;
  day_count int;
  subject_date date;
BEGIN
  SELECT decrypted_secret INTO api_key FROM vault.decrypted_secrets WHERE name = 'resend_api_key';
  IF api_key IS NULL THEN
    RAISE NOTICE 'No Resend API key found in vault';
    RETURN;
  END IF;

  FOR rec IN
    SELECT p.id AS uid, u.email AS user_email, p.display_name,
           p.notify_weekly_recap_email, p.notify_weekly_recap_inapp, p.weekly_recap_relative, p.recap_excluded_kinds
    FROM profiles p
    JOIN auth.users u ON u.id = p.id
    WHERE (p.notify_weekly_recap_email OR p.notify_weekly_recap_inapp)
      AND p.weekly_recap_day = today_dow
  LOOP
    list_html := '';
    item_count := 0;

    IF rec.weekly_recap_relative = 'passed' OR rec.weekly_recap_relative = 'both' THEN
      IF rec.weekly_recap_relative = 'both' THEN
        list_html := list_html || '<h3 style="margin:0 0 4px;font-size:13px;">Last week</h3>';
      END IF;
      FOR d IN SELECT generate_series(passed_start, passed_start + 6, interval '1 day')::date LOOP
        day_html := '';
        day_count := 0;
        FOR ev IN
          SELECT e.title, e.event_time
          FROM events e
          WHERE (e.user_id = rec.uid OR (shared_circle_cat(rec.uid, e.user_id, 'calendar') AND coalesce(e.is_private, false) = false))
            AND NOT (e.kind = ANY(rec.recap_excluded_kinds))
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
    END IF;

    IF rec.weekly_recap_relative = 'coming' OR rec.weekly_recap_relative = 'both' OR rec.weekly_recap_relative IS NULL THEN
      IF rec.weekly_recap_relative = 'both' THEN
        list_html := list_html || '<h3 style="margin:16px 0 4px;font-size:13px;">This week</h3>';
      END IF;
      FOR d IN SELECT generate_series(coming_start, coming_start + 6, interval '1 day')::date LOOP
        day_html := '';
        day_count := 0;
        FOR ev IN
          SELECT e.title, e.event_time
          FROM events e
          WHERE (e.user_id = rec.uid OR (shared_circle_cat(rec.uid, e.user_id, 'calendar') AND coalesce(e.is_private, false) = false))
            AND NOT (e.kind = ANY(rec.recap_excluded_kinds))
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
    END IF;

    IF item_count = 0 THEN
      CONTINUE;
    END IF;

    subject_date := CASE WHEN rec.weekly_recap_relative = 'passed' THEN passed_start ELSE coming_start END;

    IF rec.notify_weekly_recap_email THEN
      PERFORM net.http_post(
        url := 'https://api.resend.com/emails',
        headers := jsonb_build_object('Authorization', 'Bearer ' || api_key, 'Content-Type', 'application/json'),
        body := jsonb_build_object(
          'from', 'Calendar Reminders <noreply@kristoffergt.com>',
          'to', rec.user_email,
          'subject', 'Your week: ' || to_char(subject_date, 'Mon DD'),
          'html', email_shell(
            'You''re receiving this because Weekly recap is turned on in Notifications settings.',
            '<p style="margin:0 0 14px;">Hi ' || coalesce(rec.display_name, 'there') || ',</p>' ||
            list_html ||
            email_button('Open Productivity Tracker', 'https://kristoffergt.com/?go=calendar&date=' || to_char(subject_date, 'YYYY-MM-DD') || '&view=week')
          )
        )
      );
    END IF;

    IF rec.notify_weekly_recap_inapp THEN
      INSERT INTO notifications(user_id, type, title, body, params)
      VALUES (
        rec.uid, 'weekly_recap',
        'Your week: ' || item_count || ' thing' || (CASE WHEN item_count = 1 THEN '' ELSE 's' END),
        to_char(subject_date, 'YYYY-MM-DD'),
        jsonb_build_object('date', to_char(subject_date, 'YYYY-MM-DD'), 'count', item_count)
      );
    END IF;
  END LOOP;
END;
$$;
