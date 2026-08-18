-- ============================================================================
-- Replaces the resume bucket's upload/update policies with the exact same
-- shape as job-application-files/note-media/writing-images (own-user-id
-- folder ownership) -- the one pattern in this project that's actually
-- proven to work end-to-end, unlike the admin-check and plain-auth-check
-- variants tried first. The object path becomes {uid}/resume.pdf instead
-- of a flat resume.pdf; the public resume page's PDF link is updated to
-- match (hardcoded to Kristoffer's uid, since this bucket only ever holds
-- his own public resume).
--
-- Safe to re-run.
-- ============================================================================

drop policy if exists "resume upload signed in" on storage.objects;
create policy "resume upload own folder" on storage.objects for insert
  to authenticated
  with check (bucket_id = 'resume' and (storage.foldername(name))[1] = (auth.uid())::text);

drop policy if exists "resume update signed in" on storage.objects;
create policy "resume update own folder" on storage.objects for update
  to authenticated
  using (bucket_id = 'resume' and (storage.foldername(name))[1] = (auth.uid())::text);
