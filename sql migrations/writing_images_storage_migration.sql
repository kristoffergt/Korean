-- ============================================================================
-- Storage bucket for Q53 (data-description) writing task images — lets you
-- attach a real graph/table/chart you found or screenshotted, uploaded from
-- the writing editor, instead of (or alongside) the app's built-in synthetic
-- charts. Mirrors the existing 'syllabi' bucket setup used for course files.
--
-- Safe to re-run.
-- ============================================================================

insert into storage.buckets (id, name, public)
values ('writing-images', 'writing-images', true)
on conflict (id) do nothing;

-- Anyone signed in can upload, but only into a folder named after their own
-- user id (the app always uploads to `${user.id}/...`), and can only
-- delete/replace their own files. Since the bucket is public, reads (i.e.
-- viewing the image in the writing task, including your partner viewing
-- yours) don't need a separate SELECT policy — they go through the public
-- CDN URL, not RLS.
drop policy if exists "writing images upload own" on storage.objects;
create policy "writing images upload own" on storage.objects for insert
  to authenticated
  with check (bucket_id = 'writing-images' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "writing images update own" on storage.objects;
create policy "writing images update own" on storage.objects for update
  to authenticated
  using (bucket_id = 'writing-images' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "writing images delete own" on storage.objects;
create policy "writing images delete own" on storage.objects for delete
  to authenticated
  using (bucket_id = 'writing-images' and (storage.foldername(name))[1] = auth.uid()::text);
