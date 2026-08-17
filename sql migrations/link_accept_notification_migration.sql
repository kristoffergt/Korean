-- ============================================================================
-- Lets the inviter see, in the Linked Circle panel itself, that someone they
-- invited has accepted -- not just a status change they'd have to notice on
-- their own. Reuses the existing "linkNotifyDot" affordance client-side
-- (already used for "you have a pending invite") for "someone accepted your
-- invite" too, plus an inline badge in the roster row.
--
-- accept_notified defaults true so this backfills every existing accepted
-- row as already-seen (no retroactive notification flood for K&R or anyone
-- already linked) -- link_accept_invite() explicitly flips it to false the
-- moment a NEW acceptance happens, which is the only case that should light
-- up the notification.
--
-- Safe to re-run.
-- ============================================================================

ALTER TABLE link_group_members ADD COLUMN IF NOT EXISTS accept_notified boolean NOT NULL DEFAULT true;

CREATE OR REPLACE FUNCTION link_accept_invite()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  me uuid := auth.uid();
  my_group uuid;
  member_count integer;
BEGIN
  SELECT group_id INTO my_group FROM link_group_members WHERE user_id = me AND status = 'pending';
  IF my_group IS NULL THEN
    RAISE EXCEPTION 'No pending invite to accept';
  END IF;
  SELECT COUNT(*) INTO member_count FROM link_group_members
    WHERE group_id = my_group AND status = 'accepted';
  IF member_count >= 10 THEN
    RAISE EXCEPTION 'That link group is already at the 10-member limit';
  END IF;
  UPDATE link_group_members SET status = 'accepted', responded_at = now(), accept_notified = false WHERE user_id = me;
END;
$$;
GRANT EXECUTE ON FUNCTION link_accept_invite() TO authenticated;

-- Called by the inviter once they've seen the "accepted" badge for a given
-- member, so it doesn't keep showing on every future visit. Scoped to rows
-- this caller actually invited -- link_group_members has no client UPDATE
-- policy at all (every write goes through a SECURITY DEFINER RPC), so this
-- is the only path to clear it.
CREATE OR REPLACE FUNCTION link_dismiss_accept_notice(member_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE link_group_members
  SET accept_notified = true
  WHERE user_id = member_user_id AND invited_by = auth.uid() AND status = 'accepted';
END;
$$;
REVOKE EXECUTE ON FUNCTION link_dismiss_accept_notice(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION link_dismiss_accept_notice(uuid) TO authenticated;
