-- ============================================================================
-- study_entries, books, and job_applications each carried a legacy SELECT
-- policy ("study select" / "books select" / "jobs select") predating the
-- shared_circle_cat()-gated ones (study_entries_select / books_select /
-- job_applications_select). Its qual was just `auth.uid() IS NOT NULL` --
-- true for every signed-in account on the whole site.
--
-- Postgres OR's multiple permissive policies for the same command, so this
-- blanket policy alone made all three tables fully world-readable to any
-- logged-in user regardless of shared_circle_cat()'s check or anyone's
-- sharing settings -- the category toggles for these three were silently
-- not being enforced at all. Dropping the legacy policy leaves the correct
-- shared_circle_cat()-gated one as the only SELECT policy, same pattern
-- already used cleanly by certifications/writing_samples.
--
-- Safe to re-run.
-- ============================================================================

DROP POLICY IF EXISTS "study select" ON study_entries;
DROP POLICY IF EXISTS "books select" ON books;
DROP POLICY IF EXISTS "jobs select" ON job_applications;
