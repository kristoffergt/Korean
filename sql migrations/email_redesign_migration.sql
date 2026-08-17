-- ============================================================================
-- Redesigns every transactional email this app sends (welcome, admin
-- new-signup ping, calendar reminders, Yonsei board notices) around a
-- shared branded shell -- structurally modeled on Welcome Korea's email
-- templates (header bar / centered white card / muted footer disclaimer),
-- but in THIS app's own visual identity, not copied colors: Noto Serif KR
-- header, Inter body, ink-black text (#1E1F22), celadon-4 (#4F7563) as the
-- one accent/CTA color, matching :root's palette in index.html.
--
-- email_shell(preheader, body_html) is a small SQL helper the 4 email call
-- sites below all wrap their content with, instead of quadruplicating the
-- wrapper markup by hand in each function (the pattern this app already
-- avoids duplicating whole page code for -- see the fetch-yonsei-board /
-- notify-yonsei-board parse.ts comment on why THAT particular duplication
-- was unavoidable; a plain SQL function has no such constraint).
--
-- Safe to re-run.
-- ============================================================================

CREATE OR REPLACE FUNCTION email_shell(preheader text, body_html text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT
    '<div style="background:#F5F5F6;padding:32px 16px;font-family:-apple-system,BlinkMacSystemFont,''Inter'',Helvetica,Arial,sans-serif;">' ||
      '<div style="max-width:480px;margin:0 auto;background:#ffffff;border:1px solid rgba(30,31,34,0.12);border-radius:12px;overflow:hidden;">' ||
        '<div style="background:#1E1F22;padding:20px 28px;">' ||
          '<span style="font-family:Georgia,''Noto Serif KR'',serif;font-size:18px;font-weight:700;color:#F5F5F6;letter-spacing:0.2px;">Productivity Tracker</span>' ||
        '</div>' ||
        '<div style="padding:28px;font-size:15px;line-height:1.65;color:#1E1F22;">' || body_html || '</div>' ||
        '<div style="padding:16px 28px;border-top:1px solid rgba(30,31,34,0.08);">' ||
          '<p style="margin:0;font-size:11.5px;line-height:1.5;color:#6B6D72;">' || preheader || '</p>' ||
        '</div>' ||
      '</div>' ||
    '</div>';
$$;
REVOKE EXECUTE ON FUNCTION email_shell(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION email_shell(text, text) TO authenticated, service_role;

-- Shared CTA button markup, since three of the four emails end with one.
CREATE OR REPLACE FUNCTION email_button(label text, url text DEFAULT 'https://kristoffergt.com')
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT '<div style="margin-top:20px;"><a href="' || url || '" style="display:inline-block;background:#4F7563;color:#ffffff;text-decoration:none;padding:11px 22px;border-radius:6px;font-size:14px;font-weight:600;">' || label || '</a></div>';
$$;
REVOKE EXECUTE ON FUNCTION email_button(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION email_button(text, text) TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- send_welcome_email() -- both the user-facing welcome email and the
-- admin new-signup ping now go through the shell (the admin one gets no CTA
-- button, it's an internal notice, not something to act on).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION send_welcome_email()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
declare
  api_key text;
  user_email text;
begin
  select decrypted_secret into api_key from vault.decrypted_secrets where name = 'resend_api_key';
  select email into user_email from auth.users where id = new.id;
  if api_key is not null and user_email is not null then
    perform net.http_post(
      url := 'https://api.resend.com/emails',
      headers := jsonb_build_object('Authorization','Bearer '||api_key,'Content-Type','application/json'),
      body := jsonb_build_object(
        'from','Productivity Tracker <noreply@reminders.kristoffergt.com>',
        'to', user_email,
        'subject','Welcome to Productivity Tracker',
        'html', email_shell(
          'You''re receiving this because you just created an account at kristoffergt.com.',
          '<p style="margin:0 0 14px;">Hi ' || new.display_name || ',</p>' ||
          '<p style="margin:0 0 14px;">Your account is ready. Sign in anytime with your email (or display name) and the password you chose.</p>' ||
          '<p style="margin:0;color:#6B6D72;font-size:13.5px;">Forgot your password? Use &ldquo;Forgot password?&rdquo; on the sign-in screen to reset it anytime.</p>' ||
          email_button('Open Productivity Tracker')
        )
      )
    );
    perform net.http_post(
      url := 'https://api.resend.com/emails',
      headers := jsonb_build_object('Authorization','Bearer '||api_key,'Content-Type','application/json'),
      body := jsonb_build_object(
        'from','Productivity Tracker <noreply@reminders.kristoffergt.com>',
        'to','kristoffergt@gmail.com',
        'subject','New signup: '||new.display_name,
        'html', email_shell(
          'Internal notification -- new account created.',
          '<p style="margin:0 0 6px;">New account created.</p>' ||
          '<p style="margin:0;color:#6B6D72;">Name: ' || new.display_name || '<br>Email: ' || user_email || '</p>'
        )
      )
    );
  end if;
  return new;
end;
$function$;

-- ---------------------------------------------------------------------------
-- send_due_reminders() -- only the 'html' body changes; the dedupe/window/
-- matching logic is untouched.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION send_due_reminders()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
declare
  api_key text;
  rec record;
  occ date;
  occ_ts timestamptz;
  target_ts timestamptz;
  window_start timestamptz := now() - interval '35 minutes';
  window_end timestamptz := now();
  reminder jsonb;
begin
  select decrypted_secret
    into api_key
  from vault.decrypted_secrets
  where name = 'resend_api_key';

  if api_key is null then
    raise notice 'No Resend API key found in vault';
    return;
  end if;

  for rec in
    select
      es.id as sub_id,
      es.user_id,
      es.reminders,
      ev.title,
      ev.event_date,
      ev.event_time,
      ev.recur_freq,
      ev.recur_interval,
      ev.recur_end_type,
      ev.recur_end_date,
      u.email as user_email,
      p.display_name
    from event_subscriptions es
    join events ev on ev.id = es.event_id
    join auth.users u on u.id = es.user_id
    left join public.profiles p on p.id = es.user_id
  loop
    occ := next_occurrence(
      rec.event_date,
      rec.recur_freq,
      coalesce(rec.recur_interval, 1),
      rec.recur_end_type,
      rec.recur_end_date
    );

    if occ is null then
      continue;
    end if;

    occ_ts :=
      (occ::timestamp + coalesce(rec.event_time, '09:00:00'::time))
      - interval '9 hours';

    for reminder in
      select * from jsonb_array_elements(rec.reminders)
    loop
      if (reminder->>'unit') = 'hours' then
        target_ts :=
          occ_ts - ((reminder->>'value')::int || ' hours')::interval;
      else
        target_ts :=
          occ_ts - ((reminder->>'value')::int || ' days')::interval;
      end if;

      if target_ts > window_start
         and target_ts <= window_end then

        if not exists (
          select 1
          from reminder_log
          where subscription_id = rec.sub_id
            and occurrence_date = occ
            and reminder_value = (reminder->>'value')::int
            and reminder_unit = (reminder->>'unit')
        ) then

          perform net.http_post(
            url := 'https://api.resend.com/emails',
            headers := jsonb_build_object(
              'Authorization', 'Bearer ' || api_key,
              'Content-Type', 'application/json'
            ),
            body := jsonb_build_object(
              'from', 'Calendar Reminders <noreply@kristoffergt.com>',
              'to', rec.user_email,
              'subject', 'Reminder: ' || rec.title,
              'html', email_shell(
                'You''re receiving this because you subscribed to a reminder for this event. Manage reminders from the event in your calendar.',
                '<p style="margin:0 0 14px;">Hi ' || coalesce(rec.display_name, 'there') || ',</p>' ||
                '<p style="margin:0;">Here''s a reminder for &ldquo;<strong>' || rec.title || '</strong>&rdquo; on ' ||
                to_char(occ, 'YYYY-MM-DD') ||
                case
                  when rec.event_time is not null
                  then ' at ' || to_char(rec.event_time, 'HH12:MI AM') || ' KST'
                  else ''
                end ||
                '.</p>' ||
                email_button('Open Productivity Tracker')
              )
            )
          );

          if wants_in_app_notification(rec.user_id, 'reminder') then
            insert into notifications(user_id, type, title, body)
            values (rec.user_id, 'reminder', 'Reminder: ' || rec.title, to_char(occ, 'YYYY-MM-DD'));
          end if;

          insert into reminder_log (
            subscription_id,
            occurrence_date,
            reminder_value,
            reminder_unit
          )
          values (
            rec.sub_id,
            occ,
            (reminder->>'value')::int,
            reminder->>'unit'
          );

        end if;
      end if;
    end loop;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- notify_yonsei_board_new_items() -- only the 'html' body changes.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION notify_yonsei_board_new_items(items jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  api_key text;
  item jsonb;
  v_article_no text;
  new_items jsonb := '[]'::jsonb;
  rec record;
  my_items jsonb;
  list_html text;
  recipient_id uuid;
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

  FOR rec IN
    SELECT p.id AS recipient_id, u.email AS user_email, p.display_name, p.notify_yonsei_categories, p.yonsei_hidden_subtags
    FROM profiles p
    JOIN auth.users u ON u.id = p.id
    WHERE p.notify_yonsei_board = true
  LOOP
    SELECT jsonb_agg(elem) INTO my_items
    FROM jsonb_array_elements(new_items) elem
    WHERE NOT (coalesce(elem->>'subTag', '') = ANY(rec.yonsei_hidden_subtags))
      AND (rec.notify_yonsei_categories IS NULL OR (elem->>'category') = ANY(rec.notify_yonsei_categories));

    IF my_items IS NULL OR jsonb_array_length(my_items) = 0 THEN
      CONTINUE;
    END IF;

    list_html := (
      SELECT string_agg(
        '<li style="margin-bottom:6px;"><a href="' || (elem->>'link') || '" style="color:#4F7563;">' || (elem->>'title') || '</a> <span style="color:#6B6D72;font-size:13px;">(' || (elem->>'date') || ')</span></li>',
        ''
      )
      FROM jsonb_array_elements(my_items) elem
    );

    PERFORM net.http_post(
      url := 'https://api.resend.com/emails',
      headers := jsonb_build_object(
        'Authorization', 'Bearer ' || api_key,
        'Content-Type', 'application/json'
      ),
      body := jsonb_build_object(
        'from', 'Yonsei Notices <noreply@kristoffergt.com>',
        'to', rec.user_email,
        'subject', 'New Yonsei GSIS notice' || (CASE WHEN jsonb_array_length(my_items) > 1 THEN 's' ELSE '' END),
        'html', email_shell(
          'You''re receiving this because notifications are turned on for the Yonsei Official Notices board. Change this anytime in the Yonsei Boards tab.',
          '<p style="margin:0 0 14px;">Hi ' || coalesce(rec.display_name, 'there') || ',</p>' ||
          '<p style="margin:0 0 10px;">New on the Yonsei GSIS Official Notices board:</p>' ||
          '<ul style="margin:0 0 4px;padding-left:20px;">' || list_html || '</ul>' ||
          email_button('View on Productivity Tracker')
        )
      )
    );

    IF wants_in_app_notification(rec.recipient_id, 'yonsei_board') THEN
      INSERT INTO notifications(user_id, type, title, body)
      VALUES (
        rec.recipient_id, 'yonsei_board',
        'New Yonsei GSIS notice' || (CASE WHEN jsonb_array_length(my_items) > 1 THEN 's' ELSE '' END),
        (SELECT string_agg(elem->>'title', ', ') FROM jsonb_array_elements(my_items) elem)
      );
    END IF;
  END LOOP;
END;
$function$;
