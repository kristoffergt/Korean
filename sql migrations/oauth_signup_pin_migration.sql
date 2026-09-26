-- Sign-up with Google, Kakao, GitHub and LinkedIn, still behind the site PIN.
--
-- An email sign-up carries the PIN in its metadata, and check_signup_site_pin
-- refuses the account without it. An OAuth sign-up cannot carry anything: the
-- provider sends the person straight back to Supabase, which creates the
-- account there and then. So an OAuth account is created LOCKED instead, and
-- unlocked by redeeming the PIN:
--
--   * a trigger records every new account whose first way in is a provider in
--     signup_pin_pending;
--   * custom_access_token_hook issues such an account a token with role anon
--     instead of authenticated, so PostgREST, Storage and Realtime all treat it
--     exactly as a signed-out visitor: it can read nothing a stranger cannot,
--     and write nothing;
--   * redeem_signup_pin(pin) checks the PIN (through verify_site_pin, so the
--     same 10-per-15-minutes limit applies) and removes the row. The page then
--     refreshes the session, and the next token is an ordinary one;
--   * an account still locked after 7 days is deleted by a nightly job.
--
-- An existing member who signs in with a provider using the same, confirmed
-- email is LINKED to their account by Supabase rather than given a new one, so
-- no row is inserted into auth.users and nothing here applies to them.
--
-- The hook only works once it is switched on in the dashboard
-- (Authentication > Auth Hooks > Customize Access Token (JWT) Claims, Postgres,
-- public.custom_access_token_hook), and it must be on BEFORE any provider is.
-- Without it a locked account gets an ordinary token.

-- ---------------------------------------------------------------------------
-- 1. Who is still locked.
-- ---------------------------------------------------------------------------
create table if not exists public.signup_pin_pending (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.signup_pin_pending enable row level security;
revoke all on public.signup_pin_pending from public, anon, authenticated;
-- No policies: only the security definer functions below read or write it.

-- ---------------------------------------------------------------------------
-- 2. A new account whose first way in is a provider starts locked.
--
--    Two triggers, because which one sees the provider first is Supabase's
--    business: the account row carries it in raw_app_meta_data when it is
--    inserted, and the identity row inserted straight after names it outright.
--    The identity trigger only locks an account that is brand new, has no
--    other way in and no profile yet, so a member linking a provider to an
--    existing account is never caught by it.
-- ---------------------------------------------------------------------------
create or replace function public.lock_provider_signup()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if coalesce(new.raw_app_meta_data->>'provider', 'email') not in ('email', 'phone')
     and new.invited_at is null
     and coalesce(new.is_anonymous, false) = false
  then
    insert into public.signup_pin_pending (user_id) values (new.id)
    on conflict (user_id) do nothing;
  end if;
  return null;
end;
$$;
revoke all on function public.lock_provider_signup() from public, anon, authenticated;

drop trigger if exists lock_provider_signup on auth.users;
create trigger lock_provider_signup
  after insert on auth.users
  for each row execute function public.lock_provider_signup();

create or replace function public.lock_provider_identity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.provider not in ('email', 'phone')
     and not exists (select 1 from auth.identities i where i.user_id = new.user_id and i.id <> new.id)
     and not exists (select 1 from public.profiles p where p.id = new.user_id)
     and exists (
       select 1 from auth.users u
       where u.id = new.user_id
         and u.invited_at is null
         and u.created_at > now() - interval '10 minutes'
     )
  then
    insert into public.signup_pin_pending (user_id) values (new.user_id)
    on conflict (user_id) do nothing;
  end if;
  return null;
end;
$$;
revoke all on function public.lock_provider_identity() from public, anon, authenticated;

drop trigger if exists lock_provider_identity on auth.identities;
create trigger lock_provider_identity
  after insert on auth.identities
  for each row execute function public.lock_provider_identity();

-- ---------------------------------------------------------------------------
-- 3. The PIN check at sign-up is for EMAIL sign-ups only now.
--
--    A provider may send an account with no confirmed email (GitHub with a
--    private address, Kakao without the email permission), which the old test
--    would have refused outright for not carrying a PIN it has no way to
--    carry. Those accounts are locked by the triggers above instead. A missing
--    provider still counts as email, so the check fails closed.
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
     and coalesce(new.raw_app_meta_data->>'provider', 'email') = 'email'
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

-- ---------------------------------------------------------------------------
-- 4. A locked account's token says role anon.
--
--    Any error answers with the token unchanged: this runs for EVERY sign-in
--    and refresh, and a hook that fails stops everybody signing in.
-- ---------------------------------------------------------------------------
create or replace function public.custom_access_token_hook(event jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_claims jsonb;
begin
  begin
    if exists (select 1 from public.signup_pin_pending where user_id = (event->>'user_id')::uuid) then
      v_claims := coalesce(event->'claims', '{}'::jsonb);
      v_claims := jsonb_set(v_claims, '{role}', '"anon"');
      v_claims := jsonb_set(v_claims, '{signup_pin_pending}', 'true');
      return jsonb_set(event, '{claims}', v_claims);
    end if;
  exception when others then
    return event;
  end;
  return event;
end;
$$;
revoke all on function public.custom_access_token_hook(jsonb) from public, anon, authenticated;
grant execute on function public.custom_access_token_hook(jsonb) to supabase_auth_admin;

-- ---------------------------------------------------------------------------
-- 5. What the page asks, and how it unlocks.
--    Both are callable with role anon, which is what a locked account's token
--    carries; auth.uid() still reads the account from the token's sub. A
--    signed-out visitor has no sub, so both answer false for them.
-- ---------------------------------------------------------------------------
create or replace function public.signup_pin_pending_for_me()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is not null
     and exists (select 1 from public.signup_pin_pending where user_id = auth.uid());
$$;
revoke all on function public.signup_pin_pending_for_me() from public;
grant execute on function public.signup_pin_pending_for_me() to anon, authenticated;

create or replace function public.redeem_signup_pin(candidate text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    return false;
  end if;
  if not exists (select 1 from public.signup_pin_pending where user_id = v_uid) then
    return true;
  end if;
  if not coalesce(public.verify_site_pin(candidate), false) then
    return false;
  end if;
  delete from public.signup_pin_pending where user_id = v_uid;
  return true;
end;
$$;
revoke all on function public.redeem_signup_pin(text) from public;
grant execute on function public.redeem_signup_pin(text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 6. A locked account nobody unlocked is removed after a week. It owns no
--    data (it could never write any), so this deletes the login and nothing
--    else; the pending row goes with it by cascade.
-- ---------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from cron.job where jobname = 'purge-locked-signups') then
    perform cron.unschedule('purge-locked-signups');
  end if;
end $$;

select cron.schedule(
  'purge-locked-signups',
  '47 18 * * *',  -- 03:47 in Seoul
  $cron$
    delete from auth.users u
    using public.signup_pin_pending p
    where p.user_id = u.id
      and p.created_at < now() - interval '7 days';
  $cron$
);
