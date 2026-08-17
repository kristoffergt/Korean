-- ============================================================================
-- Live presence/live-insert support for Notebook notes and Yonsei course
-- notes (see subscribeNoteRealtimeInserts()/broadcastWriting() in
-- index.html). postgres_changes subscriptions only fire for tables added to
-- the supabase_realtime publication -- neither table was in it before this.
--
-- No RLS changes needed: Realtime's postgres_changes already enforces each
-- table's existing RLS policy per subscriber (shared_circle() for both
-- tables), so a linked person's new note only ever arrives for someone
-- already allowed to see it -- same rule the initial page load uses.
--
-- Safe to re-run (ALTER PUBLICATION ... ADD TABLE errors if already a
-- member, so this checks first).
-- ============================================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'notebook_notes'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE notebook_notes;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'course_notes'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE course_notes;
  END IF;
END $$;
