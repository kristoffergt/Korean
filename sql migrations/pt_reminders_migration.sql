-- Reminders written to the app itself (real-user request: "Enable sending
-- messages to 'productivity tracker' app. Whenever you do it processes as if
-- you want to be reminded of something, so you just write a time and
-- (optionally) date and it automatically processes it, reminding you next time
-- that time comes around with a notification in the app").
--
-- The time is read on the device, which knows the clock its owner is on, and
-- arrives here as an instant. A row is the message as written (body), what is
-- left once the when is taken out of it (label, the notification's title, or
-- null when the message was nothing but a time), and when to say it.
--
-- sent_at and canceled_at are written only by functions: the table has no
-- UPDATE policy, so nobody can mark a reminder sent without it being sent.
-- send_pt_reminders() runs every minute and puts a 'pt_reminder' row in
-- notifications, which the existing trigger turns into a push.

create table if not exists pt_reminders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 1000),
  label text check (label is null or char_length(label) between 1 and 1000),
  remind_at timestamptz not null,
  created_at timestamptz not null default now(),
  sent_at timestamptz,
  canceled_at timestamptz
);

create index if not exists pt_reminders_user_idx on pt_reminders(user_id, created_at desc);
create index if not exists pt_reminders_due_idx on pt_reminders(remind_at)
  where sent_at is null and canceled_at is null;

alter table pt_reminders enable row level security;

drop policy if exists "pt_reminders_select" on pt_reminders;
create policy "pt_reminders_select" on pt_reminders for select to authenticated
  using (user_id = auth.uid());

-- A new reminder is one nobody has been told about yet, for a moment that has
-- not gone (a few minutes' grace for a clock running slow) and is not absurdly
-- far off.
drop policy if exists "pt_reminders_insert" on pt_reminders;
create policy "pt_reminders_insert" on pt_reminders for insert to authenticated
  with check (
    user_id = auth.uid()
    and sent_at is null and canceled_at is null
    and remind_at > now() - interval '5 minutes'
    and remind_at < now() + interval '2 years'
  );

drop policy if exists "pt_reminders_delete" on pt_reminders;
create policy "pt_reminders_delete" on pt_reminders for delete to authenticated
  using (user_id = auth.uid());

revoke all on pt_reminders from anon;
grant select, insert, delete on pt_reminders to authenticated;

do $$
begin
  if not exists (select 1 from pg_publication_tables
                  where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'pt_reminders') then
    alter publication supabase_realtime add table pt_reminders;
  end if;
end $$;

-- Cancelling keeps the row, so the conversation still shows what was asked
-- and that it was called off. Only a reminder still waiting can be.
create or replace function cancel_pt_reminder(p_id uuid)
returns timestamptz
language plpgsql
security definer
set search_path = public
as $$
declare
  stamp timestamptz := now();
begin
  if auth.uid() is null then raise exception 'not signed in' using errcode = '42501'; end if;
  update pt_reminders set canceled_at = stamp
   where id = p_id and user_id = auth.uid() and sent_at is null and canceled_at is null;
  if not found then raise exception 'not pending' using errcode = 'P0002'; end if;
  return stamp;
end;
$$;
revoke all on function cancel_pt_reminder(uuid) from public, anon;
grant execute on function cancel_pt_reminder(uuid) to authenticated;

-- Marked sent BEFORE the notification is written, in one statement, so two
-- runs overlapping cannot send one twice. One that is more than a day late
-- (the job was down) is marked and not announced: being told at noon about a
-- 7am alarm from yesterday helps nobody.
create or replace function send_pt_reminders()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  rec record;
begin
  for rec in
    update pt_reminders set sent_at = now()
     where sent_at is null and canceled_at is null and remind_at <= now()
    returning id, user_id, body, label, remind_at
  loop
    continue when rec.remind_at < now() - interval '1 day';
    continue when not wants_in_app_notification(rec.user_id, 'pt_reminder');
    insert into notifications (user_id, type, title, body, params)
    values (rec.user_id, 'pt_reminder', coalesce(rec.label, rec.body), 'Reminder',
            jsonb_build_object('text', rec.label, 'reminder_id', rec.id, 'at', rec.remind_at));
  end loop;
end;
$$;
revoke all on function send_pt_reminders() from public, anon, authenticated;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'send-pt-reminders') then
    perform cron.unschedule('send-pt-reminders');
  end if;
  perform cron.schedule('send-pt-reminders', '* * * * *', 'select public.send_pt_reminders();');
end $$;
