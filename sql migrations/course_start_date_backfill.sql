-- The courses table has never actually had a start_date column, even
-- though the app's JS (addCourse / saveCourseEdit / linkCourseToCalendar)
-- has been reading and writing course.start_date all along. That means the
-- "Start date" field in the course form has silently never been able to
-- save. Add the column first so everything below (and the app itself) can
-- actually work.
ALTER TABLE courses ADD COLUMN IF NOT EXISTS start_date date;

-- Backfill: make sure every course's start date is no earlier than
-- 2026-09-01, aligned to that course's own day of week (day_of_week: 1=Mon
-- ... 5=Fri, matching Postgres ISODOW for Mon-Fri).
--
-- Only touches courses with no start_date, or a start_date before Sept 1 —
-- courses already starting on/after Sept 1 are left untouched.
UPDATE courses
SET start_date = DATE '2026-09-01'
  + ((((day_of_week - EXTRACT(ISODOW FROM DATE '2026-09-01')::int) % 7) + 7) % 7)
WHERE start_date IS NULL OR start_date < DATE '2026-09-01';

-- Re-sync each course's auto-generated weekly calendar block (kind='course',
-- recur_freq='week') to the corrected start_date, so the calendar reflects
-- this without needing to re-save each course from the app.
UPDATE events e
SET event_date = c.start_date
FROM courses c
WHERE e.course_id = c.id AND e.kind = 'course' AND e.recur_freq = 'week';

-- Sanity check: show the resulting start dates.
SELECT id, title, day_of_week, start_date FROM courses ORDER BY start_date;
