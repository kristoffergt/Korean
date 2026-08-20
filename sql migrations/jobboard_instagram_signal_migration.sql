-- ============================================================================
-- Replaces the fixed-hour job board auto-sync trigger with an event-driven
-- one: a third-party page-monitoring service (Visualping) watches the
-- Yonsei GSIS CDC Instagram (@yonseigsis_cdc) on its own schedule and its
-- own infrastructure -- this app never visits Instagram itself, avoiding
-- the automated-access-to-Instagram problem entirely -- and calls the
-- instagram-post-signal Edge Function's webhook when it detects a change.
-- That function upserts today's date here; maybeAutoTriggerJobBoardSync()
-- in index.html checks for today's row before firing the local sync
-- script, instead of (or in addition to) the JOB_BOARD_AUTO_SYNC_HOUR
-- clock check.
--
-- RLS: readable by any authenticated user (same posture as
-- yonsei_jobboard_items -- low-sensitivity shared reference data, not
-- per-user). No INSERT/UPDATE policy: only the Edge Function's
-- service-role client writes here, same pattern as
-- ingest-yonsei-jobboard/yonsei_jobboard_items.
--
-- check_instagram_signal_secret(text): same shared-secret-in-Vault pattern
-- as check_yonsei_jobboard_ingest_secret -- the webhook has to be callable
-- by Visualping with no user session, but it writes data, so it needs its
-- own auth rather than relying on the (intentionally public) anon key
-- alone. Secret is set via vault.create_secret(), never written to this
-- file or any other committed file -- Visualping's webhook URL carries it
-- as a query param since that's the most universally-supported way to
-- attach a credential to a generic "webhook URL" field.
--
-- Safe to re-run (except the vault secret itself, which is set separately
-- and is not part of this migration).
-- ============================================================================

CREATE TABLE IF NOT EXISTS jobboard_instagram_signal (
  signal_date date PRIMARY KEY,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE jobboard_instagram_signal ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "jobboard_instagram_signal readable by authenticated" ON jobboard_instagram_signal;
CREATE POLICY "jobboard_instagram_signal readable by authenticated" ON jobboard_instagram_signal
  FOR SELECT TO authenticated USING (true);

CREATE OR REPLACE FUNCTION check_instagram_signal_secret(provided text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  expected text;
BEGIN
  SELECT decrypted_secret INTO expected
  FROM vault.decrypted_secrets
  WHERE name = 'instagram_signal_webhook_secret';

  RETURN expected IS NOT NULL AND provided IS NOT NULL AND provided = expected;
END;
$function$;

REVOKE EXECUTE ON FUNCTION check_instagram_signal_secret(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION check_instagram_signal_secret(text) TO service_role;
