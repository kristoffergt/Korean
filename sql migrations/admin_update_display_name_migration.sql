-- ============================================================================
-- Lets the admin change any user's display name from the moderator panel
-- (task: "Allow admins to change people's display names"). Mirrors the
-- existing admin_reset_user_password / admin_confirm_user_email pattern in
-- account_admin_migration.sql: SECURITY DEFINER, current_is_admin() gate,
-- pinned search_path, executable only by authenticated (the client still
-- has to be the admin to get past current_is_admin()).
--
-- Re-validates length/character rules and uniqueness server-side too, since
-- the client-side checks in index.html are just UX -- this RPC is the actual
-- enforcement point, same as display_name_available is for signup.
--
-- Safe to re-run.
-- ============================================================================

CREATE OR REPLACE FUNCTION admin_update_display_name(target_user_id uuid, new_name text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  trimmed text := trim(new_name);
BEGIN
  IF NOT current_is_admin() THEN
    RAISE EXCEPTION 'Not authorized.';
  END IF;
  IF trimmed = '' THEN
    RAISE EXCEPTION 'Name cannot be empty.';
  END IF;
  IF length(trimmed) > 12 THEN
    RAISE EXCEPTION 'Name must be 12 characters or fewer.';
  END IF;
  IF trimmed !~ '^[[:alnum:] ''-]+$' THEN
    RAISE EXCEPTION 'Name contains invalid characters.';
  END IF;
  IF EXISTS (
    SELECT 1 FROM profiles
    WHERE lower(display_name) = lower(trimmed) AND id <> target_user_id
  ) THEN
    RAISE EXCEPTION 'That display name is already taken.';
  END IF;
  UPDATE profiles SET display_name = trimmed WHERE id = target_user_id;
END;
$$;
-- Supabase auto-grants EXECUTE to anon on every new function by default
-- (a database-level default privilege, independent of the GRANT below) --
-- explicit REVOKE is required to actually keep this authenticated-only,
-- same pattern as yonsei_security_definer_hardening_migration.sql.
REVOKE EXECUTE ON FUNCTION admin_update_display_name(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION admin_update_display_name(uuid, text) TO authenticated;
