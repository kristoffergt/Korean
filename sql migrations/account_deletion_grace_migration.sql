-- ============================================================================
-- Deleting an account keeps it for 30 days first (real-user request, 29 Sep:
-- "remove the need for email/password for delete, but save the account for
-- 30 days ... in case it is done maliciously, accidentally, or if it was
-- regretted").
--
-- profiles.deletion_scheduled_at   null = a live account; set = the moment
--                                  deletion was asked for. The account is
--                                  deleted for good 30 days after it.
--
-- While it is set the account is as good as gone to everybody else: hidden
-- from the circle (shared_circle, shared_circle_cat, so every RLS policy that
-- reads through them), off every leaderboard, and sent nothing (the three
-- wants_* helpers every sender asks, and the two recaps, which pick their
-- recipients from profiles directly). Its owner is emailed the date, and
-- signing in before it offers to restore the account exactly as it was.
--
-- request_account_deletion()   sets it (never moves it once set) and emails
-- cancel_account_deletion()    clears it
-- purge_scheduled_account_deletions()  hourly: deletes what has waited 30 days
--
-- Only those two functions can change the column: a trigger puts back any
-- other write, so nobody holding a session can backdate it and skip the 30
-- days. For the same reason the immediate delete_own_account() is taken away
-- from users, in part 2 (see below).
--
-- Safe to re-run.
-- ============================================================================

alter table public.profiles add column if not exists deletion_scheduled_at timestamptz;
create index if not exists profiles_deletion_scheduled_idx on public.profiles (deletion_scheduled_at) where deletion_scheduled_at is not null;

create or replace function public.guard_deletion_scheduled_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if coalesce(current_setting('pt.account_deletion', true), '') = '1' then
    return new;
  end if;
  if tg_op = 'INSERT' then
    new.deletion_scheduled_at := null;
  elsif new.deletion_scheduled_at is distinct from old.deletion_scheduled_at then
    new.deletion_scheduled_at := old.deletion_scheduled_at;
  end if;
  return new;
end;
$$;
drop trigger if exists profiles_guard_deletion_scheduled_at on public.profiles;
create trigger profiles_guard_deletion_scheduled_at
  before insert or update on public.profiles
  for each row execute function public.guard_deletion_scheduled_at();

create or replace function public.account_pending_deletion(uid uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select p.deletion_scheduled_at is not null from profiles p where p.id = uid), false);
$$;
revoke all on function public.account_pending_deletion(uuid) from public, anon, authenticated;

-- ---- The email to the owner: the date, and how to undo it -------------------
create or replace function public.send_account_deletion_email(target_user_id uuid, delete_on timestamptz)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  api_key text;
  user_email text;
  loc text;
  nm text;
  d date := (delete_on at time zone 'Asia/Seoul')::date;
  date_text text;
  subject text;
  title text;
  intro text;
  restore text;
  meanwhile text;
  button_label text;
  footer text;
  body_html text;
