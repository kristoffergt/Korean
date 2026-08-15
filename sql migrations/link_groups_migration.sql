-- ============================================================================
-- Generalized multi-user linking system.
--
-- Kristoffer & Roxy keep working exactly as before (the `is_core_member`
-- flag + `is_core_member()`/`shared_circle()` helpers from
-- privacy_rls_migration.sql are untouched and still give them blanket,
-- non-toggleable shared-everything access to each other) — per instruction,
-- treat them as "already fully linked."
--
-- Everyone else can now form their own link group (up to 10 accepted
-- members) via an invite/accept flow, and each member independently
-- controls, per data category, whether THEY expose their own data to the
-- rest of their group (opt-out model: sharing defaults to on once linked).
--
-- Scope: this generalizes the SHARED-READ personal-log visibility (study
-- entries, books, job applications, grammar notes, course notes, writing
-- samples/feedback, weekly-monthly recap, grammar readiness) and the
-- "still visible to your own circle even if hidden from leaderboards"
-- override. It deliberately does NOT extend the joint-calendar "assign
-- this event to my partner" / shared courses / synced daily-goal
-- conveniences beyond Kristoffer & Roxy — those are inherently two-person
-- UI concepts (a single partner dropdown, one shared goal) that would need
-- their own redesign to generalize to a group of up to 10, and weren't
-- part of the original ask.
--
-- One active group per user at a time, so sharing settings are simply
-- per-user-per-category rather than per-group-per-category.
--
-- All writes to link_groups / link_group_members go through the RPC
-- functions below (SECURITY DEFINER, bypass RLS) so invite/accept/cap
-- semantics can't be bypassed by a raw client insert — same pattern as the
-- admin RPCs in account_admin_migration.sql. There are deliberately no
-- client-facing INSERT/UPDATE/DELETE policies on those two tables.
--
-- Safe to re-run. Run after privacy_rls_migration.sql and
-- new_features_migration.sql (writing_samples must already exist).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS link_groups (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text,
  created_by uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- One row per user, total — a user can only ever be pending/accepted in a
-- single group at once, which is what makes "settings are per-user, not
-- per-group" a safe simplification.
CREATE TABLE IF NOT EXISTS link_group_members (
  user_id uuid PRIMARY KEY,
  group_id uuid NOT NULL REFERENCES link_groups(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','accepted','declined')),
  invited_by uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  responded_at timestamptz
);

-- target_user_id = user_id itself is the sentinel for "my default setting,
-- used for anyone without a specific override" (can't use NULL here since
-- primary-key columns can't be NULL). A row where target_user_id is some
-- OTHER linked person's id is a per-partner override of that default —
-- what the "gear icon next to their name" in the UI writes to.
CREATE TABLE IF NOT EXISTS link_sharing_settings (
  user_id uuid NOT NULL,
  target_user_id uuid NOT NULL,
  category text NOT NULL CHECK (category IN (
    'study_entries','books','job_applications','grammar_notes',
    'course_notes','writing_samples','recap','readiness'
  )),
  enabled boolean NOT NULL DEFAULT true,
  PRIMARY KEY (user_id, target_user_id, category)
);

-- Upgrade path for the earlier version of this migration, which created
-- link_sharing_settings with PRIMARY KEY (user_id, category) and no
-- target_user_id column. CREATE TABLE IF NOT EXISTS above is a no-op
-- against an already-existing old-shaped table, so this block detects that
-- case and migrates it in place: add the column, backfill every existing
-- row as its owner's own default (target_user_id = user_id, matching what
-- those rows meant before per-partner overrides existed), then widen the
-- primary key. No-op if the table is already in the new shape or brand new.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'link_sharing_settings')
     AND NOT EXISTS (
       SELECT 1 FROM information_schema.columns
       WHERE table_name = 'link_sharing_settings' AND column_name = 'target_user_id'
     ) THEN
    ALTER TABLE link_sharing_settings ADD COLUMN target_user_id uuid;
    UPDATE link_sharing_settings SET target_user_id = user_id WHERE target_user_id IS NULL;
    ALTER TABLE link_sharing_settings ALTER COLUMN target_user_id SET NOT NULL;
    ALTER TABLE link_sharing_settings DROP CONSTRAINT IF EXISTS link_sharing_settings_pkey;
    ALTER TABLE link_sharing_settings ADD PRIMARY KEY (user_id, target_user_id, category);
  END IF;
