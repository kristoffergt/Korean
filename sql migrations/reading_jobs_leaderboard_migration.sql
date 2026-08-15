-- ============================================================================
-- Splits "detail" privacy from "leaderboard" visibility for Reading (books)
-- and Job hunt (job_applications):
--   - The actual rows (book titles/authors, company names/roles) stay exactly
--     as private as they already are today: shared_circle-only, i.e. visible
--     to you and the other core member (Roxy <-> Kristoffer), never to a
--     third-party signup. No RLS change needed here — this was already
--     correct in privacy_rls_migration.sql.
--   - The LEADERBOARDS (finished-book count, application count) should be
--     visible to anyone signed in, without exposing which books or companies
--     produced that count. Since the row-level RLS above blocks a
--     non-core-member from reading Roxy/Kristoffer's rows at all, a plain
--     client-side count from the fetched rows can't work for a third party —
--     so this adds two SECURITY DEFINER functions that compute the counts
--     server-side (bypassing RLS internally) and return ONLY the aggregate
--     number, never the underlying rows. Grant them to `authenticated` so any
--     signed-in account can see the leaderboard.
--
-- Safe to re-run. Run after privacy_rls_migration.sql.
-- ============================================================================

CREATE OR REPLACE FUNCTION reading_leaderboard()
RETURNS TABLE(user_id uuid, finished_count bigint)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT b.user_id, COUNT(*) FILTER (WHERE b.status = 'finished') AS finished_count
  FROM books b
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
  GROUP BY j.user_id;
$$;
GRANT EXECUTE ON FUNCTION job_leaderboard() TO authenticated;
