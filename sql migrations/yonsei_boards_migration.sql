-- ============================================================================
-- Adds a personal, own-row-only display preference for the new "Boards"
-- subtab (under the new Yonsei tab) that pulls in the public Yonsei GSIS
-- "Official Notices" board client-side. This is NOT a privacy/sharing
-- setting like the generalized-linking categories -- the notices feed is
-- the same for everyone (it's a public external page, not personal data)
-- -- it's just a personal "do I want to see this tab" toggle, on by
-- default for every account.
--
-- No RLS changes needed: profiles already has an own-row UPDATE policy
-- (see privacy_rls_migration.sql) that display_name/hide_from_leaderboards
-- already rely on the same way; show_yonsei_boards just piggybacks on it.
--
-- Safe to re-run.
-- ============================================================================

ALTER TABLE profiles ADD COLUMN IF NOT EXISTS show_yonsei_boards boolean NOT NULL DEFAULT true;