begin
  select decrypted_secret into api_key from vault.decrypted_secrets where name = 'resend_api_key';
  select u.email,
         case when u.raw_user_meta_data->>'locale' in ('ko', 'vi') then u.raw_user_meta_data->>'locale' else 'en' end
    into user_email, loc
    from auth.users u where u.id = target_user_id;
  if api_key is null or user_email is null then
    return;
  end if;
  select html_escape(coalesce(p.display_name, '')) into nm from profiles p where p.id = target_user_id;
  nm := coalesce(nm, '');

  if loc = 'ko' then
    date_text := to_char(d, 'YYYY"년" FMMM"월" FMDD"일"');
    subject := 'Productivity Tracker 계정이 삭제될 예정입니다';
    title := '계정 삭제가 예약되었습니다';
    intro := nm || '님, Productivity Tracker 계정과 모든 데이터가 <strong>' || date_text || '</strong>에 완전히 삭제됩니다.';
    restore := '마음이 바뀌었거나 본인이 요청하지 않았다면, 그 전에 로그인해서 &ldquo;계정 복구&rdquo;를 누르세요. 모든 내용이 그대로 돌아옵니다.';
    meanwhile := '그때까지 계정은 다른 사람에게 보이지 않으며, 다른 이메일도 보내지 않습니다.';
    button_label := 'Productivity Tracker 열기';
    footer := 'Productivity Tracker · kristoffergt.com · 이 메일은 자동으로 발송되었으며 직접 회신하지 마세요.';
  elsif loc = 'vi' then
    date_text := 'ngày ' || to_char(d, 'FMDD') || ' tháng ' || to_char(d, 'FMMM') || ' năm ' || to_char(d, 'YYYY');
    subject := 'Tài khoản Productivity Tracker của bạn sẽ bị xóa';
    title := 'Tài khoản của bạn đã được lên lịch xóa';
    intro := 'Xin chào ' || nm || ', tài khoản Productivity Tracker của bạn và mọi dữ liệu trong đó sẽ bị xóa vĩnh viễn vào <strong>' || date_text || '</strong>.';
    restore := 'Bạn đổi ý, hoặc không phải bạn yêu cầu? Hãy đăng nhập trước ngày đó và chọn &ldquo;Khôi phục tài khoản&rdquo;. Mọi thứ sẽ giữ nguyên như cũ.';
    meanwhile := 'Trong thời gian đó, tài khoản của bạn bị ẩn với người khác và sẽ không gửi thêm email nào khác.';
    button_label := 'Mở Productivity Tracker';
    footer := 'Productivity Tracker · kristoffergt.com · Đây là email tự động, vui lòng không trả lời trực tiếp.';
  else
    date_text := to_char(d, 'FMDD FMMonth YYYY');
    subject := 'Your Productivity Tracker account will be deleted';
    title := 'Your account is scheduled for deletion';
    intro := 'Hi ' || nm || ', your Productivity Tracker account and everything in it will be deleted for good on <strong>' || date_text || '</strong>.';
    restore := 'Changed your mind, or was this not you? Sign in before then and choose &ldquo;Restore my account&rdquo;. Everything will be exactly as you left it.';
    meanwhile := 'Until then your account is hidden from other people, and it sends you no other emails.';
    button_label := 'Open Productivity Tracker';
    footer := 'Productivity Tracker · kristoffergt.com · This is an automated message, please don''t reply directly to it.';
  end if;

  -- The welcome email's markup, so the two read as one sender.
  body_html :=
    '<div style="background:#F5F5F6;padding:32px 16px;font-family:-apple-system,BlinkMacSystemFont,''Inter'',Helvetica,Arial,sans-serif;">' ||
      '<div style="max-width:480px;margin:0 auto;background:#ffffff;border:1px solid #E1E1E3;border-radius:12px;overflow:hidden;">' ||
        '<div style="background:#1E1F22;padding:20px 28px;">' ||
          '<img src="https://kristoffergt.com/icon-192.png" width="24" height="24" alt="" style="vertical-align:middle;border-radius:6px;margin-right:8px;display:inline-block;" />' ||
          '<span style="font-family:Georgia,''Noto Serif KR'',serif;color:#F5F5F6;font-size:18px;font-weight:bold;letter-spacing:0.02em;vertical-align:middle;">Productivity Tracker</span>' ||
        '</div>' ||
        '<div style="padding:28px;color:#1E1F22;font-size:15px;line-height:1.65;">' ||
          '<p style="margin:0 0 16px;font-size:20px;font-weight:bold;">' || title || '</p>' ||
          '<p style="margin:0 0 12px;">' || intro || '</p>' ||
          '<p style="margin:0 0 20px;">' || restore || '</p>' ||
          '<div style="margin:0 0 24px;">' ||
            '<a href="https://kristoffergt.com" style="display:inline-block;background:#4F7563;color:#ffffff;text-decoration:none;padding:11px 24px;border-radius:6px;font-size:15px;font-weight:600;">' || button_label || '</a>' ||
          '</div>' ||
          '<p style="margin:0;color:#6B6D72;font-size:13px;">' || meanwhile || '</p>' ||
        '</div>' ||
        '<div style="padding:16px 28px;border-top:1px solid #EFEFEF;color:#6B6D72;font-size:12px;">' || footer || '</div>' ||
      '</div>' ||
    '</div>';

  perform net.http_post(
    url := 'https://api.resend.com/emails',
    headers := jsonb_build_object('Authorization', 'Bearer ' || api_key, 'Content-Type', 'application/json'),
    body := jsonb_build_object(
      'from', 'Productivity Tracker <noreply@kristoffergt.com>',
      'to', user_email,
      'subject', subject,
      'html', body_html
    )
  );
