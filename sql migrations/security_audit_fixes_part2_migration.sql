-- Security audit fixes, part 2.
--
-- ONLY APPLY THIS ONCE THE PAGE FROM COMMIT 6e3b9fd IS LIVE. Everything here
-- closes something the OLD page still depends on:
--   * the old page looks up a display name's email itself, through
--     email_for_display_name, and this revokes that from the browser;
--   * the old page opens CVs through their public URL, and this makes the
--     bucket private;
--   * the old 404.html reads file_links signed out, and this makes the table
--     owner-only;
--   * the old sign-up does not send the site PIN, and this refuses a sign-up
--     without it.
-- Applied early, sign-in by name, every CV link and every short link on the
-- live site stop working, and nobody can sign up.
--
-- Part 1 is security_audit_fixes_migration.sql.

-- ---------------------------------------------------------------------------
-- 1. A display name no longer tells the browser whose email it is.
--    sign-in-by-name (an edge function, service role) is the only caller now.
-- ---------------------------------------------------------------------------
revoke execute on function public.email_for_display_name(text) from public, anon, authenticated;
grant execute on function public.email_for_display_name(text) to service_role;

-- ---------------------------------------------------------------------------
-- 2. The site PIN is checked by the server at sign-up, not just by the page.
--
--    verify_site_pin only gated the page, so anybody calling the Auth API
--    directly could make an account without the PIN. The page now sends the
--    PIN it was given as sign-up metadata (site_pin); this checks it and then
--    strips it, so it never stays in the account's metadata.
--
--    Only an ordinary sign-up is checked. A user created from the Supabase
--    dashboard arrives already confirmed (auto-confirm) or invited, and has no
--    PIN to send. That test relies on "Confirm email" staying ON for sign-up:
--    with it off, a public sign-up would also arrive confirmed and skip the
--    check.
--
--    A refusal comes back from Auth as "Database error saving new user"; the
--    page reads that as a stale PIN and sends the visitor back to the gate.
--    With no PIN configured at all, nothing is refused.
-- ---------------------------------------------------------------------------
create or replace function public.check_signup_site_pin()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_pin text := new.raw_user_meta_data->>'site_pin';
begin
  if new.raw_user_meta_data ? 'site_pin' then
    new.raw_user_meta_data := new.raw_user_meta_data - 'site_pin';
  end if;
  if tg_op = 'INSERT'
     and new.email_confirmed_at is null
     and new.invited_at is null
     and coalesce(new.is_anonymous, false) = false
     and exists (select 1 from public.site_config where key = 'signup_pin')
     and not exists (select 1 from public.site_config where key = 'signup_pin' and value = v_pin)
  then
    raise exception 'signup_pin_required' using errcode = '28000';
  end if;
  return new;
end;
$$;

revoke all on function public.check_signup_site_pin() from public, anon, authenticated;

drop trigger if exists check_signup_site_pin on auth.users;
create trigger check_signup_site_pin
  before insert or update of raw_user_meta_data on auth.users
  for each row execute function public.check_signup_site_pin();

-- ---------------------------------------------------------------------------
-- 3. CVs and cover letters are private. The page opens them through a signed
--    URL (openStoredFile) and short links resolve through the file-link edge
--    function, which signs too. The storage select policy from part 1 already
--    lets the owner and their circle read them.
--    The syllabi bucket is deliberately NOT touched here (left out with the
--    other copyright items).
-- ---------------------------------------------------------------------------
update storage.buckets set public = false where id = 'job-application-files';

-- ---------------------------------------------------------------------------
-- 4. file_links is owner-only. Read unfiltered it listed every CV URL in the
--    app; 404.html now asks the file-link function for one slug instead.
-- ---------------------------------------------------------------------------
drop policy if exists file_links_public_read on public.file_links;
drop policy if exists file_links_select_own on public.file_links;
create policy file_links_select_own on public.file_links
  for select to authenticated using (owner_id = auth.uid());
revoke all on public.file_links from anon;

