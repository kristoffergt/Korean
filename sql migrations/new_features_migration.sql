-- ============================================================================
-- New features migration: manual "unmark reviewed" overrides, YouTube/link
-- resources on grammar points, and a Writing Practice table.
--
-- Assumes privacy_rls_migration.sql has already been run (uses its
-- is_core_member() / shared_circle() helper functions).
-- Safe to re-run: uses IF NOT EXISTS / DROP POLICY IF EXISTS throughout.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1) Manual "unmark as reviewed" overrides.
-- A row here means "this user has manually forced this pattern back to
-- not-reviewed, even though a matching sentence exists." Deleting the row
-- reverts to normal auto-detection. Fully private to each user — nobody
-- else needs to see or touch your overrides, not even your partner.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS grammar_review_overrides (
  user_id uuid NOT NULL,
  pattern_id text NOT NULL,
  unmarked boolean NOT NULL DEFAULT true,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, pattern_id)
);
ALTER TABLE grammar_review_overrides ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "grammar_review_overrides_select" ON grammar_review_overrides;
CREATE POLICY "grammar_review_overrides_select" ON grammar_review_overrides FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "grammar_review_overrides_insert" ON grammar_review_overrides;
CREATE POLICY "grammar_review_overrides_insert" ON grammar_review_overrides FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "grammar_review_overrides_update" ON grammar_review_overrides;
CREATE POLICY "grammar_review_overrides_update" ON grammar_review_overrides FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "grammar_review_overrides_delete" ON grammar_review_overrides;
CREATE POLICY "grammar_review_overrides_delete" ON grammar_review_overrides FOR DELETE
  TO authenticated
  USING (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- 2) YouTube/link resources per grammar point.
-- Stored as a jsonb array of {type: 'youtube'|'link', url, label}. Only
-- core members (Roxy & Kristoffer) can add/edit these through the app;
-- everyone signed in can read them. The grammar_points table otherwise
-- stays locked down to the SQL editor for every other column (see
-- privacy_rls_migration.sql) — this grants write access to exactly the
-- `resources` column and nothing else, even for core members.
-- ---------------------------------------------------------------------------
ALTER TABLE grammar_points ADD COLUMN IF NOT EXISTS resources jsonb NOT NULL DEFAULT '[]'::jsonb;

GRANT UPDATE (resources) ON grammar_points TO authenticated;

DROP POLICY IF EXISTS "grammar_points_update_resources" ON grammar_points;
CREATE POLICY "grammar_points_update_resources" ON grammar_points FOR UPDATE
  TO authenticated
  USING (is_core_member(auth.uid()))
  WITH CHECK (is_core_member(auth.uid()));

-- ---------------------------------------------------------------------------
-- 3) Writing Practice samples.
-- Shared read within the core circle (Roxy & Kristoffer can always read
-- each other's samples — this is the standing rule for the whole app now),
-- own-only write, matching books/job_applications/grammar_notes.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS writing_samples (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  topic text,
  content text,
  word_count integer NOT NULL DEFAULT 0,
  previous_versions jsonb NOT NULL DEFAULT '[]'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz,
  updated_by uuid
);
ALTER TABLE writing_samples ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "writing_samples_select" ON writing_samples;
CREATE POLICY "writing_samples_select" ON writing_samples FOR SELECT
  TO authenticated
  USING (shared_circle(auth.uid(), user_id));

DROP POLICY IF EXISTS "writing_samples_insert" ON writing_samples;
CREATE POLICY "writing_samples_insert" ON writing_samples FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "writing_samples_update" ON writing_samples;
CREATE POLICY "writing_samples_update" ON writing_samples FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "writing_samples_delete" ON writing_samples;
CREATE POLICY "writing_samples_delete" ON writing_samples FOR DELETE
  TO authenticated
  USING (auth.uid() = user_id);
