-- ============================================================================
-- upload(..., {upsert:true}) has to check whether the object already
-- exists before deciding insert-vs-update, which is a SELECT under the
-- hood -- and there was no SELECT policy on storage.objects for the resume
-- bucket at all. job-application-files never hit this because its upload
-- calls never pass upsert:true (each file gets a fresh timestamped path
-- instead of overwriting one). Adding the missing own-folder SELECT policy
-- so upsert's existence check actually has something to evaluate.
--
-- Safe to re-run.
-- ============================================================================

drop policy if exists "resume select own folder" on storage.objects;
create policy "resume select own folder" on storage.objects for select
  to authenticated
  using (bucket_id = 'resume' and (storage.foldername(name))[1] = (auth.uid())::text);
