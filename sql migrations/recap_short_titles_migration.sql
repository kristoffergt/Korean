-- The daily recap's in-app notification body was just the raw date (and
-- the client even overrode it with a formatted date regardless, see the
-- renderNotifText() fix for daily_recap in index.html) -- neither told you
-- anything about what was actually on. Now it's a short, comma-joined list
-- of the day's item titles, each shortened to its first word ("Interview:
-- Luxolis Labs" -> "Interview"). Same shortening applied to the weekly
-- recap's per-day title lists, which already listed real titles but at
-- full length.
--
-- Applied live via apply_migration as "recap_short_titles" and
-- "weekly_recap_short_titles" -- this file mirrors that for the record.

create or replace function public.send_daily_recap()
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
DECLARE
  api_key text;
  today date := (now() AT TIME ZONE 'Asia/Seoul')::date;
  today_dow int := extract(dow from (now() AT TIME ZONE 'Asia/Seoul'))::int;
  now_time time := date_trunc('minute', (now() AT TIME ZONE 'Asia/Seoul'))::time;
  target_date date;
  rec record;
  ev record;
  list_html text;
  short_title_list text;
  item_count int;
BEGIN
  SELECT decrypted_secret INTO api_key FROM vault.decrypted_secrets WHERE name = 'resend_api_key';
  IF api_key IS NULL THEN
    RAISE NOTICE 'No Resend API key found in vault';
    RETURN;
  END IF;

  FOR rec IN
    SELECT p.id AS uid, u.email AS user_email, p.display_name,
           p.notify_daily_recap_email, p.notify_daily_recap_inapp, p.daily_recap_relative, p.daily_recap_excluded_kinds,
           p.recap_included_uids
    FROM profiles p
    JOIN auth.users u ON u.id = p.id
    WHERE p.daily_recap_time_of_day = now_time
      AND (p.notify_daily_recap_email OR p.notify_daily_recap_inapp)
      AND today_dow = ANY(p.daily_recap_days)
  LOOP
    target_date := CASE WHEN rec.daily_recap_relative = 'day_before' THEN today + 1 ELSE today END;
    list_html := '';
    short_title_list := '';
    item_count := 0;
    FOR ev IN
      SELECT e.title, e.event_time
      FROM events e
      WHERE (e.user_id = rec.uid OR (
              shared_circle_cat(rec.uid, e.user_id, 'calendar')
              AND coalesce(e.is_private, false) = false
              AND (rec.recap_included_uids IS NULL OR e.user_id = ANY(rec.recap_included_uids))
            ))
        AND NOT (e.kind = ANY(rec.daily_recap_excluded_kinds))
        AND event_occurs_on(e.event_date, e.recur_freq, e.recur_interval, e.recur_end_type, e.recur_end_date, e.excluded_dates, target_date)
      ORDER BY e.event_time NULLS LAST, e.title
    LOOP
      item_count := item_count + 1;
      list_html := list_html || '<li style="margin-bottom:6px;">' ||
        (CASE WHEN ev.event_time IS NOT NULL THEN '<strong>' || to_char(ev.event_time, 'HH12:MI AM') || '</strong> &ndash; ' ELSE '' END) ||
        ev.title || '</li>';
      short_title_list := short_title_list || (CASE WHEN short_title_list <> '' THEN ', ' ELSE '' END) ||
        regexp_replace(split_part(ev.title, ' ', 1), ':$', '');
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
        short_title_list,
        jsonb_build_object('date', to_char(target_date, 'YYYY-MM-DD'), 'count', item_count)
      );
    END IF;
  END LOOP;
END;
$function$;

create or replace function public.send_weekly_recap()
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
DECLARE
  api_key text;
  today date := (now() AT TIME ZONE 'Asia/Seoul')::date;
  today_dow int := extract(dow from (now() AT TIME ZONE 'Asia/Seoul'))::int;
  now_time time := date_trunc('minute', (now() AT TIME ZONE 'Asia/Seoul'))::time;
  passed_start date := today - 7;
  coming_start date := today;
  d date;
  rec record;
  ev record;
  day_html text;
  day_titles_text text;
  list_html text;
  item_count int;
  day_count int;
  passed_text text;
  coming_text text;
  passed_count int;
  coming_count int;
  notif_body text;
  subject_date date;
  intro_line text;
