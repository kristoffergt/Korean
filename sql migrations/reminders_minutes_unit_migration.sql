-- send_due_reminders() only ever understood 'hours' and 'days' on a
-- reminder's unit field (see reminderSelectToOffset's own comment in
-- index.html), treating anything else as days. The Add Event reminder
-- picker gained an exact minutes/hours/days picker, so the function needs
-- an actual 'minutes' branch rather than having it silently misfire as a
-- multi-day wait.
--
-- Precision note, not something this migration can fix: send_due_reminders
-- runs on a pg_cron schedule of */30 * * * * with a 35-minute lookback
-- window inside the function. A "15 minutes before" reminder is real and
-- will fire, but only as precisely as the cron cadence allows -- up to
-- ~30 minutes late in the worst case. Tightening that means changing the
-- cron job itself, not this function.

create or replace function public.send_due_reminders()
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
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
      (occ::timestamp + coalesce(rec.event_time, '08:00:00'::time))
      - interval '9 hours';

    for reminder in
      select * from jsonb_array_elements(rec.reminders)
    loop
      if (reminder->>'unit') = 'minutes' then
        target_ts :=
          occ_ts - ((reminder->>'value')::int || ' minutes')::interval;
      elsif (reminder->>'unit') = 'hours' then
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
$function$;
