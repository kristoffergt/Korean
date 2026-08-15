-- ============================================================================
-- Privacy / Row Level Security migration
--
-- Problem: the app currently fetches every table with `select('*')` and no
-- server-side filtering. The UI only *displays* "your" rows, but the full
-- dataset (every user's job applications, books, grammar sentences, study
-- log, etc.) is downloaded into the browser for ANY signed-in account,
-- including a brand-new third-party signup. That data is visible to anyone
-- who opens devtools, regardless of what the UI chooses to render.
--
-- Fix: enable Postgres Row Level Security so the database itself only ever
-- returns rows a user is allowed to see. Rule used throughout:
--   - You can always see/write your own rows.
--   - You and another "core member" (Roxy + Kristoffer, i.e. profiles with
--     is_core_member = true) can see each other's rows in the tables that
--     are meant to be a shared couple's tracker (calendar/courses) or
--     shared-read (books, jobs, grammar sentences, study log).
--   - Anyone who is NOT a core member (e.g. a curious third signup) can only
--     ever see/write their own rows, never Roxy's or Kristoffer's.
--   - Personal-log tables (books, job_applications, grammar_notes,
--     study_entries, course_notes) are shared READ but OWN-ONLY write,
--     matching the "isMine" edit-button gating already in the app's UI.
--   - Joint-calendar tables (events, event_subscriptions, courses) are
--     shared read AND shared write, matching the app's existing "assign to
--     [other core member]" / shared_with UI.
--   - grammar_points is global reference content: readable by anyone signed
--     in, but NOT writable by the client at all (you already maintain it
--     yourself via the SQL editor, which runs as the Postgres role and
--     bypasses RLS entirely — this migration does not affect that workflow).
--
-- Safe to re-run: uses IF NOT EXISTS / DROP POLICY IF EXISTS throughout.
-- Running this from the Supabase SQL editor uses the Postgres role, which
-- bypasses RLS, so it will not lock you out of your own editor.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Helper functions
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION is_core_member(uid uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE((SELECT p.is_core_member FROM profiles p WHERE p.id = uid), false);
$$;

CREATE OR REPLACE FUNCTION shared_circle(a uuid, b uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT a IS NOT NULL AND b IS NOT NULL AND (a = b OR (is_core_member(a) AND is_core_member(b)));
$$;

-- Used to stop a user from escalating their own is_core_member flag.
CREATE OR REPLACE FUNCTION current_is_core_member()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE((SELECT p.is_core_member FROM profiles p WHERE p.id = auth.uid()), false);
$$;

-- ---------------------------------------------------------------------------
-- profiles
-- Readable by anyone signed in (needed so the app can resolve display names
-- for shared UI). Writable only for your own row, and you may never set
-- your own is_core_member flag — that's only ever set by hand via the SQL
-- editor for Roxy & Kristoffer's two accounts.
-- ---------------------------------------------------------------------------
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "profiles_select_all" ON profiles;
CREATE POLICY "profiles_select_all" ON profiles FOR SELECT
  TO authenticated
  USING (true);

DROP POLICY IF EXISTS "profiles_insert_own" ON profiles;
CREATE POLICY "profiles_insert_own" ON profiles FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = id AND is_core_member IS NOT TRUE);

DROP POLICY IF EXISTS "profiles_update_own" ON profiles;
CREATE POLICY "profiles_update_own" ON profiles FOR UPDATE
  TO authenticated
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id AND is_core_member = current_is_core_member());

-- ---------------------------------------------------------------------------
-- study_entries — shared read within the core circle, own-only write.
-- ---------------------------------------------------------------------------
ALTER TABLE study_entries ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "study_entries_select" ON study_entries;
CREATE POLICY "study_entries_select" ON study_entries FOR SELECT
  TO authenticated
  USING (shared_circle(auth.uid(), user_id));

