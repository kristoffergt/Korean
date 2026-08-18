-- ============================================================================
-- Drops the current_is_admin() gate on the resume bucket's upload/update
-- policies, requiring only that the caller be signed in (auth.uid() IS NOT
-- NULL) -- same pattern the syllabi bucket already uses. The "Sync resume
-- from PDF" / "Upload PDF" buttons are already hidden from everyone except
-- Kristoffer client-side (inside #moderatorSection), and this is his public
-- resume PDF, not sensitive data, so the extra admin check wasn't buying
-- much real protection -- and it's the one moving part that differs from
-- every other (working) storage policy in this project, worth eliminating
-- as a possible cause of the current upload failures.
--
-- Safe to re-run.
-- ============================================================================

drop policy if exists "resume upload admin only" on storage.objects;
create policy "resume upload signed in" on storage.objects for insert
  to authenticated
  with check (bucket_id = 'resume' and auth.uid() is not null);

drop policy if exists "resume update admin only" on storage.objects;
create policy "resume update signed in" on storage.objects for update
  to authenticated
  using (bucket_id = 'resume' and auth.uid() is not null);
