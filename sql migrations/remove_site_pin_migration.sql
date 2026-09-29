-- ============================================================================
-- The site PIN is gone (real-user request, 29 Sep: "remove the 4-digit pin
-- from the site completely"). Anybody can sign up, by email or through a
-- provider, with nothing to type first.
--
-- This has to be live BEFORE the page that stops sending the PIN, or every
-- email sign-up is refused by check_signup_site_pin for not carrying one. The
-- other order is harmless: an old page's PIN simply lands in metadata that
-- nothing reads any more.
--
-- What it undoes:
--   site_pin_gate_migration.sql            site_config, verify_site_pin, get_site_pin
--   security_audit_fixes_migration.sql     site_pin_attempts (rate limit)
--   security_audit_fixes_part2_migration   check_signup_site_pin on auth.users
--   oauth_signup_pin_migration.sql         the provider lock, its pending table,
--                                          redeem/pending RPCs, the purge cron
--
-- custom_access_token_hook is NOT dropped: Supabase Auth calls it on every
-- sign-in and refresh because it is switched on in the dashboard (Auth ->
-- Hooks), and a hook that no longer exists stops everybody signing in. It
-- becomes a pass-through; switching the hook off in the dashboard afterwards
-- is safe and makes it dead code.
--
-- The notification text for the old "New site PIN required" announcement
-- (notifSystemPinTitle/Body in the page) is left alone: those rows are
-- history in people's bells.
--
-- Safe to re-run.
-- ============================================================================

-- 1. Email sign-ups: no PIN check.
drop trigger if exists check_signup_site_pin on auth.users;
drop function if exists public.check_signup_site_pin();

-- 2. Provider sign-ups: no lock.
drop trigger if exists lock_provider_signup on auth.users;
drop trigger if exists lock_provider_identity on auth.identities;
drop function if exists public.lock_provider_signup();
drop function if exists public.lock_provider_identity();

-- 3. The token hook passes every token through unchanged.
create or replace function public.custom_access_token_hook(event jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return event;
end;
$$;
revoke all on function public.custom_access_token_hook(jsonb) from public, anon, authenticated;
grant execute on function public.custom_access_token_hook(jsonb) to supabase_auth_admin;

-- 4. Anybody still locked is simply let in (the pending row was the lock),
--    and the week-long purge of locked accounts stops.
do $$
begin
  if exists (select 1 from cron.job where jobname = 'purge-locked-signups') then
    perform cron.unschedule('purge-locked-signups');
  end if;
end $$;
drop function if exists public.redeem_signup_pin(text);
drop function if exists public.signup_pin_pending_for_me();
drop table if exists public.signup_pin_pending;

-- 5. The PIN itself, its reader, its checker and its guess log.
drop function if exists public.verify_site_pin(text);
drop function if exists public.get_site_pin();
drop table if exists public.site_pin_attempts;
do $$
begin
  if to_regclass('public.site_config') is not null then
    delete from public.site_config where key = 'signup_pin';
    -- The PIN was the only thing site_config ever held.
    if not exists (select 1 from public.site_config) then
      drop table public.site_config;
    end if;
  end if;
end $$;
