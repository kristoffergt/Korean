-- ============================================================================
-- Adds independent "Teaching Assistant" / "Research Assistant" flags to
-- courses. Deliberately NOT part of the status column (planning/signed_up/
-- locked_in) — you can TA or RA a course whether or not you're also taking
-- it, and unlike locking in, these are freely toggleable at any time (no
-- confirmation, no removing the status dropdown).
--
-- No RLS changes needed: courses already has shared read/write within the
-- core circle (privacy_rls_migration.sql), which these two new columns
-- inherit automatically.
--
-- Safe to re-run.
-- ============================================================================

ALTER TABLE courses ADD COLUMN IF NOT EXISTS is_ta boolean NOT NULL DEFAULT false;
ALTER TABLE courses ADD COLUMN IF NOT EXISTS is_ra boolean NOT NULL DEFAULT false;
