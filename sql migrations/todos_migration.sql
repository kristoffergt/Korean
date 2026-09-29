-- ============================================================================
-- A to-do list, as a sub tab of the school/work tab (real-user request,
-- 29 Sep: "a fully functional To-do List sub-tab"). His answers: private
-- unless its owner chooses to share it with their circle; its owner decides
-- whether due to-dos show on the calendar; reminders picked per to-do,
-- easily.
--
-- todos            one row per to-do. reminders is a jsonb list of
--                  {"p": preset, "at": ISO timestamp}, the moment worked out
--                  in the owner's own browser (their timezone), so the server
--                  never has to know where anybody is. A preset is how the
--                  page re-works the moment when the due date moves.
-- todo_reminder_log one row per reminder that has gone out, keyed on the
--                  to-do and the moment: a moved due date is a new moment and
--                  reminds again, the same one never twice.
-- profiles.share_todos       false = nobody but the owner sees them (default)
-- profiles.todos_on_calendar true  = open, dated to-dos appear on the calendar
--
-- send_todo_reminders() runs every 5 minutes: the bell (and so the phone,
-- through the push trigger on notifications) and email, each through the
-- same per-type switches every other notification uses, type 'todo_reminder'.
-- A reminder more than a day late is not sent at all.
--
-- Safe to re-run.
-- ============================================================================

-- A reminder list the server can read without throwing: at most 10, each an
-- object with a parseable "at". A bad row would otherwise abort every run of
-- the job for everybody.
create or replace function public.todo_reminders_ok(r jsonb)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
declare
  e jsonb;
  ts timestamptz;
begin
  if r is null or jsonb_typeof(r) <> 'array' or jsonb_array_length(r) > 10 then
    return false;
  end if;
  for e in select * from jsonb_array_elements(r) loop
    if jsonb_typeof(e) <> 'object' or e->>'at' is null then
      return false;
    end if;
    ts := (e->>'at')::timestamptz;
  end loop;
  return true;
exception when others then
  return false;
end;
$$;

create table if not exists public.todos (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  title text not null check (char_length(btrim(title)) between 1 and 200),
  notes text check (notes is null or char_length(notes) <= 2000),
  due_date date,
  due_time time,
  course_id uuid references public.courses(id) on delete set null,
  reminders jsonb not null default '[]'::jsonb check (public.todo_reminders_ok(reminders)),
  done boolean not null default false,
  done_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists todos_user_idx on public.todos (user_id);

alter table public.profiles add column if not exists share_todos boolean not null default false;
alter table public.profiles add column if not exists todos_on_calendar boolean not null default true;

alter table public.todos enable row level security;
drop policy if exists todos_select on public.todos;
drop policy if exists todos_insert on public.todos;
drop policy if exists todos_update on public.todos;
drop policy if exists todos_delete on public.todos;
-- Read: your own, or a circle member's who has chosen to share theirs.
create policy todos_select on public.todos for select to authenticated
  using (
    user_id = auth.uid()
    or (
      public.shared_circle(auth.uid(), user_id)
      and exists (select 1 from public.profiles p where p.id = todos.user_id and p.share_todos)
    )
  );
create policy todos_insert on public.todos for insert to authenticated
  with check (user_id = auth.uid());
create policy todos_update on public.todos for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy todos_delete on public.todos for delete to authenticated
  using (user_id = auth.uid());
revoke all on public.todos from anon;
grant select, insert, update, delete on public.todos to authenticated;

create table if not exists public.todo_reminder_log (
  todo_id uuid not null references public.todos(id) on delete cascade,
  remind_at timestamptz not null,
  sent_at timestamptz not null default now(),
  primary key (todo_id, remind_at)
);
alter table public.todo_reminder_log enable row level security; -- no policies: server only
revoke all on public.todo_reminder_log from anon, authenticated;

-- Live updates for the circle, like every other shared table.
do $$
begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'todos') then
    alter publication supabase_realtime add table public.todos;
  end if;
end $$;

create or replace function public.send_todo_reminders()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  api_key text;
  rec record;
  due_text text;
