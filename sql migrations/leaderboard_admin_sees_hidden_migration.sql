-- ============================================================================
-- The admin should never be leaderboard-blind: someone hiding themselves via
-- profiles.hide_from_leaderboards still needs to be visible to the site
-- admin (tagged "(hidden)" client-side, see lbNameCell()/isAdminViewer() in
-- index.html), same way current_is_admin() already bypasses other user-
-- privacy gates in account_admin_migration.sql.
--
-- Adds `OR current_is_admin()` to the three leaderboard-aggregate functions
-- from leaderboard_expansion_migration.sql. certification_leaderboard()
-- (certifications_migration.sql) doesn't filter hide_from_leaderboards at
-- all yet -- a separate pre-existing gap, left untouched here.
--
-- Safe to re-run.
-- ============================================================================

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
     OR shared_circle(auth.uid(), p.id)
     OR current_is_admin();
$$;

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
     OR current_is_admin()
  GROUP BY b.user_id;
$$;

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
     OR current_is_admin()
  GROUP BY j.user_id;
$$;
