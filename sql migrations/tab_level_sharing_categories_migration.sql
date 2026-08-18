-- ============================================================================
-- Adds real sharing toggles for the three tabs that had none at all
-- (Calendar, Study > Notebook, Yonsei > Courses) -- previously these three
-- were gated only by the blanket shared_circle() (self, core partner, or
-- any linked circle member, unconditionally, no opt-out). One toggle per
-- tab, per the same "one picker/toggle for the whole tab" convention used
-- everywhere else in the app -- not split further (e.g. Calendar doesn't
-- separate deadlines from events; whichever items you added on that tab
-- are governed by the one 'calendar' category).
--
-- Same pattern as every existing category: wraps the plain shared_circle()
-- check with shared_circle_cat(..., 'category'), which is a strict
-- narrowing for linked (non-core) circle members only -- self-access and
-- the hardcoded core-partner pairing are unaffected (shared_circle_cat()
-- grants those unconditionally, same as shared_circle()). Defaults to
-- enabled when unset, so nobody's current visibility changes until they
-- actively turn a toggle off.
--
-- Safe to re-run.
-- ============================================================================

ALTER POLICY events_select ON events
  USING ((auth.uid() = user_id) OR (shared_circle_cat(auth.uid(), user_id, 'calendar') AND (COALESCE(is_private, false) = false)));

ALTER POLICY courses_select ON courses
  USING (shared_circle_cat(auth.uid(), user_id, 'courses') OR (EXISTS (
    SELECT 1 FROM unnest(courses.shared_with) sw(sw) WHERE ((sw.sw)::text = (auth.uid())::text)
  )));

ALTER POLICY notebook_notes_select ON notebook_notes
  USING (shared_circle_cat(auth.uid(), user_id, 'notebook_notes'));
