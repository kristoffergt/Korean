-- ============================================================================
-- Storage for the public /resume page (kristoffergt.com/resume -- see
-- resume/index.html, a standalone page with none of the main app's chrome).
--
-- Unlike every other bucket in this app, uploads are NOT own-folder-scoped
-- to auth.uid() -- this is Kristoffer's personal resume, not per-user
-- content, so the upload policy is gated to the admin specifically
-- (current_is_admin(), same helper account_admin_migration.sql's admin_*
-- RPCs use) rather than "whoever is signed in". Always uploaded to the
-- fixed path resume.pdf (overwritten each time), so the public page never
-- needs to know a filename -- just the bucket's public URL for that path.
--
-- Safe to re-run.
-- ============================================================================

insert into storage.buckets (id, name, public, allowed_mime_types)
values ('resume', 'resume', true, array['application/pdf'])
on conflict (id) do update set allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "resume upload admin only" on storage.objects;
create policy "resume upload admin only" on storage.objects for insert
  to authenticated
  with check (bucket_id = 'resume' and current_is_admin());

drop policy if exists "resume update admin only" on storage.objects;
create policy "resume update admin only" on storage.objects for update
  to authenticated
  using (bucket_id = 'resume' and current_is_admin());
