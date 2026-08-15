-- ============================================================================
-- Adds two features:
--   1) A new "Notebook" sub-tab under Study — a Korean-notes-only note space
--      that mirrors course_notes but has no course concept at all. Lives in
--      its own table, notebook_notes, same shared-read/own-write RLS shape.
--   2) An optional free-text "header" on both course_notes and notebook_notes
--      so headerless notes can be grouped under a custom label the user picks
--      (e.g. "Idioms", "TOPIK mistakes") instead of always falling into the
--      fixed "General notes" bucket. Leaving it blank keeps today's behavior.
--
-- Safe to re-run. Run after privacy_rls_migration.sql (needs shared_circle()).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1) Custom header column on the existing course_notes table.
-- ---------------------------------------------------------------------------
ALTER TABLE course_notes ADD COLUMN IF NOT EXISTS header text;

-- ---------------------------------------------------------------------------
-- 2) notebook_notes — same shape as course_notes minus course_id, plus header.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS notebook_notes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  header text,
  lecture_title text NOT NULL,
  content text DEFAULT '',
  color text,
  sort_order integer NOT NULL DEFAULT 0,
  previous_versions jsonb NOT NULL DEFAULT '[]'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz,
  updated_by uuid
);
ALTER TABLE notebook_notes ENABLE ROW LEVEL SECURITY;

-- Shared read within the core circle, own-only write — identical shape to
-- course_notes (see privacy_rls_migration.sql), matching the same "isMine"
-- edit-button gating used in the app's UI.
DROP POLICY IF EXISTS "notebook_notes_select" ON notebook_notes;
CREATE POLICY "notebook_notes_select" ON notebook_notes FOR SELECT
  TO authenticated
  USING (shared_circle(auth.uid(), user_id));

DROP POLICY IF EXISTS "notebook_notes_insert" ON notebook_notes;
CREATE POLICY "notebook_notes_insert" ON notebook_notes FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "notebook_notes_update" ON notebook_notes;
CREATE POLICY "notebook_notes_update" ON notebook_notes FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "notebook_notes_delete" ON notebook_notes;
CREATE POLICY "notebook_notes_delete" ON notebook_notes FOR DELETE
  TO authenticated
  USING (auth.uid() = user_id);
