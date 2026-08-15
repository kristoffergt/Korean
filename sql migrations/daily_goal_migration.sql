-- ============================================================================
-- Makes the "daily study goal" (used for the heatmap colors, streaks, and
-- the "Goal hit" markers) a per-person setting instead of the hardcoded
-- 5-hour constant every account used to share.
--
-- Rule: for a normal account this is a private, personal number. But
-- Kristoffer and Roxy (the two `is_core_member = true` accounts) are treated
-- as one linked unit here on purpose — if either of them changes the goal,
-- it updates both of their rows together, since they use this app jointly.
-- Any other signed-up account only ever changes its own row.
--
-- Requires privacy_rls_migration.sql (uses is_core_member/current_is_core_member).
-- Safe to re-run.
-- ============================================================================

ALTER TABLE profiles ADD COLUMN IF NOT EXISTS daily_goal_hours numeric NOT NULL DEFAULT 5;

CREATE OR REPLACE FUNCTION set_daily_goal(new_goal numeric)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF new_goal IS NULL OR new_goal <= 0 OR new_goal > 24 THEN
    RAISE EXCEPTION 'Daily goal must be greater than 0 and no more than 24 hours.';
  END IF;
  IF current_is_core_member() THEN
    UPDATE profiles SET daily_goal_hours = new_goal WHERE is_core_member = true;
  ELSE
    UPDATE profiles SET daily_goal_hours = new_goal WHERE id = auth.uid();
  END IF;
END;
$$;
GRANT EXECUTE ON FUNCTION set_daily_goal(numeric) TO authenticated;
