-- Attachments on circle messages, plus what searching older history needs
-- (real-user request: "the ability to add attachments, like files and
-- pictures etc ... view files, pictures, etc. separately (also searchable by
-- date), and making it possible to go further back in the chat by
-- searching").
--
-- ONE attachment per message, not a child table: each file gets its own
-- bubble, which is how a chat actually reads, and it keeps the file list a
-- plain query over messages rather than a join.
alter table circle_messages
  add column attachment_path text,
  add column attachment_name text,
  add column attachment_type text,
  add column attachment_size integer;

-- The body may now be empty, but only when there is a file to stand in for
-- it -- a message that is neither text nor file is still refused.
alter table circle_messages drop constraint circle_messages_body_len;
alter table circle_messages add constraint circle_messages_body_len
  check (length(body) <= 4000
         and (length(btrim(body)) > 0 or attachment_path is not null));

-- Searching reaches past whatever the client has loaded, so the body needs
-- an index that suits ILIKE '%...%'. trigram rather than to_tsvector: this
-- is short chat text where people search for fragments and names, not
-- documents where stemming helps.
create extension if not exists pg_trgm;
create index circle_messages_body_trgm on circle_messages using gin (body gin_trgm_ops);
-- The files view is "everything with an attachment, newest first".
create index circle_messages_attachment_idx on circle_messages(created_at desc)
  where attachment_path is not null;

-- A PRIVATE bucket, unlike every other bucket in this project. Those hold
-- syllabi and CVs, where an unguessable public URL is an accepted trade;
-- these are private messages, so the file is reached through a short-lived
-- signed URL instead and the object is readable only to whoever could read
-- the MESSAGE carrying it -- the same predicate, not a second guess at it.
insert into storage.buckets (id, name, public, file_size_limit)
values ('circle-attachments', 'circle-attachments', false, 26214400)
on conflict (id) do nothing;

create policy "circle_attachments_insert" on storage.objects for insert to authenticated
  with check (
    bucket_id = 'circle-attachments'
    -- First path segment is the uploader's id, so nobody can write into
    -- somebody else's folder.
    and (storage.foldername(name))[1] = auth.uid()::text
  );
create policy "circle_attachments_select" on storage.objects for select to authenticated
  using (
    bucket_id = 'circle-attachments'
    and exists (
      select 1 from circle_messages m
      where m.attachment_path = storage.objects.name
        and (m.sender_id = auth.uid()
             or m.recipient_id = auth.uid()
             or (m.recipient_id is null and shared_circle(auth.uid(), m.sender_id)))
    )
  );
create policy "circle_attachments_delete" on storage.objects for delete to authenticated
  using (
    bucket_id = 'circle-attachments'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
