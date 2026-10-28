-- ============================================================================
-- Sharing a note with other people (phase 2 of sharing; phase 1 was "Send as
-- message", circle_message_cards_migration.sql). Covers the two note tables,
-- notebook_notes and course_notes. Grammar notes are example sentences on a
-- grammar point, not notes, and are left out.
--
-- note_shares       one row per person a note is shared with LIVE, with a
--                   role: viewer, commenter or editor. The person sees the
--                   owner's own row, so edits go both ways. "As their own
--                   copy" is not a share at all: copy_note_to_user() writes an
--                   independent row into the other person's Notebook.
-- note_share_links  at most one public link per note: an unguessable token,
--                   a role (viewer or commenter) and an on/off switch. Read
--                   ONLY through the two note_share_public_* functions below,
--                   which are the only things anon can execute. No table here
--                   is opened to anon.
-- note_comments     comments anchored to a range of the note's text, with
--                   replies (parent_id) and resolve / reopen. The anchor is
--                   {index, length, quote, prefix, suffix}: the quoted text and
--                   its offset, re-found in the text when the note is drawn
--                   (see noteCommentResolve in index.html).
--
-- Who may do what (my_note_role):
--   owner      everything, and only the owner shares or makes a link
--   editor     reads and saves the note's text and title; comments
--   commenter  reads; comments, replies, resolves
--   viewer     reads the note and its comments
--   circle     somebody who already sees the note through the circle
--              (shared_circle_cat) counts as a commenter. An explicit share
--              wins over that, so the owner can still make them a viewer.
--
-- The existing note SELECT / UPDATE policies are EXTENDED with an OR for an
-- explicit share row; what they already allow is unchanged. Writes stay
-- owner-only except for an editor share, and an editor changes the words of
-- the note, never where the owner keeps it (note_*_shared_edit_guard).
--
-- Idempotent; safe to run again. Not applied by the session that wrote it.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Tables
-- ---------------------------------------------------------------------------
create table if not exists public.note_shares (
  id uuid primary key default gen_random_uuid(),
  note_table text not null check (note_table in ('notebook_notes', 'course_notes')),
  note_id uuid not null,
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  grantee_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'viewer' check (role in ('viewer', 'commenter', 'editor')),
  created_at timestamptz not null default now(),
  constraint note_shares_one_per_person unique (note_table, note_id, grantee_id),
  constraint note_shares_not_self check (grantee_id <> owner_id)
);
create index if not exists note_shares_grantee_idx on public.note_shares (grantee_id);
create index if not exists note_shares_owner_idx on public.note_shares (owner_id);

-- 64 hex characters from two v4 uuids: 244 random bits.
create table if not exists public.note_share_links (
  id uuid primary key default gen_random_uuid(),
  note_table text not null check (note_table in ('notebook_notes', 'course_notes')),
  note_id uuid not null,
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  token text not null default (replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '')),
  role text not null default 'viewer' check (role in ('viewer', 'commenter')),
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  constraint note_share_links_token_key unique (token),
  constraint note_share_links_token_shape check (token ~ '^[0-9a-f]{64}$'),
  constraint note_share_links_one_per_note unique (note_table, note_id)
);
create index if not exists note_share_links_owner_idx on public.note_share_links (owner_id);

create table if not exists public.note_comments (
  id uuid primary key default gen_random_uuid(),
  note_table text not null check (note_table in ('notebook_notes', 'course_notes')),
  note_id uuid not null,
  parent_id uuid references public.note_comments(id) on delete cascade,
  author_id uuid references auth.users(id) on delete cascade,
  anon_name text,
  link_id uuid references public.note_share_links(id) on delete set null,
  body text not null,
  anchor jsonb,
  resolved boolean not null default false,
  resolved_by uuid references auth.users(id) on delete set null,
  resolved_at timestamptz,
  created_at timestamptz not null default now(),
  constraint note_comments_body_len check (char_length(btrim(body)) between 1 and 2000),
  constraint note_comments_anon_name_len check (anon_name is null or char_length(btrim(anon_name)) between 1 and 40),
  constraint note_comments_has_author check (author_id is not null or anon_name is not null),
  constraint note_comments_anchor_shape check (anchor is null or (jsonb_typeof(anchor) = 'object' and pg_column_size(anchor) <= 4000)),
  constraint note_comments_reply_unanchored check (parent_id is null or anchor is null)
);
create index if not exists note_comments_note_idx on public.note_comments (note_table, note_id);
create index if not exists note_comments_link_idx on public.note_comments (link_id, created_at);

