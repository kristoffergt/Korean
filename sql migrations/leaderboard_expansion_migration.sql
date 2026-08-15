-- ============================================================================
-- Two changes to the site's three leaderboards (study streaks, books
-- finished, job applications):
--
--   1) A personal "hide me from leaderboards" toggle. Someone may not want
--      their name/stats shown publicly even though the counts themselves
--      are already privacy-safe aggregates (no titles, companies, or study
--      activity details). This is a simple boolean on profiles.
--
--      Hiding is scoped per-viewer, not global: a hidden row still shows up
--      for the person themselves and for their own core study partner
--      (Kristoffer <-> Roxy) — it only disappears for everyone else. This
--      reuses the same shared_circle(a,b) helper from
--      privacy_rls_migration.sql that already scopes books/jobs/study data,
--      so "hidden from strangers, visible to your partner" falls out for
--      free: shared_circle(auth.uid(), row's user_id) is true for yourself
--      and, if you're both core members, for your partner too.
--
--   2) The study-streak leaderboard used to only work for the two
--      `is_core_member` accounts, because it was built entirely client-side
--      from the detailed `study_entries` rows the current user's RLS grants
--      them (self + core partner only). To show EVERY signed-up account
--      (like the reading/job leaderboards already do), this adds
--      study_daily_totals() — a SECURITY DEFINER function that exposes only
--      the summed hours per user per day (never which activities), for
--      every visible-to-you user. The client merges this in for any
--      user/date it doesn't already have full detail for, and reuses its
--      existing streak/week/total math unchanged.
--
-- Safe to re-run. Run after privacy_rls_migration.sql and
-- reading_jobs_leaderboard_migration.sql.
-- ============================================================================

ALTER TABLE profiles ADD COLUMN IF NOT EXISTS hide_from_leaderboards boolean NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION study_daily_totals()
RETURNS TABLE(user_id uuid, entry_date date, total_hours numeric)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT se.user_id, se.entry_date,
    COALESCE((SELECT SUM(value::numeric) FROM jsonb_each_text(se.activities)), 0) AS total_hours
  FROM study_entries se
  JOIN profiles p ON p.id = se.user_id
  WHERE COALESCE(p.hide_from_leaderboards, false) = false
     OR shared_circle(auth.uid(), p.id);
$$;
GRANT EXECUTE ON FUNCTION study_daily_totals() TO authenticated;

CREATE OR REPLACE FUNCTION reading_leaderboard()
RETURNS TABLE(user_id uuid, finished_count bigint)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT b.user_id, COUNT(*) FILTER (WHERE b.status = 'finished') AS finished_count
  FROM books b
  JOIN profiles p ON p.id = b.user_id
  WHERE COALESCE(p.hide_from_leaderboards, false) = false
     OR shared_circle(auth.uid(), p.id)
  GROUP BY b.user_id;
$$;
GRANT EXECUTE ON FUNCTION reading_leaderboard() TO authenticated;

CREATE OR REPLACE FUNCTION job_leaderboard()
RETURNS TABLE(user_id uuid, application_count bigint)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT j.user_id, COUNT(*) AS application_count
  FROM job_applications j
  JOIN profiles p ON p.id = j.user_id
  WHERE COALESCE(p.hide_from_leaderboards, false) = false
     OR shared_circle(auth.uid(), p.id)
  GROUP BY j.user_id;
$$;
GRANT EXECUTE ON FUNCTION job_leaderboard() TO authenticated;
