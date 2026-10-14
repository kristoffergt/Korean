-- Ten more reactions (real-user request: "make them a lot cooler and add like
-- 10 more"). The six that exist keep their keys, so every reaction already on
-- a message still means what it meant; only the drawings change, and those
-- live in the client.
--
-- New keys: fire, hundred, clap, party, hearteyes, cool, think, fingerheart
-- (손하트), skull ("I'm dead", from laughing), angry.
--
-- Everything else about the function is circle_message_actions' own: one
-- reaction per person, written in the caller's own name, refused on anything
-- that is not a message.
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

revoke all on function set_circle_message_reaction(uuid, text) from public, anon;
grant execute on function set_circle_message_reaction(uuid, text) to authenticated;
