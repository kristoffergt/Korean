-- ============================================================================
-- Part 2 of account_deletion_grace_migration.sql. Apply ONLY once the page
-- that deletes through request_account_deletion() is live on kristoffergt.com:
-- the page before it calls delete_own_account(), and this takes that away.
--
-- The immediate delete skipped the 30 days, so nobody signed in may call it.
-- Safe to re-run.
-- ============================================================================

revoke all on function public.delete_own_account() from public, anon, authenticated;
