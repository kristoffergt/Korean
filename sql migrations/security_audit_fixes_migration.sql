-- Security audit fixes, part 1 of 2 (26 Sep 2026). Applied to the live
-- database the same day. Everything here works with the page as it is
-- already deployed; the changes that need the new index.html / 404.html
-- first are in security_audit_fixes_part2_migration.sql.
--
-- What this closes, in the audit's own order:
--   1. _purge_user_data(uuid) was callable by anyone, signed out included,
--      and deletes an account and everything in it. Now service-role only;
--      delete_own_account() and admin_delete_user() still reach it because
--      they run as its owner.
--   2. A user could make themselves a core member. "profiles updatable by
--      owner" allowed any column, and permissive policies OR together, so it
--      beat profiles_update_own's is_core_member check. The loose policies
--      are gone and a trigger now refuses the change for anyone but the admin.
--   4. send_weekly_recap / send_daily_recap / send_due_reminders were
--      callable by anyone, so anyone could make the app email and push every
--      user on a loop. The cron jobs run as postgres and are unaffected.
--   6. create_notification(target, type, title, body) let any signed-in user
--      put any text in anyone's bell and on their phone. Nothing in the page
--      calls it; only link_accept_invite() does, as its owner.
--   8. syllabi: any signed-in user could delete or upload anything. Now
--      own-folder only, PDF/Word only, 20 MB. The other buckets got type and
--      size limits too.
--   9. The shared grammar list could be edited by anyone signed in. Now the
--      core members only (the policy for editing resources already said so).
--   Plus, found on the way:
--   - Every SECURITY DEFINER function was executable by the signed-out role.
--     Now only the four the sign-in screen needs are, and new functions no
--     longer get that grant by default.
--   - verify_site_pin() could be guessed without limit (10,000 codes). Now
--     10 wrong guesses per IP per 15 minutes.
--   - Deleting an account left rows behind in grammar_srs, quiz_attempts,
--     link_sharing_settings and link_group_members, and a user who had ever
--     edited a partner's course note or a grammar point could not be deleted
--     at all (updated_by foreign keys with no ON DELETE).
--   - The reminder and Yonsei emails ignored the "Email" switch in
--     Notification settings. They honour it now.
--   - Names and event titles went into emails as raw HTML, so a circle
--     member could put links or images into someone else's email.
--   - file_links.url is now constrained to this project's storage, which
--     stops a short link pointing at a javascript: URL.

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
create or replace function public.html_escape(s text)
returns text language sql immutable set search_path = public as $$
  select replace(replace(replace(replace(replace(coalesce(s, ''),
    '&', '&amp;'), '<', '&lt;'), '>', '&gt;'), '"', '&quot;'), '''', '&#39;');
$$;

create or replace function public.wants_email_notification(target_user_id uuid, ntype text)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select email from notification_prefs where user_id = target_user_id and type = ntype), true);
$$;

-- Files in a folder named after an account that no longer exists. Read by
-- the purge-orphan-files edge function, which deletes them through the
-- Storage API (a direct DELETE on storage.objects is refused, and would leave
-- the file itself behind anyway).
create or replace function public.orphaned_storage_objects()
returns table(bucket_id text, name text) language sql stable security definer
set search_path = public, storage as $$
  select o.bucket_id, o.name from storage.objects o
  where split_part(o.name, '/', 1) ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    and not exists (select 1 from auth.users u where u.id::text = split_part(o.name, '/', 1));
$$;

-- ---------------------------------------------------------------------------
-- 1. Account deletion: service-role only, and complete
-- ---------------------------------------------------------------------------
create or replace function public._purge_user_data(target_user_id uuid)
returns void language plpgsql security definer set search_path to 'public' as $function$
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
  DELETE FROM courses WHERE user_id = v_uid;
  DELETE FROM link_sharing_settings l WHERE l.user_id = v_uid OR l.target_user_id = v_uid;
  DELETE FROM link_group_members m WHERE m.user_id = v_uid;
  -- Rows the account only last edited stay with their owner, minus the name.
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
$function$;

-- ---------------------------------------------------------------------------
-- 5. HTML-escape user text in the emails, and honour the Email switch
-- ---------------------------------------------------------------------------
-- The senders are rewritten in place rather than retyped: each anchor must
-- occur exactly as often as expected or the whole migration stops.
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
  -- send_due_reminders
  d := pg_get_functiondef('public.send_due_reminders()'::regprocedure);
  d := pg_temp.swap(d, $a$coalesce(rec.display_name, 'there')$a$, $b$html_escape(coalesce(rec.display_name, 'there'))$b$, 1);
  d := pg_temp.swap(d, $a$<strong>' || rec.title || '</strong>$a$, $b$<strong>' || html_escape(rec.title) || '</strong>$b$, 1);
  d := pg_temp.swap(d, $a$perform net.http_post($a$, $b$if wants_email_notification(rec.user_id, 'reminder') then
          perform net.http_post($b$, 1);
  d := pg_temp.swap(d, $a$if wants_in_app_notification(rec.user_id, 'reminder') then$a$, $b$end if;

          if wants_in_app_notification(rec.user_id, 'reminder') then$b$, 1);
  execute d;

  -- send_daily_recap()
  d := pg_get_functiondef('public.send_daily_recap()'::regprocedure);
  d := pg_temp.swap(d, $a$coalesce(rec.display_name, 'there')$a$, $b$html_escape(coalesce(rec.display_name, 'there'))$b$, 1);
  d := pg_temp.swap(d, $a$ev.title || '</li>'$a$, $b$html_escape(ev.title) || '</li>'$b$, 2);
  execute d;

  -- send_weekly_recap()
  d := pg_get_functiondef('public.send_weekly_recap()'::regprocedure);
  d := pg_temp.swap(d, $a$coalesce(rec.display_name, 'there')$a$, $b$html_escape(coalesce(rec.display_name, 'there'))$b$, 1);
  d := pg_temp.swap(d, $a$ev.title || '</li>'$a$, $b$html_escape(ev.title) || '</li>'$b$, 4);
  execute d;

  -- notify_yonsei_board_new_items(jsonb): the board's own titles and links
  -- are third-party text too.
  d := pg_get_functiondef('public.notify_yonsei_board_new_items(jsonb)'::regprocedure);
  d := pg_temp.swap(d, $a$coalesce(rec.display_name, 'there')$a$, $b$html_escape(coalesce(rec.display_name, 'there'))$b$, 1);
  d := pg_temp.swap(d, $a$(elem->>'link')$a$, $b$html_escape(elem->>'link')$b$, 1);
  d := pg_temp.swap(d, $a$(elem->>'title')$a$, $b$html_escape(elem->>'title')$b$, 1);
  d := pg_temp.swap(d, $a$(elem->>'date')$a$, $b$html_escape(elem->>'date')$b$, 1);
  d := pg_temp.swap(d, $a$PERFORM net.http_post($a$, $b$IF wants_email_notification(rec.recipient_id, 'yonsei_board') THEN
    PERFORM net.http_post($b$, 1);
  d := pg_temp.swap(d, $a$IF wants_in_app_notification(rec.recipient_id, 'yonsei_board') THEN$a$, $b$END IF;

    IF wants_in_app_notification(rec.recipient_id, 'yonsei_board') THEN$b$, 1);
  execute d;

  -- send_welcome_email() (profile trigger): the greeting and the admin copy.
  d := pg_get_functiondef('public.send_welcome_email()'::regprocedure);
  d := pg_temp.swap(d, $a$Hi ' || new.display_name$a$, $b$Hi ' || html_escape(new.display_name)$b$, 1);
  d := pg_temp.swap(d, $a$Name: ' || new.display_name$a$, $b$Name: ' || html_escape(new.display_name)$b$, 1);
  d := pg_temp.swap(d, $a$Email: ' || user_email$a$, $b$Email: ' || html_escape(user_email)$b$, 1);
  execute d;
end $$;

-- ---------------------------------------------------------------------------
-- 2. Nobody but the admin changes is_core_member
-- ---------------------------------------------------------------------------
drop policy if exists "profiles updatable by owner" on public.profiles;
drop policy if exists "profiles insertable by owner" on public.profiles;
drop policy if exists "profiles readable by logged in users" on public.profiles; -- duplicate of profiles_select_all

-- SECURITY INVOKER on purpose: current_user is then the role the request
-- came in as, so a request through the API ('authenticated') is checked and
-- SECURITY DEFINER functions, cron and the SQL editor (all postgres) are not.
create or replace function public.guard_profile_privileges()
returns trigger language plpgsql set search_path = public as $$
BEGIN
  IF current_user IN ('authenticated', 'anon') AND NOT coalesce(public.current_is_admin(), false) THEN
    IF TG_OP = 'INSERT' AND coalesce(NEW.is_core_member, false) THEN
      RAISE EXCEPTION 'Only the admin can make someone a core member.' USING ERRCODE = '42501';
    ELSIF TG_OP = 'UPDATE' AND NEW.is_core_member IS DISTINCT FROM OLD.is_core_member THEN
      RAISE EXCEPTION 'Only the admin can change core membership.' USING ERRCODE = '42501';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
drop trigger if exists profiles_guard_privileges on public.profiles;
create trigger profiles_guard_privileges before insert or update on public.profiles
  for each row execute function public.guard_profile_privileges();

-- The page already refuses anything but letters, digits, spaces, ' and -,
-- up to 12; the database now does too, so a name can never carry markup.
alter table public.profiles drop constraint if exists profiles_display_name_chars;
alter table public.profiles add constraint profiles_display_name_chars
  check (display_name is null or display_name ~ '^[[:alpha:][:digit:] ''-]{1,12}$');

-- Colours go into style attributes; keep them colours.
alter table public.profiles drop constraint if exists profiles_color_format;
alter table public.profiles add constraint profiles_color_format
  check (color is null or color = '' or color ~* '^(#[0-9a-f]{3,8}|(rgb|rgba|hsl|hsla)\([0-9., %]+\)|[a-z]{3,20})$');
alter table public.events drop constraint if exists events_color_format;
alter table public.events add constraint events_color_format
  check (color is null or color = '' or color ~* '^(#[0-9a-f]{3,8}|(rgb|rgba|hsl|hsla)\([0-9., %]+\)|[a-z]{3,20})$');
alter table public.course_notes drop constraint if exists course_notes_color_format;
alter table public.course_notes add constraint course_notes_color_format
  check (color is null or color = '' or color ~* '^(#[0-9a-f]{3,8}|(rgb|rgba|hsl|hsla)\([0-9., %]+\)|[a-z]{3,20})$');
alter table public.notebook_notes drop constraint if exists notebook_notes_color_format;
alter table public.notebook_notes add constraint notebook_notes_color_format
  check (color is null or color = '' or color ~* '^(#[0-9a-f]{3,8}|(rgb|rgba|hsl|hsla)\([0-9., %]+\)|[a-z]{3,20})$');

-- ---------------------------------------------------------------------------
-- Short links: never a non-storage URL, and no owner ids for signed-out
-- readers. (Signed-out reading goes away entirely in part 2.)
-- ---------------------------------------------------------------------------
alter table public.file_links drop constraint if exists file_links_url_is_storage;
alter table public.file_links add constraint file_links_url_is_storage
  check (url like 'https://kbqwitmxpmkueryjsyip.supabase.co/storage/v1/object/public/%');
alter table public.file_links drop constraint if exists file_links_slug_format;
alter table public.file_links add constraint file_links_slug_format
  check (slug ~ '^[a-z0-9][a-z0-9-]{0,63}$');
revoke select on public.file_links from anon;
grant select (slug, url, label, created_at) on public.file_links to anon;

alter table public.job_applications drop constraint if exists job_applications_file_urls;
alter table public.job_applications add constraint job_applications_file_urls check (
  (resume_url is null or resume_url like 'https://kbqwitmxpmkueryjsyip.supabase.co/storage/v1/object/public/job-application-files/%')
  and (cover_letter_url is null or cover_letter_url like 'https://kbqwitmxpmkueryjsyip.supabase.co/storage/v1/object/public/job-application-files/%'));
alter table public.courses drop constraint if exists courses_syllabus_url;
alter table public.courses add constraint courses_syllabus_url check (
  syllabus_url is null or syllabus_url like 'https://kbqwitmxpmkueryjsyip.supabase.co/storage/v1/object/public/syllabi/%');

-- ---------------------------------------------------------------------------
-- 9. Shared grammar list: core members only
-- ---------------------------------------------------------------------------
drop policy if exists "grammar points update" on public.grammar_points;
drop policy if exists grammar_points_insert on public.grammar_points;
drop policy if exists grammar_points_insert_core on public.grammar_points;
create policy grammar_points_insert_core on public.grammar_points
  for insert to authenticated with check (is_core_member(auth.uid()));

-- ---------------------------------------------------------------------------
-- 8. Storage
-- ---------------------------------------------------------------------------
drop policy if exists "syllabi owner delete" on storage.objects;
drop policy if exists "syllabi authenticated upload" on storage.objects;
drop policy if exists "syllabi public read" on storage.objects;
drop policy if exists "syllabi upload own folder" on storage.objects;
drop policy if exists "syllabi delete own folder" on storage.objects;
drop policy if exists "syllabi select own or circle" on storage.objects;
create policy "syllabi upload own folder" on storage.objects for insert to authenticated
  with check (bucket_id = 'syllabi' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "syllabi delete own folder" on storage.objects for delete to authenticated
  using (bucket_id = 'syllabi' and (storage.foldername(name))[1] = auth.uid()::text);
-- The bucket is public, so a file's URL still opens for anyone; what this
-- stops is signed-out LISTING of every syllabus (and the account ids that
-- name their folders).
create policy "syllabi select own or circle" on storage.objects for select to authenticated
  using (bucket_id = 'syllabi' and (
    (storage.foldername(name))[1] = auth.uid()::text
    or ((storage.foldername(name))[1] ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        and shared_circle(auth.uid(), ((storage.foldername(name))[1])::uuid))));

-- Read access to CVs and cover letters, for the day the bucket goes private
-- (part 2): the owner, and whoever can already see the job application.
drop policy if exists "job app files select own or circle" on storage.objects;
create policy "job app files select own or circle" on storage.objects for select to authenticated
  using (bucket_id = 'job-application-files' and (
    (storage.foldername(name))[1] = auth.uid()::text
    or ((storage.foldername(name))[1] ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        and shared_circle_cat(auth.uid(), ((storage.foldername(name))[1])::uuid, 'job_applications'))));

update storage.buckets set file_size_limit = 20971520,
  allowed_mime_types = array['application/pdf', 'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document']
  where id = 'syllabi';
update storage.buckets set file_size_limit = 10485760,
  allowed_mime_types = array['image/png', 'image/jpeg', 'image/gif', 'image/webp', 'image/heic', 'image/heif']
  where id in ('writing-images', 'note-media');
update storage.buckets set file_size_limit = 10485760 where id in ('job-application-files', 'resume');

-- ---------------------------------------------------------------------------
-- The site PIN: 10 wrong guesses per IP per 15 minutes
-- ---------------------------------------------------------------------------
create table if not exists public.site_pin_attempts (
  id bigserial primary key,
  ip text not null,
  attempted_at timestamptz not null default now()
);
create index if not exists site_pin_attempts_ip_time on public.site_pin_attempts (ip, attempted_at);
alter table public.site_pin_attempts enable row level security; -- no policies: no client access
revoke all on public.site_pin_attempts from anon, authenticated;

create or replace function public.verify_site_pin(candidate text)
returns boolean language plpgsql volatile security definer set search_path to 'public' as $$
DECLARE
  hdrs json := nullif(current_setting('request.headers', true), '')::json;
  v_ip text;
  v_recent int;
BEGIN
  v_ip := coalesce(hdrs->>'cf-connecting-ip', trim(split_part(hdrs->>'x-forwarded-for', ',', 1)), hdrs->>'x-real-ip', 'unknown');
  IF v_ip = '' THEN v_ip := 'unknown'; END IF;
  DELETE FROM site_pin_attempts WHERE attempted_at < now() - interval '1 day';
  SELECT count(*) INTO v_recent FROM site_pin_attempts a
    WHERE a.ip = v_ip AND a.attempted_at > now() - interval '15 minutes';
  IF v_recent >= 10 THEN
    RAISE EXCEPTION 'too_many_attempts' USING ERRCODE = 'P0429';
  END IF;
  IF EXISTS (SELECT 1 FROM site_config WHERE key = 'signup_pin' AND value = candidate) THEN
    RETURN true;
  END IF;
  INSERT INTO site_pin_attempts(ip) VALUES (v_ip);
  RETURN false;
END;
$$;

-- ---------------------------------------------------------------------------
-- Function privileges
-- ---------------------------------------------------------------------------
-- Internal: cron, triggers and other SECURITY DEFINER functions (which run
-- as the owner) call these. No end user needs them.
do $$
declare f regprocedure;
begin
  for f in
    select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname in (
      '_purge_user_data', 'send_daily_recap', 'send_due_reminders', 'send_weekly_recap',
      'send_welcome_email', 'notify_push_on_notification', 'create_notification',
      'wants_in_app_notification', 'wants_push_notification', 'wants_email_notification',
      'orphaned_storage_objects', 'html_escape', 'guard_profile_privileges')
  loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;

  -- Everything else that is SECURITY DEFINER: signed-in users only, except
  -- the four the sign-in screen calls before anyone is signed in.
  for f in
    select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prosecdef
      and has_function_privilege('anon', p.oid, 'execute')
      and p.proname not in ('verify_site_pin', 'reserve_display_name', 'display_name_available', 'email_for_display_name')
  loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated, service_role', f);
  end loop;

  for f in
    select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname in ('verify_site_pin', 'reserve_display_name', 'display_name_available', 'email_for_display_name')
  loop
    execute format('revoke all on function %s from public', f);
    execute format('grant execute on function %s to anon, authenticated, service_role', f);
  end loop;
end $$;

-- New functions stop being callable by the signed-out role by default. A
-- function the sign-in screen needs must now be granted to anon explicitly.
-- (PUBLIC has to go globally too: anon is a member of PUBLIC, and a per-schema
-- rule cannot take away a global default.)
alter default privileges for role postgres revoke execute on functions from public;
alter default privileges for role postgres in schema public revoke execute on functions from anon;
