-- ============================================================================
-- Lets the admin edit anyone's self-logged study hours from the moderator
-- panel (task: "Should let moderators edit the self tracked leaderboard stuff
-- like Korean study times"). study_entries is own-write under RLS
-- (privacy_rls_migration.sql), and the admin is not in every account's
-- circle, so the read and both writes go through SECURITY DEFINER functions
-- here. Same pattern as admin_update_display_name_migration.sql: the
-- current_is_admin() gate, a pinned search_path, executable by authenticated
-- only (the caller still has to BE the admin to get past the gate).
--
-- The write re-validates what the client already checks, because this is the
-- actual enforcement point: an object of known activity keys mapped to
-- non-negative numbers. Zero-hour activities are dropped, and a day left with
-- none is DELETED rather than stored as {} -- which is what the app's own
-- delete path does (deleteMyDay), so a row with no hours never exists.
--
-- No cap on a day's total: the app's own logger has none, and live rows
-- already hold more than 24 hours on a single activity, so a cap here would
-- stop the admin saving a day unchanged. 1000 per activity only rejects a
-- typo that grew a few zeroes.
--
-- Safe to re-run.
-- ============================================================================

CREATE OR REPLACE FUNCTION admin_list_study_entries(target_user_id uuid)
RETURNS TABLE(entry_date date, activities jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT current_is_admin() THEN
    RAISE EXCEPTION 'Not authorized.';
  END IF;
  RETURN QUERY
  SELECT se.entry_date, se.activities
  FROM study_entries se
  WHERE se.user_id = target_user_id
  ORDER BY se.entry_date DESC;
END;
$$;

CREATE OR REPLACE FUNCTION admin_set_study_entry(target_user_id uuid, target_date date, new_activities jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  k text;
  v jsonb;
  hrs numeric;
  cleaned jsonb := '{}'::jsonb;
BEGIN
  IF NOT current_is_admin() THEN
    RAISE EXCEPTION 'Not authorized.';
  END IF;
  IF target_user_id IS NULL OR target_date IS NULL THEN
    RAISE EXCEPTION 'An account and a date are required.';
  END IF;
  IF new_activities IS NULL OR jsonb_typeof(new_activities) <> 'object' THEN
    RAISE EXCEPTION 'Activities must be an object.';
  END IF;
  FOR k, v IN SELECT * FROM jsonb_each(new_activities) LOOP
    IF k NOT IN ('listening','speaking','reading','writing','grammar','vocabulary','topik','other') THEN
      RAISE EXCEPTION 'Unknown activity: %', k;
    END IF;
    IF jsonb_typeof(v) <> 'number' THEN
      RAISE EXCEPTION 'Hours for % must be a number.', k;
    END IF;
    hrs := (v #>> '{}')::numeric;
    IF hrs < 0 OR hrs > 1000 THEN
      RAISE EXCEPTION 'Hours for % are out of range.', k;
    END IF;
    IF hrs > 0 THEN
      cleaned := cleaned || jsonb_build_object(k, hrs);
    END IF;
  END LOOP;
  IF cleaned = '{}'::jsonb THEN
    DELETE FROM study_entries WHERE user_id = target_user_id AND entry_date = target_date;
    RETURN;
  END IF;
  INSERT INTO study_entries (user_id, entry_date, activities)
  VALUES (target_user_id, target_date, cleaned)
  ON CONFLICT (user_id, entry_date) DO UPDATE SET activities = EXCLUDED.activities;
END;
$$;

CREATE OR REPLACE FUNCTION admin_delete_study_entry(target_user_id uuid, target_date date)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT current_is_admin() THEN
    RAISE EXCEPTION 'Not authorized.';
  END IF;
  DELETE FROM study_entries WHERE user_id = target_user_id AND entry_date = target_date;
END;
$$;

-- Supabase auto-grants EXECUTE to anon on every new function by default (a
-- database-level default privilege, independent of the GRANT below), so the
-- explicit REVOKE is what actually keeps these authenticated-only -- same as
-- admin_update_display_name_migration.sql.
REVOKE EXECUTE ON FUNCTION admin_list_study_entries(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION admin_list_study_entries(uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION admin_set_study_entry(uuid, date, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION admin_set_study_entry(uuid, date, jsonb) TO authenticated;
REVOKE EXECUTE ON FUNCTION admin_delete_study_entry(uuid, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION admin_delete_study_entry(uuid, date) TO authenticated;