end;
$$;
revoke all on function public.send_account_deletion_email(uuid, timestamptz) from public, anon, authenticated;

-- ---- Asking for it, and taking it back ---------------------------------------
-- Returns when the account will be deleted. Asking twice keeps the first
-- date and sends no second email.
create or replace function public.request_account_deletion()
returns timestamptz
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_at timestamptz;
begin
  if v_uid is null then
    raise exception 'Not signed in.';
  end if;
  if current_is_admin() then
    raise exception 'The admin account cannot be deleted.';
  end if;
  select deletion_scheduled_at into v_at from profiles where id = v_uid;
  if v_at is null then
    perform set_config('pt.account_deletion', '1', true);
    update profiles set deletion_scheduled_at = now() where id = v_uid returning deletion_scheduled_at into v_at;
    perform set_config('pt.account_deletion', '', true);
    if v_at is null then
      raise exception 'No profile for this account.';
    end if;
    perform send_account_deletion_email(v_uid, v_at + interval '30 days');
  end if;
  return v_at + interval '30 days';
end;
$$;
revoke all on function public.request_account_deletion() from public, anon;
grant execute on function public.request_account_deletion() to authenticated;

create or replace function public.cancel_account_deletion()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Not signed in.';
  end if;
  perform set_config('pt.account_deletion', '1', true);
  update profiles set deletion_scheduled_at = null where id = auth.uid();
  perform set_config('pt.account_deletion', '', true);
end;
$$;
revoke all on function public.cancel_account_deletion() from public, anon;
grant execute on function public.cancel_account_deletion() to authenticated;

-- The immediate delete_own_account() is revoked by
-- account_deletion_grace_part2_migration.sql, which goes in only once the page
-- that calls request_account_deletion() instead is live: the old page still
-- calls it, and revoking it first would break deleting on the live site.

-- ---- After 30 days, for good --------------------------------------------------
create or replace function public.purge_scheduled_account_deletions()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
begin
  for r in
    select id from profiles
    where deletion_scheduled_at is not null
      and deletion_scheduled_at <= now() - interval '30 days'
      and not is_admin_user(id)
  loop
    -- The same purge the old immediate delete ran. Files in storage are swept
    -- by the daily purge-orphan-files job once the account is gone.
    perform _purge_user_data(r.id);
  end loop;
end;
$$;
revoke all on function public.purge_scheduled_account_deletions() from public, anon, authenticated;
select cron.schedule('purge-scheduled-account-deletions', '7 * * * *', 'select public.purge_scheduled_account_deletions();');

-- ---- Nothing is sent to a pending account ------------------------------------
create or replace function public.wants_email_notification(target_user_id uuid, ntype text)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $$
  select not account_pending_deletion(target_user_id)
     and coalesce((select email from notification_prefs where user_id = target_user_id and type = ntype), true);
$$;
create or replace function public.wants_in_app_notification(target_user_id uuid, ntype text)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $$
  select not account_pending_deletion(target_user_id)
     and coalesce((select in_app from notification_prefs where user_id = target_user_id and type = ntype), true);
$$;
create or replace function public.wants_push_notification(target_user_id uuid, ntype text)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $$
  select not account_pending_deletion(target_user_id)
     and coalesce((select push from notification_prefs where user_id = target_user_id and type = ntype), true);
$$;

-- The two recaps choose their recipients from profiles themselves; the pending
-- test goes into that WHERE. Patched in place rather than restated, because
-- they are long and nothing else in them changes. A second run finds the test
-- already there and leaves them alone.
do $$
declare
  def text;
