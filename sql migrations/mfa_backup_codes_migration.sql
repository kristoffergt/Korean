-- ============================================================================
-- 2FA recovery codes ("generate 3 codes you can download and save... in case
-- you lose it"). Codes are stored bcrypt-hashed (crypt()/gen_salt('bf'),
-- same pgcrypto pattern already used by admin_reset_user_password), never
-- in plaintext -- the plaintext is only ever returned once, at generation
-- time, for the client to show/download.
--
-- Note this app's 2FA gate is purely a client-side UX step already (no RLS
-- policy anywhere checks auth.jwt()->>'aal', confirmed before writing this),
-- so a verified backup code only needs to unblock the same client-side
-- screen transition that a verified TOTP code does -- it doesn't need to
-- elevate any session AAL that isn't being checked anywhere.
--
-- Safe to re-run.
-- ============================================================================

CREATE TABLE IF NOT EXISTS mfa_backup_codes (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  code_hash text NOT NULL,
  used_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE mfa_backup_codes ENABLE ROW LEVEL SECURITY;
-- No policies -- every access goes through the SECURITY DEFINER functions
-- below, each scoped to auth.uid().

-- Wipes any existing codes and issues 3 fresh ones for the calling user.
-- Called right after a successful TOTP enrollment confirm.
CREATE OR REPLACE FUNCTION mfa_backup_codes_generate()
RETURNS text[]
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  codes text[] := '{}';
  new_code text;
  i int;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated.';
  END IF;
  DELETE FROM mfa_backup_codes WHERE user_id = auth.uid();
  FOR i IN 1..3 LOOP
    new_code := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 4))
      || '-' || upper(substr(md5(random()::text || clock_timestamp()::text), 1, 4));
    INSERT INTO mfa_backup_codes(user_id, code_hash) VALUES (auth.uid(), crypt(new_code, gen_salt('bf')));
    codes := array_append(codes, new_code);
  END LOOP;
  RETURN codes;
END;
$$;
GRANT EXECUTE ON FUNCTION mfa_backup_codes_generate() TO authenticated;

-- Checks a code against the calling user's unused codes; consumes it (marks
-- used_at) on a match so it can't be reused. Called from the MFA challenge
-- screen's "use a backup code instead" path -- the caller already has a
-- valid (password-authenticated) session at that point.
CREATE OR REPLACE FUNCTION mfa_backup_code_verify(code text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  match_id bigint;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN false;
  END IF;
  SELECT id INTO match_id FROM mfa_backup_codes
  WHERE user_id = auth.uid() AND used_at IS NULL AND code_hash = crypt(code, code_hash)
  LIMIT 1;
  IF match_id IS NULL THEN
    RETURN false;
  END IF;
  UPDATE mfa_backup_codes SET used_at = now() WHERE id = match_id;
  RETURN true;
END;
$$;
GRANT EXECUTE ON FUNCTION mfa_backup_code_verify(text) TO authenticated;

-- Cleanup when 2FA is turned off -- stale backup codes for a disabled
-- authenticator shouldn't keep working.
CREATE OR REPLACE FUNCTION mfa_backup_codes_clear()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN RETURN; END IF;
  DELETE FROM mfa_backup_codes WHERE user_id = auth.uid();
END;
$$;
GRANT EXECUTE ON FUNCTION mfa_backup_codes_clear() TO authenticated;
