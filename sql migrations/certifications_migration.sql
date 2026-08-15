-- ============================================================================
-- Adds a "Certifications" feature as a sibling to Jobs (own sub-tab, own
-- add form, own list with edit/delete/status, own public leaderboard) —
-- same shape as job_applications throughout, and folded into the existing
-- generalized-linking privacy model as a new category rather than a
-- bespoke one, so per-partner sharing overrides work the same way they do
-- for every other personal-log table.
--
-- Safe to re-run.
-- ============================================================================

CREATE TABLE IF NOT EXISTS certifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name text NOT NULL,
  issuer text,
  status text NOT NULL DEFAULT 'in_progress' CHECK (status IN ('in_progress','acquired')),
  date_completed date,
  link text,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- Fold 'certifications' into the generalized linking system's category list
-- (link_groups_migration.sql) so it gets its own per-partner sharing toggle
-- in the "Friends" circle UI, same as job_applications/books/etc.
-- ---------------------------------------------------------------------------
ALTER TABLE link_sharing_settings DROP CONSTRAINT IF EXISTS link_sharing_settings_category_check;
ALTER TABLE link_sharing_settings ADD CONSTRAINT link_sharing_settings_category_check CHECK (category IN (
  'study_entries','books','job_applications','grammar_notes',
  'course_notes','writing_samples','recap','readiness','certifications'
));

-- ---------------------------------------------------------------------------
-- certifications — shared read within the core circle / linked circle
-- (category-aware, honoring per-partner overrides), own-only write. Same
-- shape as job_applications_select in link_groups_migration.sql.
-- ---------------------------------------------------------------------------
ALTER TABLE certifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "certifications_select" ON certifications;
CREATE POLICY "certifications_select" ON certifications FOR SELECT
  TO authenticated
  USING (shared_circle_cat(auth.uid(), user_id, 'certifications'));

DROP POLICY IF EXISTS "certifications_insert" ON certifications;
CREATE POLICY "certifications_insert" ON certifications FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "certifications_update" ON certifications;
CREATE POLICY "certifications_update" ON certifications FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "certifications_delete" ON certifications;
CREATE POLICY "certifications_delete" ON certifications FOR DELETE
  TO authenticated
  USING (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- Public leaderboard — aggregate-only (acquired count), same pattern as
-- reading_leaderboard()/job_leaderboard() in reading_jobs_leaderboard_migration.sql.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION certification_leaderboard()
RETURNS TABLE(user_id uuid, acquired_count bigint)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT c.user_id, COUNT(*) FILTER (WHERE c.status = 'acquired') AS acquired_count
  FROM certifications c
  GROUP BY c.user_id;
$$;
GRANT EXECUTE ON FUNCTION certification_leaderboard() TO authenticated;