BEGIN
  SELECT decrypted_secret INTO api_key FROM vault.decrypted_secrets WHERE name = 'resend_api_key';
  IF api_key IS NULL THEN
    RAISE NOTICE 'No Resend API key found in vault';
    RETURN;
  END IF;

  FOR rec IN
    SELECT p.id AS uid, u.email AS user_email, p.display_name,
           p.notify_weekly_recap_email, p.notify_weekly_recap_inapp, p.weekly_recap_relative, p.weekly_recap_excluded_kinds,
           p.recap_included_uids
    FROM profiles p
    JOIN auth.users u ON u.id = p.id
    WHERE (p.notify_weekly_recap_email OR p.notify_weekly_recap_inapp)
      AND p.weekly_recap_day = today_dow
      AND p.weekly_recap_time_of_day = now_time
  LOOP
    list_html := '';
    item_count := 0;
    passed_text := '';
    coming_text := '';
    passed_count := 0;
    coming_count := 0;

    IF rec.weekly_recap_relative = 'passed' OR rec.weekly_recap_relative = 'both' THEN
      IF rec.weekly_recap_relative = 'both' THEN
        list_html := list_html || '<h3 style="margin:0 0 6px;font-size:17px;">Last week</h3>';
      END IF;
      FOR d IN SELECT generate_series(passed_start, passed_start + 6, interval '1 day')::date LOOP
        day_html := '';
        day_titles_text := '';
        day_count := 0;
        FOR ev IN
          SELECT e.title, e.event_time
          FROM events e
          WHERE (e.user_id = rec.uid OR (
                  shared_circle_cat(rec.uid, e.user_id, 'calendar')
                  AND coalesce(e.is_private, false) = false
                  AND (rec.recap_included_uids IS NULL OR e.user_id = ANY(rec.recap_included_uids))
                ))
            AND NOT (e.kind = ANY(rec.weekly_recap_excluded_kinds))
            AND event_occurs_on(e.event_date, e.recur_freq, e.recur_interval, e.recur_end_type, e.recur_end_date, e.excluded_dates, d)
          ORDER BY e.event_time NULLS LAST, e.title
        LOOP
          day_count := day_count + 1;
          item_count := item_count + 1;
          passed_count := passed_count + 1;
          day_html := day_html || '<li style="margin-bottom:4px;">' ||
            (CASE WHEN ev.event_time IS NOT NULL THEN '<strong>' || to_char(ev.event_time, 'HH12:MI AM') || '</strong> &ndash; ' ELSE '' END) ||
            ev.title || '</li>';
          day_titles_text := day_titles_text || (CASE WHEN day_titles_text <> '' THEN ', ' ELSE '' END) ||
            regexp_replace(split_part(ev.title, ' ', 1), ':$', '');
        END LOOP;
        IF day_count > 0 THEN
          list_html := list_html || '<p style="margin:12px 0 4px;font-weight:700;font-size:13px;color:#4B4B4B;">' || to_char(d, 'Dy, Mon DD') || '</p><ul style="margin:0 0 4px;padding-left:20px;">' || day_html || '</ul>';
          passed_text := passed_text || to_char(d, 'Dy') || ': ' || day_titles_text || E'\n';
        END IF;
      END LOOP;
    END IF;

    IF rec.weekly_recap_relative = 'coming' OR rec.weekly_recap_relative = 'both' OR rec.weekly_recap_relative IS NULL THEN
      IF rec.weekly_recap_relative = 'both' THEN
        list_html := list_html || '<h3 style="margin:18px 0 6px;font-size:17px;">This week</h3>';
      END IF;
      FOR d IN SELECT generate_series(coming_start, coming_start + 6, interval '1 day')::date LOOP
        day_html := '';
        day_titles_text := '';
        day_count := 0;
        FOR ev IN
          SELECT e.title, e.event_time
          FROM events e
          WHERE (e.user_id = rec.uid OR (
                  shared_circle_cat(rec.uid, e.user_id, 'calendar')
                  AND coalesce(e.is_private, false) = false
                  AND (rec.recap_included_uids IS NULL OR e.user_id = ANY(rec.recap_included_uids))
                ))
            AND NOT (e.kind = ANY(rec.weekly_recap_excluded_kinds))
            AND event_occurs_on(e.event_date, e.recur_freq, e.recur_interval, e.recur_end_type, e.recur_end_date, e.excluded_dates, d)
          ORDER BY e.event_time NULLS LAST, e.title
        LOOP
          day_count := day_count + 1;
          item_count := item_count + 1;
          coming_count := coming_count + 1;
          day_html := day_html || '<li style="margin-bottom:4px;">' ||
            (CASE WHEN ev.event_time IS NOT NULL THEN '<strong>' || to_char(ev.event_time, 'HH12:MI AM') || '</strong> &ndash; ' ELSE '' END) ||
            ev.title || '</li>';
          day_titles_text := day_titles_text || (CASE WHEN day_titles_text <> '' THEN ', ' ELSE '' END) ||
            regexp_replace(split_part(ev.title, ' ', 1), ':$', '');
        END LOOP;
        IF day_count > 0 THEN
          list_html := list_html || '<p style="margin:12px 0 4px;font-weight:700;font-size:13px;color:#4B4B4B;">' || to_char(d, 'Dy, Mon DD') || '</p><ul style="margin:0 0 4px;padding-left:20px;">' || day_html || '</ul>';
          coming_text := coming_text || to_char(d, 'Dy') || ': ' || day_titles_text || E'\n';
        END IF;
      END LOOP;
    END IF;

    IF item_count = 0 THEN
      CONTINUE;
    END IF;

    subject_date := CASE WHEN rec.weekly_recap_relative = 'passed' THEN passed_start ELSE coming_start END;

    intro_line := CASE rec.weekly_recap_relative
      WHEN 'passed' THEN 'Here''s a breakdown of what you were up to and what happened this past week.'
      WHEN 'both' THEN 'Here''s a breakdown of what happened this past week, and how your week ahead is looking.'
      ELSE 'Here''s a breakdown of how your week ahead is looking.'
    END;

    IF rec.weekly_recap_relative = 'both' THEN
      notif_body := passed_count || ' thing' || (CASE WHEN passed_count = 1 THEN '' ELSE 's' END) || ' last week:' || E'\n' ||
        rtrim(passed_text, E'\n') || E'\n\n' ||
        coming_count || ' thing' || (CASE WHEN coming_count = 1 THEN '' ELSE 's' END) || ' next week:' || E'\n' ||
        rtrim(coming_text, E'\n');
    ELSIF rec.weekly_recap_relative = 'passed' THEN
      notif_body := rtrim(passed_text, E'\n');
    ELSE
      notif_body := rtrim(coming_text, E'\n');
    END IF;

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
            '<p style="margin:0 0 14px;">' || intro_line || '</p>' ||
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
        notif_body,
        jsonb_build_object('date', to_char(subject_date, 'YYYY-MM-DD'), 'count', item_count)
      );
    END IF;
  END LOOP;
END;
$function$;