-- ---------------------------------------------------------------------------
-- 2. Who may do what
-- ---------------------------------------------------------------------------
-- The owner of a note, read past RLS. Internal: not executable by any client.
create or replace function public.note_owner_of(p_table text, p_note_id uuid)
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v uuid;
begin
  if p_table = 'notebook_notes' then
    select user_id into v from notebook_notes where id = p_note_id;
  elsif p_table = 'course_notes' then
    select user_id into v from course_notes where id = p_note_id;
  end if;
  return v;
end;
$$;
revoke all on function public.note_owner_of(text, uuid) from public, anon, authenticated;

-- 'owner' | 'editor' | 'commenter' | 'viewer' | null for any account.
-- Internal: a client could otherwise ask who else has access to a note.
create or replace function public.note_access_role(p_uid uuid, p_table text, p_note_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_owner uuid;
  v_role text;
begin
  if p_uid is null or p_note_id is null then
    return null;
  end if;
  v_owner := note_owner_of(p_table, p_note_id);
  if v_owner is null then
    return null;
  end if;
  if v_owner = p_uid then
    return 'owner';
  end if;
  -- An account on its way out is hidden, the same as shared_circle does.
  if account_pending_deletion(v_owner) is true then
    return null;
  end if;
  select s.role into v_role
    from note_shares s
   where s.note_table = p_table and s.note_id = p_note_id and s.grantee_id = p_uid;
  if v_role is not null then
    return v_role;
  end if;
  if shared_circle_cat(p_uid, v_owner, p_table) is true then
    return 'commenter';
  end if;
  return null;
end;
$$;
revoke all on function public.note_access_role(uuid, text, uuid) from public, anon, authenticated;

-- The caller's own role. This is the one the policies and the app use.
create or replace function public.my_note_role(p_table text, p_note_id uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select note_access_role(auth.uid(), p_table, p_note_id);
$$;
revoke all on function public.my_note_role(text, uuid) from public, anon;
grant execute on function public.my_note_role(text, uuid) to authenticated;

-- For the note tables' own policies: is THIS row shared with the caller
-- (any role), and is it shared with the caller as an editor. p_owner is the
-- row's user_id, so a share only counts for the account that made it.
create or replace function public.note_shared_with_me(p_table text, p_note_id uuid, p_owner uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() is not null
     and account_pending_deletion(p_owner) is not true
     and exists (
       select 1 from note_shares s
        where s.note_table = p_table and s.note_id = p_note_id
          and s.owner_id = p_owner and s.grantee_id = auth.uid()
     );
$$;
revoke all on function public.note_shared_with_me(text, uuid, uuid) from public, anon;
grant execute on function public.note_shared_with_me(text, uuid, uuid) to authenticated;

create or replace function public.note_editable_by_me(p_table text, p_note_id uuid, p_owner uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() is not null
     and account_pending_deletion(p_owner) is not true
     and exists (
       select 1 from note_shares s
        where s.note_table = p_table and s.note_id = p_note_id
          and s.owner_id = p_owner and s.grantee_id = auth.uid()
          and s.role = 'editor'
     );
$$;
revoke all on function public.note_editable_by_me(text, uuid, uuid) from public, anon;
grant execute on function public.note_editable_by_me(text, uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. The note tables: extend, never loosen
-- ---------------------------------------------------------------------------
alter policy notebook_notes_select on public.notebook_notes
  using (
    shared_circle_cat(auth.uid(), user_id, 'notebook_notes')
    or public.note_shared_with_me('notebook_notes', id, user_id)
  );
alter policy course_notes_select on public.course_notes
  using (
    shared_circle_cat(auth.uid(), user_id, 'course_notes')
    or public.note_shared_with_me('course_notes', id, user_id)
  );
alter policy notebook_notes_update on public.notebook_notes
  using (auth.uid() = user_id or public.note_editable_by_me('notebook_notes', id, user_id))
  with check (auth.uid() = user_id or public.note_editable_by_me('notebook_notes', id, user_id));
alter policy course_notes_update on public.course_notes
  using (auth.uid() = user_id or public.note_editable_by_me('course_notes', id, user_id))
  with check (auth.uid() = user_id or public.note_editable_by_me('course_notes', id, user_id));
-- INSERT and DELETE are untouched: still the owner's alone.

-- An editor saves the words. Nobody but the owner moves a note to another
-- account (the WITH CHECK above would otherwise accept an editor setting
-- user_id to themselves), and an editor share does not reach the owner's
-- filing: header, sub-category, colour, order and course stay as they were.
-- The older core-member rule on course_notes ("notes update") is left exactly
-- as it was, so a core member's update passes through untouched.
create or replace function public.notebook_notes_shared_edit_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null or v_uid = old.user_id then
    return new;
  end if;
  if new.user_id is distinct from old.user_id then
    raise exception 'only the owner can move a note to another account' using errcode = '42501';
  end if;
  new.header := old.header;
  new.subcategory := old.subcategory;
  new.color := old.color;
  new.sort_order := old.sort_order;
  new.created_at := old.created_at;
  return new;
end;
$$;
revoke all on function public.notebook_notes_shared_edit_guard() from public, anon, authenticated;

create or replace function public.course_notes_shared_edit_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null or v_uid = old.user_id then
    return new;
  end if;
  if new.user_id is distinct from old.user_id then
    raise exception 'only the owner can move a note to another account' using errcode = '42501';
  end if;
  if is_core_member(v_uid) is true and is_core_member(old.user_id) is true then
    return new;
  end if;
  new.header := old.header;
  new.subcategory := old.subcategory;
  new.color := old.color;
  new.sort_order := old.sort_order;
  new.course_id := old.course_id;
  new.created_at := old.created_at;
  return new;
end;
$$;
revoke all on function public.course_notes_shared_edit_guard() from public, anon, authenticated;

drop trigger if exists notebook_notes_shared_edit_guard on public.notebook_notes;
create trigger notebook_notes_shared_edit_guard
  before update on public.notebook_notes
  for each row execute function public.notebook_notes_shared_edit_guard();
drop trigger if exists course_notes_shared_edit_guard on public.course_notes;
create trigger course_notes_shared_edit_guard
  before update on public.course_notes
  for each row execute function public.course_notes_shared_edit_guard();

-- A deleted note takes its shares, its link and its comments with it. There
-- is no foreign key to hang that on: a share points into one of two tables.
create or replace function public.note_sharing_cleanup()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from note_comments where note_table = tg_table_name and note_id = old.id;
  delete from note_share_links where note_table = tg_table_name and note_id = old.id;
  delete from note_shares where note_table = tg_table_name and note_id = old.id;
  return old;
end;
$$;
revoke all on function public.note_sharing_cleanup() from public, anon, authenticated;

drop trigger if exists notebook_notes_sharing_cleanup on public.notebook_notes;
create trigger notebook_notes_sharing_cleanup
  after delete on public.notebook_notes
  for each row execute function public.note_sharing_cleanup();
drop trigger if exists course_notes_sharing_cleanup on public.course_notes;
create trigger course_notes_sharing_cleanup
  after delete on public.course_notes
  for each row execute function public.note_sharing_cleanup();

-- ---------------------------------------------------------------------------
-- 4. RLS on the new tables
-- ---------------------------------------------------------------------------
alter table public.note_shares enable row level security;
drop policy if exists note_shares_select on public.note_shares;
drop policy if exists note_shares_insert on public.note_shares;
drop policy if exists note_shares_update on public.note_shares;
drop policy if exists note_shares_delete on public.note_shares;
-- The owner sees who has access; a person sees their own access.
create policy note_shares_select on public.note_shares for select to authenticated
  using (owner_id = auth.uid() or grantee_id = auth.uid());
-- Only the owner shares, and only with somebody in their circle.
create policy note_shares_insert on public.note_shares for insert to authenticated
  with check (
    owner_id = auth.uid()
    and grantee_id <> auth.uid()
    and public.my_note_role(note_table, note_id) = 'owner'
    and shared_circle(auth.uid(), grantee_id) is true
  );
-- Changing a role. Only the role column is grantable for update (below).
create policy note_shares_update on public.note_shares for update to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid() and public.my_note_role(note_table, note_id) = 'owner');
-- The owner removes a person; a person can also leave.
create policy note_shares_delete on public.note_shares for delete to authenticated
  using (owner_id = auth.uid() or grantee_id = auth.uid());
revoke all on public.note_shares from anon, authenticated;
grant select, insert, delete on public.note_shares to authenticated;
grant update (role) on public.note_shares to authenticated;

alter table public.note_share_links enable row level security;
drop policy if exists note_share_links_select on public.note_share_links;
drop policy if exists note_share_links_insert on public.note_share_links;
drop policy if exists note_share_links_update on public.note_share_links;
drop policy if exists note_share_links_delete on public.note_share_links;
create policy note_share_links_select on public.note_share_links for select to authenticated
  using (owner_id = auth.uid());
create policy note_share_links_insert on public.note_share_links for insert to authenticated
  with check (owner_id = auth.uid() and public.my_note_role(note_table, note_id) = 'owner');
create policy note_share_links_update on public.note_share_links for update to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());
create policy note_share_links_delete on public.note_share_links for delete to authenticated
  using (owner_id = auth.uid());
-- The token is never written by a client: it comes from the column default,
-- and a new one only from note_share_link_regenerate().
revoke all on public.note_share_links from anon, authenticated;
grant select, delete on public.note_share_links to authenticated;
grant insert (note_table, note_id, owner_id, role, enabled) on public.note_share_links to authenticated;
grant update (role, enabled) on public.note_share_links to authenticated;

-- A reply hangs off a top-level comment on the same note, and only a
-- top-level comment carries an anchor.
create or replace function public.note_comment_parent_ok(p_parent uuid, p_table text, p_note_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select p_parent is null or exists (
    select 1 from note_comments c
     where c.id = p_parent and c.parent_id is null
       and c.note_table = p_table and c.note_id = p_note_id
  );
$$;
revoke all on function public.note_comment_parent_ok(uuid, text, uuid) from public, anon;
grant execute on function public.note_comment_parent_ok(uuid, text, uuid) to authenticated;

alter table public.note_comments enable row level security;
drop policy if exists note_comments_select on public.note_comments;
drop policy if exists note_comments_insert on public.note_comments;
drop policy if exists note_comments_delete on public.note_comments;
-- Anyone who can read the note reads its comments (viewers included).
create policy note_comments_select on public.note_comments for select to authenticated
  using (public.my_note_role(note_table, note_id) is not null);
-- Commenters, editors and the owner comment, as themselves.
create policy note_comments_insert on public.note_comments for insert to authenticated
  with check (
    author_id = auth.uid()
    and anon_name is null
    and link_id is null
    and resolved = false and resolved_by is null and resolved_at is null
    and public.my_note_role(note_table, note_id) in ('owner', 'editor', 'commenter')
    and public.note_comment_parent_ok(parent_id, note_table, note_id)
  );
-- No UPDATE policy: resolving goes through note_comment_set_resolved().
-- A comment is removed by whoever wrote it, or by the note's owner.
create policy note_comments_delete on public.note_comments for delete to authenticated
  using (author_id = auth.uid() or public.my_note_role(note_table, note_id) = 'owner');
revoke all on public.note_comments from anon, authenticated;
grant select, insert, delete on public.note_comments to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Functions the signed-in app calls
-- ---------------------------------------------------------------------------
-- Resolve or reopen a thread (its top-level comment).
create or replace function public.note_comment_set_resolved(p_comment_id uuid, p_resolved boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  c record;
begin
  select * into c from note_comments where id = p_comment_id;
  if not found or c.parent_id is not null then
    raise exception 'comment not found' using errcode = 'P0002';
  end if;
  if coalesce(note_access_role(auth.uid(), c.note_table, c.note_id), '') not in ('owner', 'editor', 'commenter') then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  update note_comments
     set resolved = coalesce(p_resolved, false),
         resolved_by = case when coalesce(p_resolved, false) then auth.uid() end,
         resolved_at = case when coalesce(p_resolved, false) then now() end
   where id = p_comment_id;
end;
$$;
revoke all on function public.note_comment_set_resolved(uuid, boolean) from public, anon;
grant execute on function public.note_comment_set_resolved(uuid, boolean) to authenticated;

-- A new token for a link: the old address stops working at once.
create or replace function public.note_share_link_regenerate(p_link_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_token text := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
begin
  update note_share_links
     set token = v_token
   where id = p_link_id and owner_id = auth.uid();
  if not found then
    raise exception 'link not found' using errcode = 'P0002';
  end if;
  return v_token;
end;
$$;
revoke all on function public.note_share_link_regenerate(uuid) from public, anon;
grant execute on function public.note_share_link_regenerate(uuid) to authenticated;

-- "As their own copy": an independent row in the other person's Notebook
-- (General, at the end), whichever table the original is in. It never syncs
-- back. Only the owner sends one, and only to somebody in their circle.
create or replace function public.copy_note_to_user(p_table text, p_note_id uuid, p_recipient uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_title text;
  v_content text;
  v_owner uuid;
  v_order integer;
  v_id uuid;
begin
  if v_uid is null then
    raise exception 'not signed in' using errcode = '42501';
  end if;
  if p_table = 'notebook_notes' then
    select user_id, lecture_title, content into v_owner, v_title, v_content from notebook_notes where id = p_note_id;
  elsif p_table = 'course_notes' then
    select user_id, lecture_title, content into v_owner, v_title, v_content from course_notes where id = p_note_id;
  end if;
  if v_owner is null or v_owner <> v_uid then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if p_recipient is null or p_recipient = v_uid or shared_circle(v_uid, p_recipient) is not true then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  select coalesce(max(sort_order), 0) + 10 into v_order
    from notebook_notes where user_id = p_recipient and header is null;
  insert into notebook_notes (user_id, header, lecture_title, content, sort_order, updated_at, updated_by)
  values (p_recipient, null, v_title, coalesce(v_content, ''), v_order, now(), v_uid)
  returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.copy_note_to_user(text, uuid, uuid) from public, anon;
grant execute on function public.copy_note_to_user(text, uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. The public link: the only things anon can execute
-- ---------------------------------------------------------------------------
-- The note behind a link, with its comments, or null when the token is
-- unknown, the link is off, or the note is gone.
create or replace function public.note_share_public_get(p_token text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  l note_share_links%rowtype;
  v_owner uuid;
  v_title text;
  v_content text;
  v_updated timestamptz;
  v_comments jsonb;
begin
  if p_token is null or p_token !~ '^[0-9a-f]{64}$' then
    return null;
  end if;
  select * into l from note_share_links where token = p_token and enabled;
  if not found then
    return null;
  end if;
  if l.note_table = 'notebook_notes' then
    select user_id, lecture_title, content, coalesce(updated_at, created_at)
      into v_owner, v_title, v_content, v_updated
      from notebook_notes where id = l.note_id;
  else
    select user_id, lecture_title, content, coalesce(updated_at, created_at)
      into v_owner, v_title, v_content, v_updated
      from course_notes where id = l.note_id;
  end if;
  if v_owner is null or v_owner <> l.owner_id or account_pending_deletion(v_owner) is true then
    return null;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', c.id,
           'parent_id', c.parent_id,
           'name', coalesce(p.display_name, c.anon_name),
           'guest', c.author_id is null,
           'body', c.body,
           'anchor', c.anchor,
           'resolved', c.resolved,
           'created_at', c.created_at
         ) order by c.created_at), '[]'::jsonb)
    into v_comments
    from note_comments c
    left join profiles p on p.id = c.author_id
   where c.note_table = l.note_table and c.note_id = l.note_id;
  return jsonb_build_object(
    'title', v_title,
    'content', coalesce(v_content, ''),
    'updated_at', v_updated,
    'owner_name', (select display_name from profiles where id = v_owner),
    'role', l.role,
    'comments', v_comments
  );
end;
$$;
revoke all on function public.note_share_public_get(text) from public;
grant execute on function public.note_share_public_get(text) to anon, authenticated;

-- A comment from somebody holding a commenter link, signed in or not. It
-- needs a display name (1-40 characters). Limits per link: 20 comments in
-- any 10 minutes and 500 in all; the link's row is locked while counting so
-- two at once cannot both slip under.
create or replace function public.note_share_public_comment(
  p_token text,
  p_name text,
  p_body text,
  p_parent_id uuid default null,
  p_anchor jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  l note_share_links%rowtype;
  v_owner uuid;
  v_name text := btrim(coalesce(p_name, ''));
  v_body text := btrim(coalesce(p_body, ''));
  v_anchor jsonb := p_anchor;
  v_recent integer;
  v_total integer;
  v_id uuid;
  v_at timestamptz;
begin
  if p_token is null or p_token !~ '^[0-9a-f]{64}$' then
    raise exception 'link not found' using errcode = 'P0002';
  end if;
  select * into l from note_share_links where token = p_token and enabled for update;
  if not found then
    raise exception 'link not found' using errcode = 'P0002';
  end if;
  if l.role <> 'commenter' then
    raise exception 'this link cannot comment' using errcode = '42501';
  end if;
  v_owner := note_owner_of(l.note_table, l.note_id);
  if v_owner is null or v_owner <> l.owner_id or account_pending_deletion(v_owner) is true then
    raise exception 'link not found' using errcode = 'P0002';
  end if;
  if char_length(v_name) < 1 or char_length(v_name) > 40 then
    raise exception 'a name of 1 to 40 characters is needed' using errcode = '22023', hint = 'name';
  end if;
  if char_length(v_body) < 1 or char_length(v_body) > 2000 then
    raise exception 'a comment is 1 to 2000 characters' using errcode = '22023', hint = 'body';
  end if;
  if p_parent_id is not null then
    if note_comment_parent_ok(p_parent_id, l.note_table, l.note_id) is not true then
      raise exception 'comment not found' using errcode = 'P0002';
    end if;
    v_anchor := null;
  elsif v_anchor is not null and (jsonb_typeof(v_anchor) <> 'object' or pg_column_size(v_anchor) > 4000) then
    raise exception 'bad anchor' using errcode = '22023';
  end if;
  select count(*) into v_recent from note_comments
   where link_id = l.id and created_at > now() - interval '10 minutes';
  select count(*) into v_total from note_comments where link_id = l.id;
  if v_recent >= 20 or v_total >= 500 then
    raise exception 'too many comments on this link, try again later' using errcode = 'P0001', hint = 'rate_limited';
  end if;
  insert into note_comments (note_table, note_id, parent_id, author_id, anon_name, link_id, body, anchor)
  values (l.note_table, l.note_id, p_parent_id, null, v_name, l.id, v_body, v_anchor)
  returning id, created_at into v_id, v_at;
  return jsonb_build_object(
    'id', v_id, 'parent_id', p_parent_id, 'name', v_name, 'guest', true,
    'body', v_body, 'anchor', v_anchor, 'resolved', false, 'created_at', v_at
  );
end;
$$;
revoke all on function public.note_share_public_comment(text, text, text, uuid, jsonb) from public;
grant execute on function public.note_share_public_comment(text, text, text, uuid, jsonb) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 7. Live updates: access changes and comments reach open editors
-- ---------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'note_shares') then
    alter publication supabase_realtime add table public.note_shares;
  end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'note_comments') then
    alter publication supabase_realtime add table public.note_comments;
  end if;
end $$;
