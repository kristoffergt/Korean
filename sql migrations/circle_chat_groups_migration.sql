-- Group chats (real-user request: "make group chats").
--
-- Until now a message had two possible addresses: nobody in particular (the
-- whole circle) or one person (a direct thread). A group is a third: a named
-- set of people, chosen by whoever made it, with its own conversation.
--
-- WHO SEES WHAT used to be one predicate written out six times -- in the
-- select policy, the storage policy and four security definer functions:
--
--   m.sender_id = uid or m.recipient_id = uid
--   or (m.recipient_id is null and shared_circle(uid, m.sender_id))
--
-- That is now ONE function, can_see_circle_message, and every one of the six
-- calls it, so a fourth kind of address later is one edit rather than six that
-- have to agree.
--
-- A GROUP MESSAGE IS SEEN BY THE GROUP'S CURRENT MEMBERS, and by nobody else,
-- the sender included once they have left. That is the rule that makes
-- leaving mean something: a group you left is gone from your side, history
-- and all, rather than lingering as a thread you can read and not write in.
-- A member added later sees the whole history (the Slack shape, not
-- WhatsApp's), which is what a small circle adding one more person wants.

create table if not exists circle_chat_groups (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  -- Who manages membership: only they can remove somebody else. Handed to the
  -- longest-standing member when they leave, so a group is never stuck with
  -- nobody able to do it. Null only if that account is deleted outright.
  created_by uuid references profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint circle_chat_groups_name check (length(btrim(name)) between 1 and 60)
);

create table if not exists circle_chat_group_members (
  group_id uuid not null references circle_chat_groups(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  added_by uuid references profiles(id) on delete set null,
  added_at timestamptz not null default now(),
  primary key (group_id, user_id)
);
create index if not exists circle_chat_group_members_user_idx on circle_chat_group_members(user_id);

alter table circle_messages
  add column if not exists group_id uuid references circle_chat_groups(id) on delete cascade;
-- One address per message: a person OR a group, never both.
alter table circle_messages drop constraint if exists circle_messages_one_address;
alter table circle_messages add constraint circle_messages_one_address
  check (recipient_id is null or group_id is null);
create index if not exists circle_messages_group_idx
  on circle_messages(group_id, created_at) where group_id is not null;

-- Membership, readable from policies without recursing into the member
-- table's own policy (which asks this same question).
create or replace function in_chat_group(p_group uuid, p_user uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select p_group is not null and p_user is not null and exists (
    select 1 from circle_chat_group_members
     where group_id = p_group and user_id = p_user);
$$;
revoke all on function in_chat_group(uuid, uuid) from public, anon;
grant execute on function in_chat_group(uuid, uuid) to authenticated;

-- THE one answer to "may this person see this message".
create or replace function can_see_circle_message(p_viewer uuid, p_sender uuid, p_recipient uuid, p_group uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  -- COALESCE, because shared_circle answers NULL rather than false for two
  -- people with no link at all (is_linked compares two null group ids), and
  -- a NULL here was the hole: every plpgsql caller writes "if not (...) then
  -- refuse", and "not NULL" is NULL, which IF treats as false -- so it did not
  -- refuse. That was already true of the four functions' own copy of the
  -- predicate before this migration (a stranger holding a circle message's id
  -- could react to it or tick it); one strict answer closes it everywhere.
  select coalesce(p_viewer is not null and case
    when p_group is not null then in_chat_group(p_group, p_viewer)
    else p_sender = p_viewer
         or p_recipient = p_viewer
         or (p_recipient is null and shared_circle(p_viewer, p_sender))
  end, false);
$$;
revoke all on function can_see_circle_message(uuid, uuid, uuid, uuid) from public, anon;
grant execute on function can_see_circle_message(uuid, uuid, uuid, uuid) to authenticated;

-- Read markers: a group thread's key is 'g:<group id>' for every member (a
-- direct thread's is keyed from the reader's side, the group's needs no
-- side). A group member can be somebody outside your own circle, and their
-- marker is what turns your eye on, so a group marker is visible to the
-- group; every other marker keeps the old rule. The cast is guarded by the
-- pattern in plpgsql, where the order is guaranteed -- in a policy's own
-- boolean expression it is not, and a malformed key would throw.
create or replace function can_see_read_marker(p_viewer uuid, p_reader uuid, p_thread text)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  gid uuid;
begin
  if p_viewer is null or p_reader is null then return false; end if;
  if p_viewer = p_reader then return true; end if;
  if p_thread ~ '^g:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    gid := substr(p_thread, 3)::uuid;
    return in_chat_group(gid, p_viewer) and in_chat_group(gid, p_reader);
  end if;
  return coalesce(shared_circle(p_viewer, p_reader), false);
end;
$$;
revoke all on function can_see_read_marker(uuid, uuid, text) from public, anon;
grant execute on function can_see_read_marker(uuid, uuid, text) to authenticated;

drop policy if exists "circle_message_reads_select" on circle_message_reads;
create policy "circle_message_reads_select" on circle_message_reads for select to authenticated
  using (can_see_read_marker(auth.uid(), user_id, thread));

drop policy if exists "circle_messages_select" on circle_messages;
create policy "circle_messages_select" on circle_messages for select to authenticated
  using (can_see_circle_message(auth.uid(), sender_id, recipient_id, group_id));

-- Sending into a group needs membership of it; everything else about an
-- insert is what circle_message_edit left it as.
drop policy if exists "circle_messages_insert" on circle_messages;
create policy "circle_messages_insert" on circle_messages for insert to authenticated
  with check (
    sender_id = auth.uid()
    and (case when group_id is not null
              then recipient_id is null and in_chat_group(group_id, auth.uid())
              else recipient_id is null or shared_circle(auth.uid(), recipient_id) end)
    and kind = 'text' and ref_message is null
    and checks = '{}'::jsonb and reactions = '{}'::jsonb
    and edited_at is null
  );

drop policy if exists "circle_attachments_select" on storage.objects;
create policy "circle_attachments_select" on storage.objects for select to authenticated
  using (
    bucket_id = 'circle-attachments'
    and exists (select 1 from circle_messages m
                 where m.attachment_path = objects.name
                   and can_see_circle_message(auth.uid(), m.sender_id, m.recipient_id, m.group_id))
  );

-- The groups themselves: seen by their members, written only through the
-- functions below (no insert/update/delete policy at all).
alter table circle_chat_groups enable row level security;
alter table circle_chat_group_members enable row level security;
drop policy if exists "circle_chat_groups_select" on circle_chat_groups;
create policy "circle_chat_groups_select" on circle_chat_groups for select to authenticated
  using (in_chat_group(id, auth.uid()));
drop policy if exists "circle_chat_group_members_select" on circle_chat_group_members;
create policy "circle_chat_group_members_select" on circle_chat_group_members for select to authenticated
  using (in_chat_group(group_id, auth.uid()));

-- Make a group. Everybody put in it has to be in the maker's own circle --
-- you can only start a conversation with people you could already message.
-- One other person is enough: a named thread with your partner ("Groceries")
-- is a real use, not a duplicate of the direct one.
create or replace function create_chat_group(p_name text, p_members uuid[])
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  nm text := btrim(coalesce(p_name, ''));
  others uuid[];
  x uuid;
  gid uuid;
begin
  if uid is null then raise exception 'not signed in' using errcode = '42501'; end if;
  if nm = '' or length(nm) > 60 then raise exception 'bad name' using errcode = '22023'; end if;
  select coalesce(array_agg(distinct v), '{}'::uuid[]) into others
    from unnest(coalesce(p_members, '{}'::uuid[])) as v where v is not null and v <> uid;
  if coalesce(array_length(others, 1), 0) = 0 then
    raise exception 'nobody to talk to' using errcode = '22023';
  end if;
  if array_length(others, 1) > 30 then raise exception 'too many' using errcode = '22023'; end if;
  foreach x in array others loop
    -- IS NOT TRUE, not NOT: shared_circle is NULL for a stranger (see above).
    if shared_circle(uid, x) is not true then raise exception 'not in your circle' using errcode = '42501'; end if;
  end loop;
  insert into circle_chat_groups (name, created_by) values (nm, uid) returning id into gid;
  insert into circle_chat_group_members (group_id, user_id, added_by) values (gid, uid, uid);
  insert into circle_chat_group_members (group_id, user_id, added_by)
    select gid, v, uid from unnest(others) as v;
  return gid;
end;
$$;

create or replace function rename_chat_group(p_group uuid, p_name text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  nm text := btrim(coalesce(p_name, ''));
begin
  if uid is null then raise exception 'not signed in' using errcode = '42501'; end if;
  if not in_chat_group(p_group, uid) then raise exception 'not allowed' using errcode = '42501'; end if;
  if nm = '' or length(nm) > 60 then raise exception 'bad name' using errcode = '22023'; end if;
  update circle_chat_groups set name = nm where id = p_group;
  return nm;
end;
$$;

-- Any member can add people, but only people in THEIR OWN circle -- the same
-- rule as making the group, so nobody is ever added by a stranger to them.
create or replace function add_chat_group_members(p_group uuid, p_members uuid[])
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  x uuid;
  n integer;
begin
  if uid is null then raise exception 'not signed in' using errcode = '42501'; end if;
  if not in_chat_group(p_group, uid) then raise exception 'not allowed' using errcode = '42501'; end if;
  foreach x in array coalesce(p_members, '{}'::uuid[]) loop
    if x is not null and x <> uid and shared_circle(uid, x) is not true then
      raise exception 'not in your circle' using errcode = '42501';
    end if;
  end loop;
  if (select count(*) from circle_chat_group_members where group_id = p_group)
     + coalesce(array_length(p_members, 1), 0) > 31 then
    raise exception 'too many' using errcode = '22023';
  end if;
  insert into circle_chat_group_members (group_id, user_id, added_by)
    select p_group, v, uid from unnest(coalesce(p_members, '{}'::uuid[])) as v
     where v is not null and v <> uid
    on conflict do nothing;
  get diagnostics n = row_count;
  return n;
end;
$$;

-- Removing somebody else is the manager's. Removing yourself is leaving.
create or replace function remove_chat_group_member(p_group uuid, p_user uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  g circle_chat_groups%rowtype;
begin
  if uid is null then raise exception 'not signed in' using errcode = '42501'; end if;
  select * into g from circle_chat_groups where id = p_group for update;
  if not found or not in_chat_group(p_group, uid) then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_user = uid then raise exception 'leave instead' using errcode = '22023'; end if;
  if g.created_by is distinct from uid then raise exception 'not allowed' using errcode = '42501'; end if;
  delete from circle_chat_group_members where group_id = p_group and user_id = p_user;
end;
$$;

-- Leaving. The last one out deletes the group, and its messages with it --
-- there is nobody left who could ever see them. A manager leaving hands the
-- role to whoever has been in the group longest.
create or replace function leave_chat_group(p_group uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  g circle_chat_groups%rowtype;
  heir uuid;
begin
  if uid is null then raise exception 'not signed in' using errcode = '42501'; end if;
  select * into g from circle_chat_groups where id = p_group for update;
  if not found or not in_chat_group(p_group, uid) then raise exception 'not allowed' using errcode = '42501'; end if;
  delete from circle_chat_group_members where group_id = p_group and user_id = uid;
  select user_id into heir from circle_chat_group_members
   where group_id = p_group order by added_at, user_id limit 1;
  if heir is null then
    delete from circle_chat_groups where id = p_group;
  elsif g.created_by is not distinct from uid then
    update circle_chat_groups set created_by = heir where id = p_group;
  end if;
end;
$$;

revoke all on function create_chat_group(text, uuid[]) from public, anon;
revoke all on function rename_chat_group(uuid, text) from public, anon;
revoke all on function add_chat_group_members(uuid, uuid[]) from public, anon;
revoke all on function remove_chat_group_member(uuid, uuid) from public, anon;
revoke all on function leave_chat_group(uuid) from public, anon;
grant execute on function create_chat_group(text, uuid[]) to authenticated;
grant execute on function rename_chat_group(uuid, text) to authenticated;
grant execute on function add_chat_group_members(uuid, uuid[]) to authenticated;
grant execute on function remove_chat_group_member(uuid, uuid) to authenticated;
grant execute on function leave_chat_group(uuid) to authenticated;

-- The four message functions, with the shared check in place of their own
-- copy of the predicate. Bodies otherwise unchanged.
create or replace function set_circle_message_check(p_message uuid, p_item integer, p_on boolean)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  m circle_messages%rowtype;
  n_items integer;
  next_checks jsonb;
begin
  if uid is null then raise exception 'not signed in' using errcode = '42501'; end if;
  select * into m from circle_messages where id = p_message for update;
  if not found then raise exception 'no such message' using errcode = 'P0002'; end if;
  if not can_see_circle_message(uid, m.sender_id, m.recipient_id, m.group_id) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if not m.checklist then raise exception 'not a checklist' using errcode = '22023'; end if;
  select count(*) into n_items
    from regexp_split_to_table(m.body, E'\r?\n') as l(line)
   where btrim(l.line) <> '';
  if p_item is null or p_item < 0 or p_item >= n_items then
    raise exception 'no such item' using errcode = '22023';
  end if;
  if p_on then
    next_checks := m.checks || jsonb_build_object(p_item::text,
                     jsonb_build_object('by', uid, 'at', now()));
  else
    next_checks := m.checks - p_item::text;
  end if;
  update circle_messages set checks = next_checks where id = p_message;
  return next_checks;
end;
$$;

create or replace function set_circle_message_reaction(p_message uuid, p_reaction text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  m circle_messages%rowtype;
  next_reactions jsonb;
begin
  if uid is null then raise exception 'not signed in' using errcode = '42501'; end if;
  if p_reaction is not null
     and p_reaction not in ('heart', 'thumbs', 'haha', 'wow', 'sad', 'yay',
                            'fire', 'hundred', 'clap', 'party', 'hearteyes',
                            'cool', 'think', 'fingerheart', 'skull', 'angry') then
    raise exception 'unknown reaction' using errcode = '22023';
  end if;
  select * into m from circle_messages where id = p_message for update;
  if not found then raise exception 'no such message' using errcode = 'P0002'; end if;
  if not can_see_circle_message(uid, m.sender_id, m.recipient_id, m.group_id) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if m.kind <> 'text' then raise exception 'not a message' using errcode = '22023'; end if;
  if p_reaction is null then
    next_reactions := m.reactions - uid::text;
  else
    next_reactions := m.reactions || jsonb_build_object(uid::text, p_reaction);
  end if;
  update circle_messages set reactions = next_reactions where id = p_message;
  return next_reactions;
end;
$$;

-- The ask goes back into the conversation it came from: the group, the
-- direct thread with the sender, or the circle.
create or replace function request_circle_message_checklist(p_message uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  m circle_messages%rowtype;
  existing uuid;
  created uuid;
begin
  if uid is null then raise exception 'not signed in' using errcode = '42501'; end if;
  select * into m from circle_messages where id = p_message;
  if not found then raise exception 'no such message' using errcode = 'P0002'; end if;
  if not can_see_circle_message(uid, m.sender_id, m.recipient_id, m.group_id) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if m.sender_id = uid then raise exception 'convert it yourself' using errcode = '22023'; end if;
  if m.kind <> 'text' or btrim(m.body) = '' or m.checklist then
    raise exception 'nothing to convert' using errcode = '22023';
  end if;
  select id into existing from circle_messages
   where kind = 'checklist_request' and ref_message = m.id and sender_id = uid
   limit 1;
  if existing is not null then return existing; end if;
  insert into circle_messages (sender_id, recipient_id, group_id, body, kind, ref_message)
  values (uid,
          case when m.recipient_id is null then null else m.sender_id end,
          m.group_id,
          '', 'checklist_request', m.id)
  returning id into created;
  return created;
end;
$$;

-- The sender's own two: still the sender's only, and now also only while the
-- sender can see the message -- somebody who left a group cannot reach back
-- into it to rewrite what they said there.
create or replace function set_circle_message_checklist(p_message uuid, p_on boolean)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  m circle_messages%rowtype;
begin
  if uid is null then raise exception 'not signed in' using errcode = '42501'; end if;
  select * into m from circle_messages where id = p_message for update;
  if not found then raise exception 'no such message' using errcode = 'P0002'; end if;
  if m.sender_id <> uid or not can_see_circle_message(uid, m.sender_id, m.recipient_id, m.group_id) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if m.kind <> 'text' or btrim(m.body) = '' then
    raise exception 'nothing to tick' using errcode = '22023';
  end if;
  if not p_on and m.checks <> '{}'::jsonb then
    raise exception 'items are ticked' using errcode = '22023';
  end if;
  update circle_messages set checklist = p_on where id = p_message;
  return p_on;
end;
$$;

create or replace function edit_circle_message(p_message uuid, p_body text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  m circle_messages%rowtype;
  new_body text := btrim(coalesce(p_body, ''), E' \t\r\n');
  old_keys text[];
  new_keys text[];
  next_checks jsonb := '{}'::jsonb;
  k text;
  v jsonb;
  i integer;
  j integer;
  x integer;
  stamp timestamptz := now();
  still_list boolean;
begin
  if uid is null then raise exception 'not signed in' using errcode = '42501'; end if;
  select * into m from circle_messages where id = p_message for update;
  if not found then raise exception 'no such message' using errcode = 'P0002'; end if;
  if m.sender_id <> uid or not can_see_circle_message(uid, m.sender_id, m.recipient_id, m.group_id) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if m.kind <> 'text' then raise exception 'not a message' using errcode = '22023'; end if;
  if length(new_body) > 4000 then raise exception 'too long' using errcode = '22001'; end if;
  if new_body = '' and m.attachment_path is null then
    raise exception 'empty' using errcode = '22023';
  end if;
  if new_body = m.body then
    return jsonb_build_object('body', m.body, 'edited_at', m.edited_at,
                              'checks', m.checks, 'checklist', m.checklist);
  end if;
  new_keys := circle_message_item_keys(new_body);
  if m.checks <> '{}'::jsonb then
    old_keys := circle_message_item_keys(m.body);
    for k, v in select e.key, e.value from jsonb_each(m.checks) e order by e.key::integer loop
      i := k::integer;
      continue when i < 0 or i >= coalesce(array_length(old_keys, 1), 0);
      j := null;
      if i < coalesce(array_length(new_keys, 1), 0)
         and new_keys[i + 1] = old_keys[i + 1]
         and not next_checks ? i::text then
        j := i;
      else
        for x in 1 .. coalesce(array_length(new_keys, 1), 0) loop
          if new_keys[x] = old_keys[i + 1] and not next_checks ? (x - 1)::text then
            j := x - 1;
            exit;
          end if;
        end loop;
      end if;
      if j is not null then next_checks := next_checks || jsonb_build_object(j::text, v); end if;
    end loop;
  end if;
  still_list := m.checklist and coalesce(array_length(new_keys, 1), 0) > 0;
  update circle_messages
     set body = new_body, edited_at = stamp, checks = next_checks, checklist = still_list
   where id = p_message;
  return jsonb_build_object('body', new_body, 'edited_at', stamp,
                            'checks', next_checks, 'checklist', still_list);
end;
$$;

-- Live: being added to a group, a rename, somebody leaving.
do $$
begin
  if not exists (select 1 from pg_publication_tables
                  where pubname = 'supabase_realtime' and tablename = 'circle_chat_groups') then
    alter publication supabase_realtime add table circle_chat_groups;
  end if;
  if not exists (select 1 from pg_publication_tables
                  where pubname = 'supabase_realtime' and tablename = 'circle_chat_group_members') then
    alter publication supabase_realtime add table circle_chat_group_members;
  end if;
end;
$$;
