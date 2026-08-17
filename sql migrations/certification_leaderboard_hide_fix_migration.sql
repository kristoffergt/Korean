-- ============================================================================
-- certification_leaderboard() was the one leaderboard aggregate that never
-- picked up the hide_from_leaderboards check the other three
-- (study_daily_totals/reading_leaderboard/job_leaderboard, see
-- leaderboard_expansion_migration.sql and its later
-- leaderboard_admin_sees_hidden_migration.sql follow-up) already have -- a
-- privacy gap where a user who opted out still showed up here for everyone.
-- Brings it in line: same join-profiles + same three-way OR (visible by
-- default, or you're in shared_circle with them, or you're the admin).
--
-- Safe to re-run.
-- ============================================================================

CREATE OR REPLACE FUNCTION certification_leaderboard()
RETURNS TABLE(user_id uuid, acquired_count bigint)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT c.user_id, COUNT(*) FILTER (WHERE c.status = 'acquired') AS acquired_count
  FROM certifications c
  JOIN profiles p ON p.id = c.user_id
  WHERE COALESCE(p.hide_from_leaderboards, false) = false
     OR shared_circle(auth.uid(), p.id)
     OR current_is_admin()
  GROUP BY c.user_id;
$$;
GRANT EXECUTE ON FUNCTION certification_leaderboard() TO authenticated;
