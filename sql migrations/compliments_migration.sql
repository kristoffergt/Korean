-- ============================================================================
-- Compliments, for one account.
--
-- profiles.compliments turns on the page's compliments (the Compliments block
-- in index.html): a greeting of its own and a compliment on Home, and now and
-- then one after finishing something. Off for everyone by default, and on
-- here for Roxy (requested 4 Nov). The account is found as the core member
-- with that display name, so no id or email is written down.
--
-- Safe to re-run.
-- ============================================================================

alter table public.profiles add column if not exists compliments boolean not null default false;

update public.profiles set compliments = true where is_core_member and display_name = 'Roxy';