END $$;

ALTER TABLE link_groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE link_group_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE link_sharing_settings ENABLE ROW LEVEL SECURITY;

-- ---------------------------------------------------------------------------
-- Helper functions
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION linked_group_id(uid uuid)
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT group_id FROM link_group_members WHERE user_id = uid AND status = 'accepted';
$$;

CREATE OR REPLACE FUNCTION is_linked(a uuid, b uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT a IS NOT NULL AND b IS NOT NULL AND a <> b
    AND linked_group_id(a) IS NOT NULL
    AND linked_group_id(a) = linked_group_id(b);
$$;

-- Blanket "are these two people in the same circle at all" check, used
-- where no per-category distinction is needed (e.g. the leaderboard
-- hide-from-strangers override). Redefines the existing function from
-- privacy_rls_migration.sql to also cover link groups; the K&R
-- is_core_member path is untouched and still always wins.
CREATE OR REPLACE FUNCTION shared_circle(a uuid, b uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT a IS NOT NULL AND b IS NOT NULL AND (
    a = b
    OR (is_core_member(a) AND is_core_member(b))
    OR is_linked(a, b)
  );
$$;

-- Category-aware visibility: can `a` see `b`'s data in category `cat`?
-- Kristoffer & Roxy share everything with each other, no toggles. For link
-- group members, `b`'s per-partner override for `a` wins if one exists,
-- otherwise `b`'s own default (target_user_id = b) applies, otherwise it
-- defaults to shared (missing rows = on).
CREATE OR REPLACE FUNCTION shared_circle_cat(a uuid, b uuid, cat text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT a IS NOT NULL AND b IS NOT NULL AND (
    a = b
    OR (is_core_member(a) AND is_core_member(b))
    OR (
      is_linked(a, b)
      AND COALESCE(
        (SELECT enabled FROM link_sharing_settings WHERE user_id = b AND target_user_id = a AND category = cat),
        (SELECT enabled FROM link_sharing_settings WHERE user_id = b AND target_user_id = b AND category = cat),
        true
      )
    )
  );
$$;

-- ---------------------------------------------------------------------------
-- link_groups / link_group_members RLS (read-only for clients; all writes
-- happen via the RPCs below)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "link_groups_select" ON link_groups;
CREATE POLICY "link_groups_select" ON link_groups FOR SELECT
  TO authenticated
  USING (id = linked_group_id(auth.uid()) OR created_by = auth.uid());

DROP POLICY IF EXISTS "link_group_members_select" ON link_group_members;
CREATE POLICY "link_group_members_select" ON link_group_members FOR SELECT
  TO authenticated
  USING (
    user_id = auth.uid()
    OR group_id = linked_group_id(auth.uid())
  );

-- ---------------------------------------------------------------------------
-- link_sharing_settings — you manage your own row; groupmates (and
-- yourself) can read the settings so the app can explain/show what's
-- shared, and so client-side views (recap, readiness) can filter correctly.
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "link_sharing_settings_select" ON link_sharing_settings;
CREATE POLICY "link_sharing_settings_select" ON link_sharing_settings FOR SELECT
  TO authenticated
  USING (user_id = auth.uid() OR is_linked(auth.uid(), user_id));

DROP POLICY IF EXISTS "link_sharing_settings_upsert" ON link_sharing_settings;
CREATE POLICY "link_sharing_settings_upsert" ON link_sharing_settings FOR INSERT
  TO authenticated
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "link_sharing_settings_update" ON link_sharing_settings;
CREATE POLICY "link_sharing_settings_update" ON link_sharing_settings FOR UPDATE
  TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- RPCs: invite / accept / decline / leave
-- ---------------------------------------------------------------------------

-- Invite `invitee_id` into my group (creating one for myself first if I
-- don't already have one). Rejects if the invitee is already
-- pending/accepted somewhere, or if my group is already at the 10-member
-- cap.
CREATE OR REPLACE FUNCTION link_invite(invitee_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  me uuid := auth.uid();
  my_group uuid;
  existing_status text;
  member_count integer;
BEGIN
  IF me IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF invitee_id IS NULL OR invitee_id = me THEN
    RAISE EXCEPTION 'Invalid invitee';
  END IF;

  SELECT status INTO existing_status FROM link_group_members WHERE user_id = invitee_id;
  IF existing_status IN ('pending', 'accepted') THEN
    RAISE EXCEPTION 'That person is already linked or has a pending invite';
  END IF;

  my_group := linked_group_id(me);
  IF my_group IS NULL THEN
    -- Also allow re-inviting from a group I created but haven't joined as
    -- accepted yet (shouldn't normally happen since the creator is
    -- auto-accepted below), otherwise start a brand new group.
    SELECT group_id INTO my_group FROM link_group_members WHERE user_id = me AND status = 'pending';
    IF my_group IS NULL THEN
      INSERT INTO link_groups (created_by) VALUES (me) RETURNING id INTO my_group;
      INSERT INTO link_group_members (user_id, group_id, status, invited_by, responded_at)
        VALUES (me, my_group, 'accepted', me, now());
    END IF;
  END IF;

  SELECT COUNT(*) INTO member_count FROM link_group_members
    WHERE group_id = my_group AND status = 'accepted';
  IF member_count >= 10 THEN
    RAISE EXCEPTION 'Your link group is already at the 10-member limit';
  END IF;

  INSERT INTO link_group_members (user_id, group_id, status, invited_by)
    VALUES (invitee_id, my_group, 'pending', me)
    ON CONFLICT (user_id) DO UPDATE
      SET group_id = EXCLUDED.group_id, status = 'pending', invited_by = EXCLUDED.invited_by,
          created_at = now(), responded_at = NULL;
END;
$$;
GRANT EXECUTE ON FUNCTION link_invite(uuid) TO authenticated;

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
  UPDATE link_group_members SET status = 'accepted', responded_at = now() WHERE user_id = me;
END;
$$;
GRANT EXECUTE ON FUNCTION link_accept_invite() TO authenticated;

CREATE OR REPLACE FUNCTION link_decline_invite()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  me uuid := auth.uid();
BEGIN
  UPDATE link_group_members SET status = 'declined', responded_at = now()
    WHERE user_id = me AND status = 'pending';
END;
$$;
GRANT EXECUTE ON FUNCTION link_decline_invite() TO authenticated;

-- Leave your current group entirely (works whether accepted or still
-- pending, so a sent-but-unwanted invite can also be cancelled by the
-- invitee, and an accepted member can walk away any time).
CREATE OR REPLACE FUNCTION link_leave_group()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  me uuid := auth.uid();
BEGIN
  DELETE FROM link_group_members WHERE user_id = me;
END;
$$;
GRANT EXECUTE ON FUNCTION link_leave_group() TO authenticated;

-- Lookup used by the invite picker: search existing profiles by
-- display-name substring, excluding yourself and anyone already
-- pending/accepted somewhere. display_name is already globally readable
-- (profiles_select_all), so this exposes nothing new.
CREATE OR REPLACE FUNCTION link_search_users(query text)
RETURNS TABLE(id uuid, display_name text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT p.id, p.display_name
  FROM profiles p
  WHERE p.id <> auth.uid()
    AND p.display_name ILIKE '%' || query || '%'
    AND NOT EXISTS (
      SELECT 1 FROM link_group_members m
      WHERE m.user_id = p.id AND m.status IN ('pending','accepted')
    )
  ORDER BY p.display_name
  LIMIT 20;
$$;
GRANT EXECUTE ON FUNCTION link_search_users(text) TO authenticated;

-- ---------------------------------------------------------------------------
-- Regenerate the shared-read SELECT policies on the existing personal-log
-- tables to use the category-aware check instead of the blanket one, so
-- each linked member's per-category toggle is actually honored. (INSERT/
-- UPDATE/DELETE policies on these tables are unchanged — still own-only —
-- so they are not repeated here.)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "study_entries_select" ON study_entries;
CREATE POLICY "study_entries_select" ON study_entries FOR SELECT
  TO authenticated
  USING (shared_circle_cat(auth.uid(), user_id, 'study_entries'));

DROP POLICY IF EXISTS "books_select" ON books;
CREATE POLICY "books_select" ON books FOR SELECT
  TO authenticated
  USING (shared_circle_cat(auth.uid(), user_id, 'books'));

DROP POLICY IF EXISTS "job_applications_select" ON job_applications;
CREATE POLICY "job_applications_select" ON job_applications FOR SELECT
  TO authenticated
  USING (shared_circle_cat(auth.uid(), user_id, 'job_applications'));

DROP POLICY IF EXISTS "grammar_notes_select" ON grammar_notes;
CREATE POLICY "grammar_notes_select" ON grammar_notes FOR SELECT
  TO authenticated
  USING (shared_circle_cat(auth.uid(), user_id, 'grammar_notes'));

DROP POLICY IF EXISTS "course_notes_select" ON course_notes;
CREATE POLICY "course_notes_select" ON course_notes FOR SELECT
  TO authenticated
  USING (shared_circle_cat(auth.uid(), user_id, 'course_notes'));

DROP POLICY IF EXISTS "writing_samples_select" ON writing_samples;
CREATE POLICY "writing_samples_select" ON writing_samples FOR SELECT
  TO authenticated
  USING (shared_circle_cat(auth.uid(), user_id, 'writing_samples'));

-- ---------------------------------------------------------------------------
-- Writing feedback / comments — limited to people who are linked with (or
-- core-member-paired with) the sample's owner AND whom the owner still has
-- 'writing_samples' sharing switched on for (same gate as seeing the
-- sample itself). Own samples are always visible to their owner regardless
-- of category toggles.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS writing_feedback (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sample_id uuid NOT NULL REFERENCES writing_samples(id) ON DELETE CASCADE,
  author_id uuid NOT NULL,
  content text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE writing_feedback ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "writing_feedback_select" ON writing_feedback;
CREATE POLICY "writing_feedback_select" ON writing_feedback FOR SELECT
  TO authenticated
  USING (
    author_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM writing_samples ws
      WHERE ws.id = sample_id
        AND (ws.user_id = auth.uid() OR shared_circle_cat(auth.uid(), ws.user_id, 'writing_samples'))
    )
  );

DROP POLICY IF EXISTS "writing_feedback_insert" ON writing_feedback;
CREATE POLICY "writing_feedback_insert" ON writing_feedback FOR INSERT
  TO authenticated
  WITH CHECK (
    author_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM writing_samples ws
      WHERE ws.id = sample_id
        AND (ws.user_id = auth.uid() OR shared_circle_cat(auth.uid(), ws.user_id, 'writing_samples'))
    )
  );

DROP POLICY IF EXISTS "writing_feedback_update" ON writing_feedback;
CREATE POLICY "writing_feedback_update" ON writing_feedback FOR UPDATE
  TO authenticated
  USING (author_id = auth.uid())
  WITH CHECK (author_id = auth.uid());

DROP POLICY IF EXISTS "writing_feedback_delete" ON writing_feedback;
CREATE POLICY "writing_feedback_delete" ON writing_feedback FOR DELETE
  TO authenticated
  USING (author_id = auth.uid());
