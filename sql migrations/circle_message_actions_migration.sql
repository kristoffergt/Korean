-- What you can do TO a message once it is sent (real-user requests, 14 Oct):
--
--   "Even messages that have been sent should be able to be turned into
--    checklist. For the person who sent it: simple convert on the message.
--    For the person who received it: 1. resend it with your own message as a
--    checklist (single button, easy path), 2. request the other person to
--    convert it to checklist"
--   "Also add message reactions with our own cute icons"
--   "Both a delete just for me and for all"
--
-- Builds on circle_message_checklist_migration.

-- 1. REACTIONS live on the message, exactly like the ticks: one jsonb of
--    {"<user id>": "<reaction>"}, one reaction per person per message, written
--    only through a function that puts the CALLER's own id in. So a reaction
--    reaches the other phone as the UPDATE the ticks already ride on, with the
--    table's own SELECT policy applied, and needs no table, no publication
--    change and no DELETE event (which Realtime cannot filter by RLS).
alter table circle_messages
  add column if not exists reactions jsonb not null default '{}'::jsonb;

-- 2. A REQUEST to turn a message into a checklist is itself a row in the
--    thread, so the sender actually sees it: it arrives live, it counts as
--    unread, and it sits where the conversation is rather than as a flag on a
--    message that may be a long way up. `kind` says what a row is and
--    `ref_message` which message it is about; deleting that message takes the
--    request with it.
alter table circle_messages
  add column if not exists kind text not null default 'text',
  add column if not exists ref_message uuid references circle_messages(id) on delete cascade;
alter table circle_messages drop constraint if exists circle_messages_kind;
alter table circle_messages add constraint circle_messages_kind
  check (kind in ('text', 'checklist_request'));
alter table circle_messages drop constraint if exists circle_messages_ref;
alter table circle_messages add constraint circle_messages_ref
  check ((kind = 'text') = (ref_message is null));
-- A request has no body of its own: what it is about is the message it names.
alter table circle_messages drop constraint circle_messages_body_len;
alter table circle_messages add constraint circle_messages_body_len
  check (length(body) <= 4000
         and (length(btrim(body)) > 0 or attachment_path is not null or kind <> 'text'));
create index if not exists circle_messages_ref_idx on circle_messages(ref_message)
  where ref_message is not null;

-- A client may insert ordinary messages and nothing else: no request rows
-- (those come only from the function below, which checks what they point at)
-- and no ticks or reactions written in at birth, which would let somebody put
-- words in another person's mouth through the jsonb. A new checklist is still
-- allowed -- the composer's own toggle -- because it carries no ticks.
drop policy if exists "circle_messages_insert" on circle_messages;
create policy "circle_messages_insert" on circle_messages for insert to authenticated
  with check (
    sender_id = auth.uid()
    and (recipient_id is null or shared_circle(auth.uid(), recipient_id))
    and kind = 'text' and ref_message is null
    and checks = '{}'::jsonb and reactions = '{}'::jsonb
  );

-- 3. CONVERTING is now the SENDER's alone. Anyone who can read it used to be
--    able to turn a message into a checklist; the receiver's two paths are a
--    copy of their own (an ordinary insert) or a request (below).
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
  if m.sender_id <> uid then raise exception 'not allowed' using errcode = '42501'; end if;
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

-- The receiver asks. Same thread as the message it is about: a direct
-- message's request goes back to its sender, a group message's to the group.
-- Asking twice returns the request already there rather than a second one.
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
  if not (m.sender_id = uid
          or m.recipient_id = uid
          or (m.recipient_id is null and shared_circle(uid, m.sender_id))) then
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
  insert into circle_messages (sender_id, recipient_id, body, kind, ref_message)
  values (uid, case when m.recipient_id is null then null else m.sender_id end,
          '', 'checklist_request', m.id)
  returning id into created;
  return created;
end;
$$;

-- One reaction per person per message; null takes yours off. The set is the
-- app's own drawn icons, named here so a client cannot store anything else.
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
     and p_reaction not in ('heart', 'thumbs', 'haha', 'wow', 'sad', 'yay') then
    raise exception 'unknown reaction' using errcode = '22023';
  end if;
  select * into m from circle_messages where id = p_message for update;
  if not found then raise exception 'no such message' using errcode = 'P0002'; end if;
  if not (m.sender_id = uid
          or m.recipient_id = uid
          or (m.recipient_id is null and shared_circle(uid, m.sender_id))) then
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

revoke all on function request_circle_message_checklist(uuid) from public, anon;
revoke all on function set_circle_message_reaction(uuid, text) from public, anon;
grant execute on function request_circle_message_checklist(uuid) to authenticated;
grant execute on function set_circle_message_reaction(uuid, text) to authenticated;

-- 4. DELETE FOR ME is a row of your own saying "not on my screen", and
--    nothing about the message changes, so nobody else learns you did it.
--    DELETE FOR EVERYONE is the plain delete the existing policy already
--    allows the sender (circle_messages_delete), which takes its ticks,
--    reactions and any request about it along with the row.
create table if not exists circle_message_hidden (
  user_id uuid not null default auth.uid() references profiles(id) on delete cascade,
  message_id uuid not null references circle_messages(id) on delete cascade,
  hidden_at timestamptz not null default now(),
  primary key (user_id, message_id)
);
alter table circle_message_hidden enable row level security;
drop policy if exists "circle_message_hidden_select" on circle_message_hidden;
drop policy if exists "circle_message_hidden_insert" on circle_message_hidden;
drop policy if exists "circle_message_hidden_delete" on circle_message_hidden;
create policy "circle_message_hidden_select" on circle_message_hidden for select to authenticated
  using (user_id = auth.uid());
-- Only a message you can actually see: the subquery runs under your own RLS.
create policy "circle_message_hidden_insert" on circle_message_hidden for insert to authenticated
  with check (user_id = auth.uid()
              and exists (select 1 from circle_messages m where m.id = message_id));
create policy "circle_message_hidden_delete" on circle_message_hidden for delete to authenticated
  using (user_id = auth.uid());
-- So hiding one on the phone hides it on the laptop too. See
-- circle_messages_realtime_migration for why this line is easy to forget.
alter publication supabase_realtime add table circle_message_hidden;
