-- ============================================================================
-- Hardens the two Yonsei-related SECURITY DEFINER functions, per findings
-- from Supabase's security advisor after adding
-- check_yonsei_jobboard_ingest_secret():
--
-- 1. function_search_path_mutable: neither function pinned search_path,
--    which leaves a SECURITY DEFINER function open to search_path hijacking
--    (a caller-controlled search_path could shadow an unqualified table/
--    function reference with a malicious one in another schema they own).
--    Neither function actually has an unqualified reference that's
--    exploitable today, but pinning it is the correct default for any
--    SECURITY DEFINER function regardless.
--
-- 2. anon_security_definer_function_executable /
--    authenticated_security_definer_function_executable: both functions
--    were only ever meant to be called by their respective Edge Functions'
--    service-role clients, but neither migration revoked the default PUBLIC
--    execute grant Postgres gives new functions, so anon/authenticated
--    could call them directly via PostgREST RPC. For
--    check_yonsei_jobboard_ingest_secret specifically this matters most --
--    it was an unintended oracle letting any anon caller probe the ingest
--    secret. Revoked from anon/authenticated on both; service_role's grant
--    (set at creation) is untouched.
--
-- Safe to re-run.
-- ============================================================================

ALTER FUNCTION notify_yonsei_board_new_items(jsonb) SET search_path = public, pg_temp;
REVOKE EXECUTE ON FUNCTION notify_yonsei_board_new_items(jsonb) FROM PUBLIC, anon, authenticated;

ALTER FUNCTION check_yonsei_jobboard_ingest_secret(text) SET search_path = public, pg_temp;
REVOKE EXECUTE ON FUNCTION check_yonsei_jobboard_ingest_secret(text) FROM PUBLIC, anon, authenticated;
