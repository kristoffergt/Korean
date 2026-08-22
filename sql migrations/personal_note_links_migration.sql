-- A private "open my Apple Notes note" shortcut -- deliberately its own
-- table, not a profiles column, because profiles is readable by anyone
-- signed in (SELECT policy is just `true`, needed for names/colors/etc
-- across the circle). This link is effectively a capability to edit
-- someone's live Apple Note, so it must never be visible to anyone but
-- its owner, even other circle members.
--
-- Applied live via apply_migration as "personal_note_links" -- this file
-- mirrors that for the record.

create table public.personal_note_links (
  user_id uuid primary key references auth.users(id) on delete cascade,
  link text not null,
  updated_at timestamptz not null default now()
);

alter table public.personal_note_links enable row level security;

create policy "personal_note_links_select_own"
  on public.personal_note_links for select
  using (auth.uid() = user_id);

create policy "personal_note_links_upsert_own"
  on public.personal_note_links for insert
  with check (auth.uid() = user_id);

create policy "personal_note_links_update_own"
  on public.personal_note_links for update
  using (auth.uid() = user_id);

create policy "personal_note_links_delete_own"
  on public.personal_note_links for delete
  using (auth.uid() = user_id);
