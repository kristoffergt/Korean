-- ============================================================================
-- The "Open Productivity Tracker" / "View on Productivity Tracker" email
-- buttons just linked to the site root -- clicking one always landed on
-- whatever tab you'd last left the app on, not the thing the email was
-- actually about. Both now carry a `?go=...` deep-link query param that
-- index.html reads on boot (handleDeepLinkParam(), called at the end of
-- onAuthed()) and uses to navigate straight there:
--   ?go=yonsei-boards           -> Yonsei > Boards
--   ?go=calendar&date=YYYY-MM-DD -> Calendar, jumped to that date
--
-- Only the email_button(...) call in each function changes; matching/dedupe/
-- window logic is untouched.
-- ============================================================================

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
                email_button('Open Productivity Tracker', 'https://kristoffergt.com/?go=calendar&date=' || to_char(occ, 'YYYY-MM-DD'))
              )
            )
          );

          if wants_in_app_notification(rec.user_id, 'reminder') then
            insert into notifications(user_id, type, title, body, params)
            values (
              rec.user_id, 'reminder', 'Reminder: ' || rec.title, to_char(occ, 'YYYY-MM-DD'),
              jsonb_build_object('event_title', rec.title, 'date', to_char(occ, 'YYYY-MM-DD'))
            );
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
          email_button('View on Productivity Tracker', 'https://kristoffergt.com/?go=yonsei-boards')
        )
      )
    );

    IF wants_in_app_notification(rec.recipient_id, 'yonsei_board') THEN
      INSERT INTO notifications(user_id, type, title, body, params)
      VALUES (
        rec.recipient_id, 'yonsei_board',
        'New Yonsei GSIS notice' || (CASE WHEN jsonb_array_length(my_items) > 1 THEN 's' ELSE '' END),
        (SELECT string_agg(elem->>'title', ', ') FROM jsonb_array_elements(my_items) elem),
        jsonb_build_object('count', jsonb_array_length(my_items))
      );
    END IF;
  END LOOP;
END;
$function$;