-- ---------------------------------------------------------------------------
-- 5. Every recap, reminder and notice email can be unsubscribed from.
--
--    The link carries the account, the kind of email and an HMAC of the two,
--    made with a key that never leaves the vault. The unsubscribe edge
--    function passes all three to unsubscribe_email, which checks the HMAC
--    and switches off that one kind of email only (in-app notifications stay
--    on). Every such email gets:
--      * a footer link to kristoffergt.com/unsubscribe.html, which asks
--        before doing anything, since mail scanners open links on their own;
--      * List-Unsubscribe and List-Unsubscribe-Post headers (RFC 8058), so
--        Gmail and Apple Mail show their own one-click unsubscribe button.
--    The welcome email is transactional and gets neither.
-- ---------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from vault.secrets where name = 'unsubscribe_secret') then
    perform vault.create_secret(
      encode(extensions.gen_random_bytes(32), 'hex'),
      'unsubscribe_secret',
      'HMAC key for the unsubscribe links in emails'
    );
  end if;
end $$;

create or replace function public.email_unsubscribe_token(p_uid uuid, p_kind text)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select encode(extensions.hmac(p_uid::text || ':' || p_kind, s.decrypted_secret, 'sha256'), 'hex')
  from vault.decrypted_secrets s
  where s.name = 'unsubscribe_secret';
$$;

create or replace function public.email_unsubscribe_query(p_uid uuid, p_kind text)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select 'u=' || p_uid::text || '&k=' || p_kind || '&t=' || public.email_unsubscribe_token(p_uid, p_kind);
$$;

create or replace function public.email_unsubscribe_headers(p_uid uuid, p_kind text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'List-Unsubscribe', '<https://kbqwitmxpmkueryjsyip.supabase.co/functions/v1/unsubscribe?'
                        || public.email_unsubscribe_query(p_uid, p_kind) || '>',
    'List-Unsubscribe-Post', 'List-Unsubscribe=One-Click'
  );
$$;

create or replace function public.email_unsubscribe_footer(p_uid uuid, p_kind text)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select ' <a href="' || public.html_escape('https://kristoffergt.com/unsubscribe.html?'
                          || public.email_unsubscribe_query(p_uid, p_kind))
         || '" style="color:#6B6D72;text-decoration:underline;">Unsubscribe</a>';
$$;

