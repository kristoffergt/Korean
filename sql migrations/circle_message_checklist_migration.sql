-- A message can be a checklist that everyone in the conversation ticks off
-- (real-user request: "add the ability to send a checklist in messages. Both
-- people should be able to interact and mark it. When marked, whoever marked
-- it, their first letter in their personal color is added ... Any list (any
-- message) should be able to be a checklist. New items are just a new line.")
--
-- The items ARE the message's own lines, so nothing new is stored about them:
-- `checklist` says the lines are to be read as items, and `checks` says which
-- of them are ticked and by whom, keyed by the item's index among the
-- non-blank lines -- {"2": {"by": "<uuid>", "at": "<timestamptz>"}}. The body
-- can never be edited (there is no UPDATE policy and this adds none), so an
-- index means the same line for the life of the message.
alter table circle_messages
  add column if not exists checklist boolean not null default false,
  add column if not exists checks jsonb not null default '{}'::jsonb;

-- Ticking is done ONLY through the two functions below, never by an UPDATE
-- from the client. An update policy would hand every reader the body too, and
-- even scoped to these columns it would let a client write {"by": somebody
-- else} into the jsonb. Here the function writes the caller's own id itself.
--
-- Who may: exactly whoever may READ the message -- the predicate is
-- circle_messages_select's own, repeated rather than paraphrased, so the two
-- cannot drift into "you can see it but not tick it" or the reverse.

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
  if not (m.sender_id = uid
          or m.recipient_id = uid
          or (m.recipient_id is null and shared_circle(uid, m.sender_id))) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if not m.checklist then raise exception 'not a checklist' using errcode = '22023'; end if;
  -- Non-blank lines, which is what the client counts as items.
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

-- Any message can BECOME a checklist after it is sent, by anyone who can read
-- it: a list somebody typed as plain text is the commonest way one arrives.
-- Turning it back into plain text is refused once anything is ticked, so a
-- list in progress cannot be wiped out from under the other person; the ticks
-- are kept either way, so turning it on again would bring them back.
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
  if not (m.sender_id = uid
          or m.recipient_id = uid
          or (m.recipient_id is null and shared_circle(uid, m.sender_id))) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if btrim(m.body) = '' then raise exception 'nothing to tick' using errcode = '22023'; end if;
  if not p_on and m.checks <> '{}'::jsonb then
    raise exception 'items are ticked' using errcode = '22023';
  end if;
  update circle_messages set checklist = p_on where id = p_message;
  return p_on;
end;
$$;

revoke all on function set_circle_message_check(uuid, integer, boolean) from public, anon;
revoke all on function set_circle_message_checklist(uuid, boolean) from public, anon;
grant execute on function set_circle_message_check(uuid, integer, boolean) to authenticated;
grant execute on function set_circle_message_checklist(uuid, boolean) to authenticated;

-- Live: circle_messages is already in the supabase_realtime publication
-- (circle_messages_realtime_migration), so these UPDATEs reach the other
-- person through postgres_changes with the table's own SELECT policy applied.
-- The client only ever subscribed to INSERT; it listens for UPDATE now too.