begin
  select decrypted_secret into api_key from vault.decrypted_secrets where name = 'resend_api_key';

  for rec in
    select t.id, t.user_id, t.title, t.due_date, t.due_time,
           (r->>'at')::timestamptz as at_ts,
           u.email as user_email, p.display_name
    from todos t
    cross join lateral jsonb_array_elements(t.reminders) r
    join auth.users u on u.id = t.user_id
    left join profiles p on p.id = t.user_id
    where not t.done
      and (r->>'at')::timestamptz <= now()
      and (r->>'at')::timestamptz > now() - interval '1 day'
  loop
    insert into todo_reminder_log (todo_id, remind_at) values (rec.id, rec.at_ts)
      on conflict do nothing;
    if not found then
      continue;
    end if;

    due_text := case
      when rec.due_date is null then ''
      when rec.due_time is null then to_char(rec.due_date, 'YYYY-MM-DD')
      else to_char(rec.due_date, 'YYYY-MM-DD') || ' ' || to_char(rec.due_time, 'HH24:MI')
    end;

    if wants_in_app_notification(rec.user_id, 'todo_reminder') then
      insert into notifications (user_id, type, title, body, params)
      values (
        rec.user_id, 'todo_reminder', 'To-do: ' || rec.title, due_text,
        jsonb_build_object(
          'todo_title', rec.title,
          'todo_id', rec.id,
          'date', to_char(rec.due_date, 'YYYY-MM-DD'),
          'time', to_char(rec.due_time, 'HH24:MI')
        )
      );
    end if;

    if api_key is not null and rec.user_email is not null
       and wants_email_notification(rec.user_id, 'todo_reminder') then
      perform net.http_post(
        url := 'https://api.resend.com/emails',
        headers := jsonb_build_object('Authorization', 'Bearer ' || api_key, 'Content-Type', 'application/json'),
        body := jsonb_build_object(
          'from', 'To-do Reminders <noreply@kristoffergt.com>',
          'to', rec.user_email,
          'headers', email_unsubscribe_headers(rec.user_id, 'todo_reminder'),
          'subject', 'To-do: ' || rec.title,
          'html', email_shell(
            'You''re receiving this because you set a reminder on this to-do.' || email_unsubscribe_footer(rec.user_id, 'todo_reminder'),
            '<p style="margin:0 0 14px;">Hi ' || html_escape(coalesce(rec.display_name, 'there')) || ',</p>' ||
            '<p style="margin:0;">A reminder for &ldquo;<strong>' || html_escape(rec.title) || '</strong>&rdquo;' ||
            case when due_text <> '' then ', due ' || due_text else '' end || '.</p>' ||
            email_button('Open your to-dos', 'https://kristoffergt.com/?go=todos')
          )
        )
      );
    end if;
  end loop;
end;
$$;
revoke all on function public.send_todo_reminders() from public, anon, authenticated;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'send-todo-reminders') then
    perform cron.unschedule('send-todo-reminders');
  end if;
end $$;
select cron.schedule('send-todo-reminders', '*/5 * * * *', 'select public.send_todo_reminders();');

-- The one-click unsubscribe in a to-do reminder email turns off to-do
-- reminder emails, like every other kind's.
create or replace function public.unsubscribe_email(p_uid uuid, p_kind text, p_token text)
returns boolean
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_expected text;
begin
  if p_uid is null or p_kind is null or p_token is null then
    return false;
  end if;
  if p_kind not in ('daily_recap', 'weekly_recap', 'reminder', 'yonsei_board', 'todo_reminder') then
    return false;
  end if;
  v_expected := public.email_unsubscribe_token(p_uid, p_kind);
  if v_expected is null or v_expected <> lower(p_token) then
    return false;
  end if;
  if not exists (select 1 from auth.users where id = p_uid) then
    return false;
  end if;

  if p_kind = 'daily_recap' then
    update public.profiles set notify_daily_recap_email = false where id = p_uid;
  elsif p_kind = 'weekly_recap' then
    update public.profiles set notify_weekly_recap_email = false where id = p_uid;
  else
    insert into public.notification_prefs (user_id, type, email)
    values (p_uid, p_kind, false)
    on conflict (user_id, type) do update set email = false;
  end if;
  return true;
end;
$$;

-- Deleting an account takes its to-dos (the foreign key would too, once
-- auth.users goes; said here so the list of what goes is in one place).
create or replace function public._purge_user_data(target_user_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
DECLARE
  v_uid uuid := target_user_id;
  v_email text;
BEGIN
  IF v_uid IS NULL THEN
    RETURN;
  END IF;
  SELECT email INTO v_email FROM auth.users WHERE id = v_uid;
  DELETE FROM study_entries WHERE user_id = v_uid;
  DELETE FROM books WHERE user_id = v_uid;
  DELETE FROM job_applications WHERE user_id = v_uid;
  DELETE FROM grammar_notes WHERE user_id = v_uid;
  DELETE FROM grammar_favorites WHERE user_id = v_uid;
  DELETE FROM grammar_review_overrides WHERE user_id = v_uid;
  DELETE FROM grammar_srs WHERE user_id = v_uid;
  DELETE FROM quiz_attempts WHERE user_id = v_uid;
  DELETE FROM course_notes WHERE user_id = v_uid;
  DELETE FROM notebook_notes WHERE user_id = v_uid;
  DELETE FROM writing_samples WHERE user_id = v_uid;
  DELETE FROM event_subscriptions WHERE user_id = v_uid;
  DELETE FROM events WHERE user_id = v_uid;
  DELETE FROM todos WHERE user_id = v_uid;
  DELETE FROM courses WHERE user_id = v_uid;
  DELETE FROM link_sharing_settings l WHERE l.user_id = v_uid OR l.target_user_id = v_uid;
  DELETE FROM link_group_members m WHERE m.user_id = v_uid;
  UPDATE course_notes SET updated_by = NULL WHERE updated_by = v_uid;
  UPDATE notebook_notes SET updated_by = NULL WHERE updated_by = v_uid;
  UPDATE writing_samples SET updated_by = NULL WHERE updated_by = v_uid;
  UPDATE grammar_points SET updated_by = NULL WHERE updated_by = v_uid;
  IF v_email IS NOT NULL THEN
    DELETE FROM pending_signup_names WHERE lower(email) = lower(v_email);
  END IF;
  DELETE FROM profiles WHERE id = v_uid;
  DELETE FROM auth.users WHERE id = v_uid;
END;
$$;
