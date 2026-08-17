-- ============================================================================
-- Grace period for a display name chosen during signup but not yet confirmed.
--
-- profiles rows (and thus display_name_available()'s check) are only ever
-- created once someone completes a real, confirmed sign-in (see
-- ensureProfileExists()/onAuthed() in index.html) -- so an unconfirmed
-- signup never blocks anyone else from taking that name. That's correct in
-- steady state, but leaves a gap: while someone's own confirmation email is
-- in flight, a different person could grab the exact name they just chose
-- out from under them.
--
-- This adds a short-lived (30 minute) reservation, keyed by email, so a name
-- picked at signup is held for that signer only. Retrying the same signup
-- (same email, or the same browser/device -- localStorage token, in case
-- they mistype the email a second time) always succeeds against their own
-- reservation; a genuinely different person is blocked from the name until
-- the reservation expires.
--
-- Safe to re-run.
-- ============================================================================

CREATE TABLE IF NOT EXISTS pending_signup_names (
  email text PRIMARY KEY,
  display_name text NOT NULL,
  browser_token text,
  reserved_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE pending_signup_names ENABLE ROW LEVEL SECURITY;
-- No policies -- only the SECURITY DEFINER function below touches this table.

-- Called instead of a plain display_name_available() check right before
-- auth.signUp(). Returns false (name unavailable) if a confirmed profile
-- already owns the name, or if a *different* email on a *different* browser
-- currently holds an active reservation on it. Otherwise reserves/refreshes
-- it for this email+browser and returns true.
CREATE OR REPLACE FUNCTION reserve_display_name(p_email text, p_name text, p_browser_token text DEFAULT NULL)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  norm_email text := lower(trim(p_email));
BEGIN
  IF EXISTS (SELECT 1 FROM profiles WHERE lower(display_name) = lower(p_name)) THEN
    RETURN false;
  END IF;
  IF EXISTS (
    SELECT 1 FROM pending_signup_names
    WHERE lower(display_name) = lower(p_name)
      AND reserved_at > now() - interval '30 minutes'
      AND lower(email) <> norm_email
      AND (browser_token IS DISTINCT FROM p_browser_token OR p_browser_token IS NULL)
  ) THEN
    RETURN false;
  END IF;
  INSERT INTO pending_signup_names(email, display_name, browser_token, reserved_at)
  VALUES (norm_email, p_name, p_browser_token, now())
  ON CONFLICT (email) DO UPDATE
    SET display_name = excluded.display_name, browser_token = excluded.browser_token, reserved_at = now();
  RETURN true;
END;
$$;
GRANT EXECUTE ON FUNCTION reserve_display_name(text, text, text) TO anon, authenticated;
