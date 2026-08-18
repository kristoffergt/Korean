-- ============================================================================
-- Per-user "seen" tracking for job board items, so the NEW tag is genuinely
-- per-account: if you've viewed the board, an item stays marked seen for
-- you (survives a refresh), but someone else who hasn't looked yet still
-- sees NEW on their own account. yonsei_jobboard_items.first_seen_at is a
-- global "when did the sync first ingest this" timestamp and isn't
-- per-viewer, so it can't answer "has *this* user seen it" -- hence a
-- separate join table instead of reusing that column.
--
-- Safe to re-run.
-- ============================================================================

CREATE TABLE IF NOT EXISTS jobboard_items_seen (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  item_idx bigint NOT NULL REFERENCES yonsei_jobboard_items(idx) ON DELETE CASCADE,
  seen_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, item_idx)
);
ALTER TABLE jobboard_items_seen ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS jobboard_items_seen_select_own ON jobboard_items_seen;
CREATE POLICY jobboard_items_seen_select_own ON jobboard_items_seen
  FOR SELECT TO authenticated USING (user_id = auth.uid());
DROP POLICY IF EXISTS jobboard_items_seen_insert_own ON jobboard_items_seen;
CREATE POLICY jobboard_items_seen_insert_own ON jobboard_items_seen
  FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
