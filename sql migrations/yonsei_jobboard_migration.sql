-- ============================================================================
-- Stores a scraped copy of the login-gated Yonsei GSIS Career Development
-- Center "Job/Internship Board" (https://gsis1.yonsei.ac.kr/cdc/board.asp?
-- mid=n02_01), a separate site from the public GSIS notices board (see
-- yonsei_boards_migration.sql) -- this one requires a real Yonsei login, so
-- there is no server-side "just fetch the page" option the way there is for
-- the public notices board. Claude does not perform logins or handle
-- passwords under any circumstances, so this can't be a scheduled
-- fetch-with-credentials job the way fetch-yonsei-board is.
--
-- Instead: the user logs into the board in their own browser (their own
-- session, their own credentials, never seen by this app) and clicks a
-- bookmarklet that POSTs the current page's HTML to the ingest-yonsei-
-- jobboard Edge Function, which parses it (supabase/functions/ingest-
-- yonsei-jobboard/parse.ts) and upserts the listings here via its
-- service-role client (bypasses RLS entirely, so no INSERT/UPDATE policy is
-- defined below -- this table is write-only from that one function).
--
-- idx is the board's own numeric article id (pulled from the "idx=" query
-- param on each listing's link), used as the natural primary key so
-- re-ingesting the same page (or an overlapping page) upserts in place
-- instead of duplicating. No "seen" dedup table is needed here the way
-- yonsei_board_seen exists for the public board's notify pipeline --
-- explicitly no notification logic was wanted for this board, so there's
-- nothing that needs a one-time "is this new" check; every ingest just
-- reflects the current state of whatever the user's bookmarklet captured.
--
-- RLS: readable by any authenticated user of this app (same posture as
-- other shared reference data, e.g. grammar_points) -- it's not
-- per-user data, just a cache of one login-gated page's public-within-
-- Yonsei listings.
--
-- check_yonsei_jobboard_ingest_secret(text): the ingest endpoint has to be
-- callable by the bookmarklet running on gsis1.yonsei.ac.kr with only the
-- publishable anon key available to it (same as fetch-yonsei-board), but
-- unlike that function this one WRITES data, so verify_jwt:false alone
-- would let anyone with the (intentionally public) anon key inject fake
-- listings. This function checks a caller-supplied secret against one
-- stored in Vault (name 'yonsei_jobboard_ingest_secret', set directly via
-- vault.create_secret(), never written to this file or any other committed
-- file) -- mirrors how 'resend_api_key' is already handled. The bookmarklet
-- embeds that same secret in a custom header; it lives only in the
-- bookmarklet text the user keeps in their own browser, never in this repo.
--
-- Safe to re-run (except the vault secret itself, which is set separately
-- and is not part of this migration).
-- ============================================================================

CREATE TABLE IF NOT EXISTS yonsei_jobboard_items (
  idx bigint PRIMARY KEY,
  link text NOT NULL,
  title text NOT NULL,
  industry text NOT NULL,
  type text NOT NULL,
  date_posted date NOT NULL,
  deadline date,
  first_seen_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE yonsei_jobboard_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "yonsei_jobboard_items readable by authenticated" ON yonsei_jobboard_items;
CREATE POLICY "yonsei_jobboard_items readable by authenticated" ON yonsei_jobboard_items
  FOR SELECT TO authenticated USING (true);

CREATE OR REPLACE FUNCTION check_yonsei_jobboard_ingest_secret(provided text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  expected text;
BEGIN
  SELECT decrypted_secret INTO expected
  FROM vault.decrypted_secrets
  WHERE name = 'yonsei_jobboard_ingest_secret';

  RETURN expected IS NOT NULL AND provided IS NOT NULL AND provided = expected;
END;
$function$;

GRANT EXECUTE ON FUNCTION check_yonsei_jobboard_ingest_secret(text) TO service_role;
