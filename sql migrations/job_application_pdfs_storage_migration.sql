-- ============================================================================
-- Storage bucket for resume/cover-letter uploads attached to job
-- applications, viewable in-browser. Mirrors writing-images-storage-migration.sql's
-- own-folder-only pattern exactly. PDF-only is enforced both client-side
-- (file input accept=".pdf,application/pdf" and a MIME check before upload)
-- and here via allowed_mime_types, which Storage itself enforces on upload --
-- a non-PDF file is rejected by Supabase regardless of what the client sends.
--
-- Safe to re-run.
-- ============================================================================

insert into storage.buckets (id, name, public, allowed_mime_types)
values ('job-application-files', 'job-application-files', true, array['application/pdf'])
on conflict (id) do update set allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "job app files upload own" on storage.objects;
create policy "job app files upload own" on storage.objects for insert
  to authenticated
  with check (bucket_id = 'job-application-files' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "job app files update own" on storage.objects;
create policy "job app files update own" on storage.objects for update
  to authenticated
  using (bucket_id = 'job-application-files' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "job app files delete own" on storage.objects;
create policy "job app files delete own" on storage.objects for delete
  to authenticated
  using (bucket_id = 'job-application-files' and (storage.foldername(name))[1] = auth.uid()::text);

-- job_applications gets two nullable URL columns rather than a separate
-- table -- one row per application already has a natural 1:1 with its own
-- resume/cover letter, same shallow shape as courses.syllabus_url.
ALTER TABLE job_applications ADD COLUMN IF NOT EXISTS resume_url text;
ALTER TABLE job_applications ADD COLUMN IF NOT EXISTS resume_name text;
ALTER TABLE job_applications ADD COLUMN IF NOT EXISTS cover_letter_url text;
ALTER TABLE job_applications ADD COLUMN IF NOT EXISTS cover_letter_name text;
