-- Replies, and what an edited message used to say (real-user requests: "Add
-- replies to messages." and "Add show edited message history.").
--
-- reply_to: the message this one answers. ON DELETE SET NULL, so deleting the
-- original for everyone leaves the reply standing with nothing to quote. A
-- reply may only name a text message in the SAME conversation, which the
-- insert policy checks through circle_reply_ok: otherwise a reply could quote
-- a message from a conversation the replier cannot see.
--
-- edit_history: [{"body": ..., "at": ...}], oldest first, written only by
-- edit_circle_message (the table has no UPDATE policy) and required empty on
-- insert, so nobody can send a message with a made-up past.

alter table circle_messages
  add column if not exists reply_to uuid references circle_messages(id) on delete set null,
  add column if not exists edit_history jsonb not null default '[]'::jsonb;

create index if not exists circle_messages_reply_to_idx on circle_messages(reply_to) where reply_to is not null;

create or replace function circle_reply_ok(p_reply uuid, p_sender uuid, p_recipient uuid, p_group uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from circle_messages m
     where m.id = p_reply
       and m.kind = 'text'
       and can_see_circle_message(p_sender, m.sender_id, m.recipient_id, m.group_id)
       and case
             when p_group is not null then m.group_id = p_group
             when p_recipient is null then m.group_id is null and m.recipient_id is null
             else m.group_id is null and m.recipient_id is not null
                  and ((m.sender_id = p_sender and m.recipient_id = p_recipient)
                    or (m.sender_id = p_recipient and m.recipient_id = p_sender))
           end
  );
$$;
revoke all on function circle_reply_ok(uuid, uuid, uuid, uuid) from public, anon;
grant execute on function circle_reply_ok(uuid, uuid, uuid, uuid) to authenticated;

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
    and edit_history = '[]'::jsonb
    and (reply_to is null or circle_reply_ok(reply_to, sender_id, recipient_id, group_id))
  );

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
  hist jsonb;
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
                              'checks', m.checks, 'checklist', m.checklist,
                              'edit_history', m.edit_history);
  end if;
  -- What it said before this edit, and since when: the first version is
  -- dated by when it was sent, every later one by the edit that made it.
  -- Twenty is plenty to read back and keeps the row small.
  hist := coalesce(m.edit_history, '[]'::jsonb)
       || jsonb_build_array(jsonb_build_object('body', m.body, 'at', coalesce(m.edited_at, m.created_at)));
  if jsonb_array_length(hist) > 20 then
    select coalesce(jsonb_agg(e order by n), '[]'::jsonb) into hist
      from jsonb_array_elements(hist) with ordinality as t(e, n)
     where n > jsonb_array_length(hist) - 20;
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
     set body = new_body, edited_at = stamp, checks = next_checks, checklist = still_list,
         edit_history = hist
   where id = p_message;
  return jsonb_build_object('body', new_body, 'edited_at', stamp,
                            'checks', next_checks, 'checklist', still_list,
                            'edit_history', hist);
end;
$$;