begin
  def := pg_get_functiondef('public.send_daily_recap()'::regprocedure);
  if position('p.deletion_scheduled_at IS NULL' in def) = 0 then
    if position('WHERE p.daily_recap_time_of_day = now_time' in def) = 0 then
      raise exception 'send_daily_recap has changed; add the pending-deletion test by hand';
    end if;
    execute replace(def, 'WHERE p.daily_recap_time_of_day = now_time', 'WHERE p.deletion_scheduled_at IS NULL AND p.daily_recap_time_of_day = now_time');
  end if;
  def := pg_get_functiondef('public.send_weekly_recap()'::regprocedure);
  if position('p.deletion_scheduled_at IS NULL' in def) = 0 then
    if position('WHERE (p.notify_weekly_recap_email OR p.notify_weekly_recap_inapp)' in def) = 0 then
      raise exception 'send_weekly_recap has changed; add the pending-deletion test by hand';
    end if;
    execute replace(def, 'WHERE (p.notify_weekly_recap_email OR p.notify_weekly_recap_inapp)', 'WHERE p.deletion_scheduled_at IS NULL AND (p.notify_weekly_recap_email OR p.notify_weekly_recap_inapp)');
  end if;
end $$;

-- ---- A pending account is out of everybody else's circle ---------------------
create or replace function public.shared_circle(a uuid, b uuid)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $$
  select a is not null and b is not null and (
    a = b
    or (
      not account_pending_deletion(a) and not account_pending_deletion(b)
      and ((is_core_member(a) and is_core_member(b)) or is_linked(a, b))
    )
  );
$$;
create or replace function public.shared_circle_cat(a uuid, b uuid, cat text)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $$
  select a is not null and b is not null and (
    a = b
    or (
      not account_pending_deletion(a) and not account_pending_deletion(b)
      and (
        (is_core_member(a) and is_core_member(b))
        or (
          is_linked(a, b)
          and coalesce(
            (select enabled from link_sharing_settings where user_id = b and target_user_id = a and category = cat),
            (select enabled from link_sharing_settings where user_id = b and target_user_id = b and category = cat),
            true
          )
        )
      )
    )
  );
$$;

-- ---- ... and off every leaderboard --------------------------------------------
create or replace function public.reading_leaderboard()
returns table(user_id uuid, finished_count bigint)
language sql stable security definer set search_path to 'public'
as $$
  select b.user_id, count(*) filter (where b.status = 'finished') as finished_count
  from books b
  join profiles p on p.id = b.user_id
  where p.deletion_scheduled_at is null
    and (coalesce(p.hide_from_leaderboards, false) = false or shared_circle(auth.uid(), p.id) or current_is_admin())
  group by b.user_id;
$$;
create or replace function public.articles_leaderboard()
returns table(user_id uuid, finished_count bigint)
language sql stable security definer set search_path to 'public'
as $$
  select a.user_id, count(*) filter (where a.status = 'finished') as finished_count
  from articles a
  join profiles p on p.id = a.user_id
  where p.deletion_scheduled_at is null
    and (coalesce(p.hide_from_leaderboards, false) = false or shared_circle(auth.uid(), p.id) or current_is_admin())
  group by a.user_id;
$$;
create or replace function public.job_leaderboard()
returns table(user_id uuid, application_count bigint)
language sql stable security definer set search_path to 'public'
as $$
  select j.user_id, count(*) as application_count
  from job_applications j
  join profiles p on p.id = j.user_id
  where p.deletion_scheduled_at is null
    and (coalesce(p.hide_from_leaderboards, false) = false or shared_circle(auth.uid(), p.id) or current_is_admin())
  group by j.user_id;
$$;
create or replace function public.certification_leaderboard()
returns table(user_id uuid, acquired_count bigint)
language sql stable security definer set search_path to 'public'
as $$
  select c.user_id, count(*) filter (where c.status = 'acquired') as acquired_count
  from certifications c
  join profiles p on p.id = c.user_id
  where p.deletion_scheduled_at is null
    and (coalesce(p.hide_from_leaderboards, false) = false or shared_circle(auth.uid(), p.id) or current_is_admin())
  group by c.user_id;
$$;
create or replace function public.study_daily_totals()
returns table(user_id uuid, entry_date date, total_hours numeric)
language sql stable security definer set search_path to 'public'
as $$
  select se.user_id, se.entry_date,
    coalesce((select sum(value::numeric) from jsonb_each_text(se.activities)), 0) as total_hours
  from study_entries se
  join profiles p on p.id = se.user_id
  where p.deletion_scheduled_at is null
    and (coalesce(p.hide_from_leaderboards, false) = false or shared_circle(auth.uid(), p.id) or current_is_admin());
$$;
