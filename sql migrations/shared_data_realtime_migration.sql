-- Required for the client's subscribeSharedDataRealtime() (index.html) to
-- actually receive postgres_changes events on any of these -- RLS alone
-- doesn't enable Realtime, a table also has to be added to this
-- publication. Covers every shared-circle table besides the calendar
-- notes/job board ones already added earlier (course_notes,
-- notebook_notes, yonsei_jobboard_items).
--
-- Applied live via apply_migration as "shared_data_realtime" -- this file
-- mirrors that for the record.

alter publication supabase_realtime add table public.events;
alter publication supabase_realtime add table public.courses;
alter publication supabase_realtime add table public.study_entries;
alter publication supabase_realtime add table public.job_applications;
alter publication supabase_realtime add table public.certifications;
alter publication supabase_realtime add table public.writing_samples;
alter publication supabase_realtime add table public.books;
alter publication supabase_realtime add table public.grammar_notes;
alter publication supabase_realtime add table public.event_subscriptions;
alter publication supabase_realtime add table public.profiles;
