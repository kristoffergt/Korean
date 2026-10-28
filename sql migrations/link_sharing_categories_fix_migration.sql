-- The circle sharing toggles for Articles, Calendar and Courses never saved:
-- link_sharing_settings' category check did not list them, so every write was
-- refused. The SELECT policies on articles, events and courses already read
-- shared_circle_cat(..., 'articles' | 'calendar' | 'courses'); with no row
-- possible they always fell back to shared. This adds the three, matching the
-- client's LINK_CATEGORIES. Idempotent.
alter table public.link_sharing_settings drop constraint if exists link_sharing_settings_category_check;
alter table public.link_sharing_settings add constraint link_sharing_settings_category_check
  check (category = any (array['study_entries', 'books', 'articles', 'job_applications', 'certifications',
                               'grammar_notes', 'course_notes', 'writing_samples', 'recap', 'readiness',
                               'calendar', 'notebook_notes', 'courses']));