DROP POLICY IF EXISTS "study_entries_insert" ON study_entries;
CREATE POLICY "study_entries_insert" ON study_entries FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "study_entries_update" ON study_entries;
CREATE POLICY "study_entries_update" ON study_entries FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "study_entries_delete" ON study_entries;
CREATE POLICY "study_entries_delete" ON study_entries FOR DELETE
  TO authenticated
  USING (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- books (reading list) — shared read within the core circle, own-only write.
-- ---------------------------------------------------------------------------
ALTER TABLE books ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "books_select" ON books;
CREATE POLICY "books_select" ON books FOR SELECT
  TO authenticated
  USING (shared_circle(auth.uid(), user_id));

DROP POLICY IF EXISTS "books_insert" ON books;
CREATE POLICY "books_insert" ON books FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "books_update" ON books;
CREATE POLICY "books_update" ON books FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "books_delete" ON books;
CREATE POLICY "books_delete" ON books FOR DELETE
  TO authenticated
  USING (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- job_applications — shared read within the core circle, own-only write.
-- ---------------------------------------------------------------------------
ALTER TABLE job_applications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "job_applications_select" ON job_applications;
CREATE POLICY "job_applications_select" ON job_applications FOR SELECT
  TO authenticated
  USING (shared_circle(auth.uid(), user_id));

DROP POLICY IF EXISTS "job_applications_insert" ON job_applications;
CREATE POLICY "job_applications_insert" ON job_applications FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "job_applications_update" ON job_applications;
CREATE POLICY "job_applications_update" ON job_applications FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "job_applications_delete" ON job_applications;
CREATE POLICY "job_applications_delete" ON job_applications FOR DELETE
  TO authenticated
  USING (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- grammar_notes (practice sentences added under grammar points) — shared
-- read within the core circle, own-only write.
-- ---------------------------------------------------------------------------
ALTER TABLE grammar_notes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "grammar_notes_select" ON grammar_notes;
CREATE POLICY "grammar_notes_select" ON grammar_notes FOR SELECT
  TO authenticated
  USING (shared_circle(auth.uid(), user_id));

DROP POLICY IF EXISTS "grammar_notes_insert" ON grammar_notes;
CREATE POLICY "grammar_notes_insert" ON grammar_notes FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "grammar_notes_update" ON grammar_notes;
CREATE POLICY "grammar_notes_update" ON grammar_notes FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "grammar_notes_delete" ON grammar_notes;
CREATE POLICY "grammar_notes_delete" ON grammar_notes FOR DELETE
  TO authenticated
  USING (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- events (shared joint calendar) — shared read/write within the core
-- circle, matching the existing "assign this event to [other core member]"
-- UI.
-- ---------------------------------------------------------------------------
ALTER TABLE events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "events_select" ON events;
CREATE POLICY "events_select" ON events FOR SELECT
  TO authenticated
  USING (
    auth.uid() = user_id
    OR (shared_circle(auth.uid(), user_id) AND COALESCE(is_private, false) = false)
  );

DROP POLICY IF EXISTS "events_insert" ON events;
CREATE POLICY "events_insert" ON events FOR INSERT
  TO authenticated
  WITH CHECK (shared_circle(auth.uid(), user_id));

DROP POLICY IF EXISTS "events_update" ON events;
CREATE POLICY "events_update" ON events FOR UPDATE
  TO authenticated
  USING (shared_circle(auth.uid(), user_id))
  WITH CHECK (shared_circle(auth.uid(), user_id));

DROP POLICY IF EXISTS "events_delete" ON events;
CREATE POLICY "events_delete" ON events FOR DELETE
  TO authenticated
  USING (shared_circle(auth.uid(), user_id));

-- ---------------------------------------------------------------------------
-- event_subscriptions (per-person reminder prefs for a shared event) —
-- shared within the core circle (event creation subscribes both of you).
-- ---------------------------------------------------------------------------
ALTER TABLE event_subscriptions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "event_subscriptions_select" ON event_subscriptions;
CREATE POLICY "event_subscriptions_select" ON event_subscriptions FOR SELECT
  TO authenticated
  USING (shared_circle(auth.uid(), user_id));

DROP POLICY IF EXISTS "event_subscriptions_insert" ON event_subscriptions;
CREATE POLICY "event_subscriptions_insert" ON event_subscriptions FOR INSERT
  TO authenticated
  WITH CHECK (shared_circle(auth.uid(), user_id));

DROP POLICY IF EXISTS "event_subscriptions_update" ON event_subscriptions;
CREATE POLICY "event_subscriptions_update" ON event_subscriptions FOR UPDATE
  TO authenticated
  USING (shared_circle(auth.uid(), user_id))
  WITH CHECK (shared_circle(auth.uid(), user_id));

DROP POLICY IF EXISTS "event_subscriptions_delete" ON event_subscriptions;
CREATE POLICY "event_subscriptions_delete" ON event_subscriptions FOR DELETE
  TO authenticated
  USING (shared_circle(auth.uid(), user_id));

-- ---------------------------------------------------------------------------
-- courses — shared read/write within the core circle (honors the existing
-- shared_with column too, in case it's ever used for a non-core-member).
-- ---------------------------------------------------------------------------
ALTER TABLE courses ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "courses_select" ON courses;
CREATE POLICY "courses_select" ON courses FOR SELECT
  TO authenticated
  USING (
    shared_circle(auth.uid(), user_id)
    OR EXISTS (SELECT 1 FROM unnest(shared_with) AS sw WHERE sw::text = auth.uid()::text)
  );

DROP POLICY IF EXISTS "courses_insert" ON courses;
CREATE POLICY "courses_insert" ON courses FOR INSERT
  TO authenticated
  WITH CHECK (
    shared_circle(auth.uid(), user_id)
    OR EXISTS (SELECT 1 FROM unnest(shared_with) AS sw WHERE sw::text = auth.uid()::text)
  );

DROP POLICY IF EXISTS "courses_update" ON courses;
CREATE POLICY "courses_update" ON courses FOR UPDATE
  TO authenticated
  USING (
    shared_circle(auth.uid(), user_id)
    OR EXISTS (SELECT 1 FROM unnest(shared_with) AS sw WHERE sw::text = auth.uid()::text)
  )
  WITH CHECK (
    shared_circle(auth.uid(), user_id)
    OR EXISTS (SELECT 1 FROM unnest(shared_with) AS sw WHERE sw::text = auth.uid()::text)
  );

DROP POLICY IF EXISTS "courses_delete" ON courses;
CREATE POLICY "courses_delete" ON courses FOR DELETE
  TO authenticated
  USING (shared_circle(auth.uid(), user_id));

-- ---------------------------------------------------------------------------
-- course_notes (lecture notes) — shared read within the core circle,
-- own-only write, matching the existing "isMine" edit-button gating.
-- ---------------------------------------------------------------------------
ALTER TABLE course_notes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "course_notes_select" ON course_notes;
CREATE POLICY "course_notes_select" ON course_notes FOR SELECT
  TO authenticated
  USING (shared_circle(auth.uid(), user_id));

DROP POLICY IF EXISTS "course_notes_insert" ON course_notes;
CREATE POLICY "course_notes_insert" ON course_notes FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "course_notes_update" ON course_notes;
CREATE POLICY "course_notes_update" ON course_notes FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "course_notes_delete" ON course_notes;
CREATE POLICY "course_notes_delete" ON course_notes FOR DELETE
  TO authenticated
  USING (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- grammar_points — global reference content. Anyone signed in can read it;
-- nobody can write it through the app (you manage it yourself via the SQL
-- editor, which bypasses RLS since it runs as the Postgres role).
-- ---------------------------------------------------------------------------
ALTER TABLE grammar_points ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "grammar_points_select" ON grammar_points;
CREATE POLICY "grammar_points_select" ON grammar_points FOR SELECT
  TO authenticated
  USING (true);

-- (Deliberately no INSERT/UPDATE/DELETE policy for grammar_points: with RLS
-- enabled and no matching policy, the anon/authenticated client roles are
-- denied by default. Only the SQL editor / service role can write to it.)
