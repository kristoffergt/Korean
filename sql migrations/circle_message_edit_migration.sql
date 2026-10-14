-- A message can be edited by whoever sent it (real-user request: "There should
-- be an edit button on messages"). This ends the rule the checklist migration
-- leaned on -- "the body can never be edited, so an index means the same line
-- for the life of the message" -- so an edit has to say what happens to the
-- ticks, and it says it here, in the one place an edit can happen.
--
-- `edited_at` is when it was last changed, null for a message never edited.
-- The bubble says "edited" off it; nothing keeps the earlier text.
alter table circle_messages
  add column if not exists edited_at timestamptz;

-- A client cannot insert a message that claims to have been edited.
drop policy if exists "circle_messages_insert" on circle_messages;
create policy "circle_messages_insert" on circle_messages for insert to authenticated
  with check (
    sender_id = auth.uid()
    and (recipient_id is null or shared_circle(auth.uid(), recipient_id))
    and kind = 'text' and ref_message is null
    and checks = '{}'::jsonb and reactions = '{}'::jsonb
    and edited_at is null
  );

-- What each checklist item SAYS, in order: the non-blank lines (the same count
-- set_circle_message_check uses), with a pasted marker ("- ", "1.", "[ ]")
-- taken off when something is left after it -- exactly what the client draws
-- beside the tick box (checklistItemText).
create or replace function circle_message_item_keys(p_body text)
returns text[]
language sql
immutable
set search_path = public
as $$
  select coalesce(array_agg(
           case when btrim(regexp_replace(btrim(l.line), E'^(?:[-*+•·–—]|\\[[ xX]?\\]|[0-9]{1,3}[.)])\\s+', '')) <> ''
                then btrim(regexp_replace(btrim(l.line), E'^(?:[-*+•·–—]|\\[[ xX]?\\]|[0-9]{1,3}[.)])\\s+', ''))
                else btrim(l.line) end
           order by l.n), '{}'::text[])
    from regexp_split_to_table(coalesce(p_body, ''), E'\r?\n') with ordinality as l(line, n)
   where btrim(l.line) <> '';
$$;
revoke all on function circle_message_item_keys(text) from public, anon, authenticated;

-- The ONLY way to edit. A function, not an UPDATE policy, for the reason the
-- tick functions give: a policy would let a client write the checks and the
-- reactions as well as the body, in anybody's name.
--
-- TICKS FOLLOW THEIR ITEM, not their position. A tick is kept on the item
-- whose text it was on -- at the same place if that item is still there,
-- else wherever that text now is -- and an item that is gone takes its tick
-- with it. So fixing a typo in item 3, or adding item 6, leaves everybody's
-- progress where it was; rewording an item that was ticked clears that one
-- tick, which is right, since it is no longer the thing that was done.
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
  if m.sender_id <> uid then raise exception 'not allowed' using errcode = '42501'; end if;
  if m.kind <> 'text' then raise exception 'not a message' using errcode = '22023'; end if;
  if length(new_body) > 4000 then raise exception 'too long' using errcode = '22001'; end if;
  if new_body = '' and m.attachment_path is null then
    raise exception 'empty' using errcode = '22023';
  end if;
  -- Nothing changed: not marked as edited.
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
  -- A checklist edited down to no lines at all (a file whose caption was
  -- cleared) has nothing left to tick.
  still_list := m.checklist and coalesce(array_length(new_keys, 1), 0) > 0;
  update circle_messages
     set body = new_body, edited_at = stamp, checks = next_checks, checklist = still_list
   where id = p_message;
  return jsonb_build_object('body', new_body, 'edited_at', stamp,
                            'checks', next_checks, 'checklist', still_list);
end;
$$;

revoke all on function edit_circle_message(uuid, text) from public, anon;
grant execute on function edit_circle_message(uuid, text) to authenticated;

-- Live: the UPDATE reaches the other person through the publication the table
-- is already in; the client now takes body and edited_at from it as well.