create or replace function public.unsubscribe_email(p_uid uuid, p_kind text, p_token text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_expected text;
begin
  if p_uid is null or p_kind is null or p_token is null then
    return false;
  end if;
  if p_kind not in ('daily_recap', 'weekly_recap', 'reminder', 'yonsei_board') then
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

revoke all on function public.email_unsubscribe_token(uuid, text) from public, anon, authenticated;
revoke all on function public.email_unsubscribe_query(uuid, text) from public, anon, authenticated;
revoke all on function public.email_unsubscribe_headers(uuid, text) from public, anon, authenticated;
revoke all on function public.email_unsubscribe_footer(uuid, text) from public, anon, authenticated;
revoke all on function public.unsubscribe_email(uuid, text, text) from public, anon, authenticated;
grant execute on function public.email_unsubscribe_token(uuid, text) to service_role;
grant execute on function public.email_unsubscribe_query(uuid, text) to service_role;
grant execute on function public.email_unsubscribe_headers(uuid, text) to service_role;
grant execute on function public.email_unsubscribe_footer(uuid, text) to service_role;
grant execute on function public.unsubscribe_email(uuid, text, text) to service_role;

-- The senders are rewritten in place, the same way part 1 did it: each
-- anchor must be found exactly as often as expected or the whole migration
-- rolls back, so nothing is half-applied to a function that has since moved.
create or replace function pg_temp.swap(src text, a text, b text, expect int)
returns text language plpgsql as $f$
DECLARE
  cnt int := (length(src) - length(replace(src, a, ''))) / length(a);
BEGIN
  IF cnt <> expect THEN
    RAISE EXCEPTION 'rewrite anchor "%" found % times, expected %', left(a, 80), cnt, expect;
  END IF;
  RETURN replace(src, a, b);
END;
$f$;

do $$
declare d text;
begin
  -- Event reminders
  d := pg_get_functiondef('public.send_due_reminders()'::regprocedure);
  d := pg_temp.swap(d, $a$'to', rec.user_email,$a$,
    $b$'to', rec.user_email,
              'headers', email_unsubscribe_headers(rec.user_id, 'reminder'),$b$, 1);
  d := pg_temp.swap(d,
    $a$'You''re receiving this because you subscribed to a reminder for this event. Manage reminders from the event in your calendar.'$a$,
    $b$'You''re receiving this because you subscribed to a reminder for this event. Manage reminders from the event in your calendar.' || email_unsubscribe_footer(rec.user_id, 'reminder')$b$, 1);
  execute d;

  -- Daily recap
  d := pg_get_functiondef('public.send_daily_recap()'::regprocedure);
  d := pg_temp.swap(d, $a$'to', rec.user_email,$a$,
    $b$'to', rec.user_email,
          'headers', email_unsubscribe_headers(rec.uid, 'daily_recap'),$b$, 1);
  d := pg_temp.swap(d,
    $a$'You''re receiving this because Daily recap is turned on in Notifications settings.'$a$,
    $b$'You''re receiving this because Daily recap is turned on in Notifications settings.' || email_unsubscribe_footer(rec.uid, 'daily_recap')$b$, 1);
  execute d;

  -- Weekly recap
  d := pg_get_functiondef('public.send_weekly_recap()'::regprocedure);
  d := pg_temp.swap(d, $a$'to', rec.user_email,$a$,
    $b$'to', rec.user_email,
          'headers', email_unsubscribe_headers(rec.uid, 'weekly_recap'),$b$, 1);
  d := pg_temp.swap(d,
    $a$'You''re receiving this because Weekly recap is turned on in Notifications settings.'$a$,
    $b$'You''re receiving this because Weekly recap is turned on in Notifications settings.' || email_unsubscribe_footer(rec.uid, 'weekly_recap')$b$, 1);
  execute d;

  -- Yonsei notices
  d := pg_get_functiondef('public.notify_yonsei_board_new_items(jsonb)'::regprocedure);
  d := pg_temp.swap(d, $a$'to', rec.user_email,$a$,
    $b$'to', rec.user_email,
        'headers', email_unsubscribe_headers(rec.recipient_id, 'yonsei_board'),$b$, 1);
  d := pg_temp.swap(d,
    $a$'You''re receiving this because notifications are turned on for the Yonsei Official Notices board. Change this anytime in the Yonsei Boards tab.'$a$,
    $b$'You''re receiving this because notifications are turned on for the Yonsei Official Notices board. Change this anytime in the Yonsei Boards tab.' || email_unsubscribe_footer(rec.recipient_id, 'yonsei_board')$b$, 1);
  execute d;
end $$;

-- The two-argument send_daily_recap(text) is the old slot-based version. No
-- cron job calls it (the job runs send_daily_recap() every minute), and it
-- never escaped event titles, so it goes rather than being patched.
drop function if exists public.send_daily_recap(text);

-- ---------------------------------------------------------------------------
-- 6. A deleted account's files are removed every night, even when the page's
--    own call after a deletion is missed (closed tab, lost connection).
--    purge-orphan-files only ever removes files in a folder named after an
--    account that no longer exists, and refuses when that is most of storage.
-- ---------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from cron.job where jobname = 'purge-orphan-files') then
    perform cron.unschedule('purge-orphan-files');
  end if;
end $$;

select cron.schedule(
  'purge-orphan-files',
  '17 18 * * *',  -- 03:17 in Seoul
  $cron$
    select net.http_post(
      url := 'https://kbqwitmxpmkueryjsyip.supabase.co/functions/v1/purge-orphan-files',
      headers := '{"Content-Type": "application/json"}'::jsonb,
      body := '{}'::jsonb
    );
  $cron$
);
