-- ============================================================================
-- Site-wide 4-digit PIN gate on the sign-up/sign-in screen. The PIN itself
-- is generated once (not by this migration -- inserted separately, so the
-- actual value is never committed to this public repo) and lives in a
-- locked-down config table, never in client-side source.
--
--   verify_site_pin(candidate): called from the (pre-auth) PIN entry screen,
--   granted to anon since nobody has a session yet at that point. Returns a
--   boolean only -- never the real value.
--
--   get_site_pin(): called from Settings for an already-authenticated
--   account to display the current PIN. Granted to authenticated only.
--
-- Safe to re-run (the INSERT is separate and not part of this file).
-- ============================================================================

CREATE TABLE IF NOT EXISTS site_config (
  key text PRIMARY KEY,
  value text NOT NULL
);
ALTER TABLE site_config ENABLE ROW LEVEL SECURITY;
-- No policies -- only the two SECURITY DEFINER functions below touch this.

CREATE OR REPLACE FUNCTION verify_site_pin(candidate text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (SELECT 1 FROM site_config WHERE key = 'signup_pin' AND value = candidate);
$$;
GRANT EXECUTE ON FUNCTION verify_site_pin(text) TO anon, authenticated;

CREATE OR REPLACE FUNCTION get_site_pin()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE WHEN auth.uid() IS NOT NULL THEN (SELECT value FROM site_config WHERE key = 'signup_pin') END;
$$;
REVOKE EXECUTE ON FUNCTION get_site_pin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_site_pin() TO authenticated;
