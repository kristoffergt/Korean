-- ============================================================================
-- "Remove people from your circle" -- link_leave_group() only ever lets you
-- remove *yourself*; there was no way to remove someone else you're linked
-- with (or un-invite a pending invite you sent) without them leaving first.
--
-- Any accepted member of a group can remove any other member of that same
-- group (accepted or still-pending) -- the group has no single "owner"
-- concept, it's a flat circle, so this mirrors link_leave_group()'s
-- same-group check rather than restricting to whoever created it.
--
-- Safe to re-run.
-- ============================================================================

CREATE OR REPLACE FUNCTION link_remove_member(target_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  me uuid := auth.uid();
  my_group uuid;
  target_group uuid;
BEGIN
  IF me IS NULL OR target_id IS NULL OR target_id = me THEN
    RAISE EXCEPTION 'Invalid request';
  END IF;
  my_group := linked_group_id(me);
  IF my_group IS NULL THEN
    RAISE EXCEPTION 'You are not in a circle';
  END IF;
  SELECT group_id INTO target_group FROM link_group_members WHERE user_id = target_id;
  IF target_group IS NULL OR target_group <> my_group THEN
    RAISE EXCEPTION 'That person is not in your circle';
  END IF;
  DELETE FROM link_group_members WHERE user_id = target_id;
  DELETE FROM link_sharing_settings WHERE (user_id = me AND target_user_id = target_id) OR (user_id = target_id AND target_user_id = me);
END;
$$;
REVOKE EXECUTE ON FUNCTION link_remove_member(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION link_remove_member(uuid) TO authenticated;
