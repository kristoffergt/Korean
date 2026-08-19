-- ============================================================================
-- Live push for the notification bell and incoming/accepted link invites
-- (see subscribeNotifRealtime()/subscribeLinkRealtime() in index.html) --
-- same reasoning as note_realtime_migration.sql: postgres_changes only
-- fires for tables added to the supabase_realtime publication, and neither
-- table was in it before this.
--
-- No RLS changes needed: Realtime's postgres_changes already enforces each
-- table's existing RLS policy per subscriber, so a row only ever arrives
-- for someone already allowed to see it -- same rule the initial page load
-- uses.
--
-- Safe to re-run (ALTER PUBLICATION ... ADD TABLE errors if already a
-- member, so this checks first).
-- ============================================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'notifications'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE notifications;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'link_group_members'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE link_group_members;
  END IF;
END $$;
