-- Short, readable, EDITABLE links for uploaded files. A raw storage URL is
-- unreadable and unshareable (real-user report: "this weird ass URL"), and
-- it also leaks the storage layout. kristoffergt.com/f/<slug> resolves here
-- instead.
--
-- Read is PUBLIC (anon included) on purpose: /f/<slug> is resolved by a
-- static page with no session -- someone opening a shared syllabus link is
-- not signed in. That exposes nothing new, since every row points at an
-- already-public storage object; the slug is simply a nicer alias for a URL
-- anyone with the link could already open.
create table file_links (
  slug text primary key,
  url text not null,
  owner_id uuid not null references profiles(id) on delete cascade,
  label text,
  created_at timestamptz not null default now(),
  constraint file_links_slug_format check (slug ~ '^[a-z0-9][a-z0-9-]{0,63}$')
);
create index file_links_owner_idx on file_links(owner_id);
create index file_links_url_idx on file_links(url);
alter table file_links enable row level security;

create policy "file_links_public_read" on file_links for select
  to anon, authenticated using (true);
create policy "file_links_insert_own" on file_links for insert
  to authenticated with check (owner_id = auth.uid());
create policy "file_links_update_own" on file_links for update
  to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy "file_links_delete_own" on file_links for delete
  to authenticated using (owner_id = auth.uid());
