-- ============================================================================
-- Self-service account deletion + a single hardcoded admin/moderator account
-- (kristoffergt@gmail.com) that can never be deleted and has recovery powers
-- over every other registered account (reset password, confirm email,
-- disable 2FA, or remove the account). This exists as a safety net now that
-- the app has self-serve delete and 2FA — someone can always get a locked-out
-- account (or themselves) unstuck without needing direct SQL-editor access.
--
-- Everything here is a SECURITY DEFINER function so it can reach into the
-- `auth` schema (which normal RLS-scoped client calls can't touch at all).
-- Each admin_* function re-checks current_is_admin() itself, so even if the
-- client UI were tampered with, the database still refuses non-admin callers.
--
-- Requires pgcrypto (for admin password resets) — enabled below if missing.
-- Safe to re-run. Run after privacy_rls_migration.sql.
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ---------------------------------------------------------------------------
-- Admin identity helpers. The admin is hardcoded to one email on purpose —
-- there's exactly one person who should ever hold recovery access here.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION is_admin_user(uid uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE((SELECT email FROM auth.users WHERE id = uid) = 'kristoffergt@gmail.com', false);
$$;

CREATE OR REPLACE FUNCTION current_is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT is_admin_user(auth.uid());
$$;

GRANT EXECUTE ON FUNCTION is_admin_user(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION current_is_admin() TO authenticated;

-- ---------------------------------------------------------------------------
-- Shared cleanup routine — deletes every row a given user owns across every
-- app table, then the auth.users row itself (auth's own schema cascades to
-- identities/sessions/refresh_tokens/mfa_factors automatically). Not granted
-- directly to `authenticated`; only called from the two functions below,
-- each of which does its own authorization check first.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION _purge_user_data(target_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  DELETE FROM study_entries WHERE user_id = target_user_id;
  DELETE FROM books WHERE user_id = target_user_id;
  DELETE FROM job_applications WHERE user_id = target_user_id;
  DELETE FROM grammar_notes WHERE user_id = target_user_id;
  DELETE FROM grammar_favorites WHERE user_id = target_user_id;
  DELETE FROM grammar_review_overrides WHERE user_id = target_user_id;
  DELETE FROM course_notes WHERE user_id = target_user_id;
  DELETE FROM notebook_notes WHERE user_id = target_user_id;
  DELETE FROM writing_samples WHERE user_id = target_user_id;
  DELETE FROM event_subscriptions WHERE user_id = target_user_id;
  DELETE FROM events WHERE user_id = target_user_id;
  DELETE FROM courses WHERE user_id = target_user_id;
  DELETE FROM profiles WHERE id = target_user_id;
  DELETE FROM auth.users WHERE id = target_user_id;
END;
$$;

-- ---------------------------------------------------------------------------
-- Self-service delete: any signed-in user can permanently delete their own
-- account and all of their data, EXCEPT the admin account, which refuses.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION delete_own_account()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF current_is_admin() THEN
    RAISE EXCEPTION 'The admin account cannot be deleted.';
  END IF;
  PERFORM _purge_user_data(auth.uid());
END;
$$;
GRANT EXECUTE ON FUNCTION delete_own_account() TO authenticated;

-- ---------------------------------------------------------------------------
-- Admin/moderator functions — all gated on current_is_admin().
-- ---------------------------------------------------------------------------

-- Safe metadata only: no password hashes, no MFA secrets.
CREATE OR REPLACE FUNCTION admin_list_users()
RETURNS TABLE(
  id uuid,
  email text,
  display_name text,
  created_at timestamptz,
  last_sign_in_at timestamptz,
  email_confirmed boolean,
  mfa_enrolled boolean,
  is_core boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT current_is_admin() THEN
    RAISE EXCEPTION 'Not authorized.';
  END IF;
  RETURN QUERY
  SELECT
    u.id,
    u.email::text,
    p.display_name,
    u.created_at,
    u.last_sign_in_at,
    (u.email_confirmed_at IS NOT NULL) AS email_confirmed,
    EXISTS(SELECT 1 FROM auth.mfa_factors f WHERE f.user_id = u.id AND f.status = 'verified') AS mfa_enrolled,
    COALESCE(p.is_core_member, false) AS is_core
  FROM auth.users u
  LEFT JOIN profiles p ON p.id = u.id
  ORDER BY u.created_at ASC;
END;
$$;
GRANT EXECUTE ON FUNCTION admin_list_users() TO authenticated;

-- Directly sets a user's password (bcrypt, matching Supabase's own hashing)
-- without needing the user's current password or email access — the
-- intended recovery path when someone is fully locked out.
CREATE OR REPLACE FUNCTION admin_reset_user_password(target_user_id uuid, new_password text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT current_is_admin() THEN
    RAISE EXCEPTION 'Not authorized.';
  END IF;
  IF new_password IS NULL OR length(new_password) < 6 THEN
    RAISE EXCEPTION 'Password must be at least 6 characters.';
  END IF;
  UPDATE auth.users
  SET encrypted_password = crypt(new_password, gen_salt('bf')), updated_at = now()
  WHERE id = target_user_id;
END;
$$;
GRANT EXECUTE ON FUNCTION admin_reset_user_password(uuid, text) TO authenticated;

-- Marks a stuck "unconfirmed" account as confirmed so they can sign in.
CREATE OR REPLACE FUNCTION admin_confirm_user_email(target_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT current_is_admin() THEN
    RAISE EXCEPTION 'Not authorized.';
  END IF;
  UPDATE auth.users
  SET email_confirmed_at = COALESCE(email_confirmed_at, now())
  WHERE id = target_user_id;
END;
$$;
GRANT EXECUTE ON FUNCTION admin_confirm_user_email(uuid) TO authenticated;

-- Removes all MFA factors for a user — recovery path for a lost authenticator
-- app/device (their next sign-in will not be challenged for a code).
CREATE OR REPLACE FUNCTION admin_disable_user_mfa(target_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT current_is_admin() THEN
    RAISE EXCEPTION 'Not authorized.';
  END IF;
  DELETE FROM auth.mfa_factors WHERE user_id = target_user_id;
END;
$$;
GRANT EXECUTE ON FUNCTION admin_disable_user_mfa(uuid) TO authenticated;

-- Admin-initiated account removal — refuses to ever target the admin itself.
CREATE OR REPLACE FUNCTION admin_delete_user(target_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT current_is_admin() THEN
    RAISE EXCEPTION 'Not authorized.';
  END IF;
  IF is_admin_user(target_user_id) THEN
    RAISE EXCEPTION 'The admin account cannot be deleted.';
  END IF;
  PERFORM _purge_user_data(target_user_id);
END;
$$;
GRANT EXECUTE ON FUNCTION admin_delete_user(uuid) TO authenticated;
