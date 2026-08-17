-- ============================================================================
-- Storage bucket for images embedded inside notes (both Notebook notes and
-- Yonsei course notes, via the Quill editors' image toolbar button).
-- Mirrors writing-images-storage-migration.sql's own-folder-only pattern.
--
-- Video isn't uploaded here -- Quill's built-in video button embeds by URL
-- (e.g. a YouTube link) rather than a file, which is the more practical way
-- to put video in a note anyway (no upload size limits to worry about).
--
-- Safe to re-run.
-- ============================================================================

insert into storage.buckets (id, name, public)
values ('note-media', 'note-media', true)
on conflict (id) do nothing;

drop policy if exists "note media upload own" on storage.objects;
create policy "note media upload own" on storage.objects for insert
  to authenticated
  with check (bucket_id = 'note-media' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "note media update own" on storage.objects;
create policy "note media update own" on storage.objects for update
  to authenticated
  using (bucket_id = 'note-media' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "note media delete own" on storage.objects;
create policy "note media delete own" on storage.objects for delete
  to authenticated
  using (bucket_id = 'note-media' and (storage.foldername(name))[1] = auth.uid()::text);
