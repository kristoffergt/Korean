-- Checklists that split on more than new lines (real-user request: "+", ",",
-- "&" and "and" should also be able to make a list, with an option to choose
-- what separates the points).
--
-- The separators are stored ON THE MESSAGE when it is made a checklist, not
-- read from anybody's settings afterwards: ticks are kept by item INDEX, so
-- the way a body splits into items has to be fixed for as long as the list
-- lives, and the same for everybody looking at it. null means new lines only,
-- which is what every existing checklist is.
--
-- The client's checklistItems() applies exactly these patterns, case
-- insensitively, after splitting on new lines.

alter table circle_messages add column if not exists checklist_split text[];

alter table circle_messages drop constraint if exists circle_messages_checklist_split_ok;
alter table circle_messages add constraint circle_messages_checklist_split_ok
  check (checklist_split is null
         or checklist_split <@ array['plus','comma','amp','and','semicolon','slash']::text[]);

-- One alternation of the chosen separators, or null for none.
create or replace function circle_message_split_pattern(p_split text[])
returns text
language sql
immutable
set search_path = public
as $$
  select nullif(string_agg(case s
           when 'plus'      then E'\\s*\\+\\s*'
           when 'comma'     then E'\\s*,\\s*'
           when 'amp'       then E'\\s*&\\s*'
           when 'and'       then E'\\s+(?:and|og|và|그리고)\\s+'
           when 'semicolon' then E'\\s*;\\s*'
           when 'slash'     then E'\\s*/\\s*'
         end, '|'), '')
    from unnest(coalesce(p_split, '{}'::text[])) as s;
$$;

-- The items of a body, in order: non-blank lines, each split further on the
-- chosen separators. The single source for the count and the keys.
create or replace function circle_message_items(p_body text, p_split text[])
returns text[]
language sql
immutable
set search_path = public
as $$
  select coalesce(array_agg(btrim(p.piece) order by l.n, p.k), '{}'::text[])
    from regexp_split_to_table(coalesce(p_body, ''), E'\r?\n') with ordinality as l(line, n)
    cross join lateral regexp_split_to_table(
      l.line, coalesce(circle_message_split_pattern(p_split), '$^'), 'i') with ordinality as p(piece, k)
   where btrim(p.piece) <> '';
$$;

create or replace function circle_message_item_keys(p_body text, p_split text[])
returns text[]
language sql
immutable
set search_path = public
as $$
  select coalesce(array_agg(
           case when btrim(regexp_replace(it, E'^(?:[-*+•·–—]|\\[[ xX]?\\]|[0-9]{1,3}[.)])\\s+', '')) <> ''
                then btrim(regexp_replace(it, E'^(?:[-*+•·–—]|\\[[ xX]?\\]|[0-9]{1,3}[.)])\\s+', ''))
                else it end
           order by n), '{}'::text[])
    from unnest(circle_message_items(p_body, p_split)) with ordinality as t(it, n);
$$;
-- The old one-argument form stays as new-lines-only, for anything still calling it.
create or replace function circle_message_item_keys(p_body text)
returns text[]
language sql
immutable
set search_path = public
as $$ select circle_message_item_keys(p_body, null::text[]); $$;

revoke all on function circle_message_split_pattern(text[]) from public, anon, authenticated;
revoke all on function circle_message_items(text, text[]) from public, anon, authenticated;
revoke all on function circle_message_item_keys(text, text[]) from public, anon, authenticated;
revoke all on function circle_message_item_keys(text) from public, anon, authenticated;

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
  n_items := coalesce(array_length(circle_message_items(m.body, m.checklist_split), 1), 0);
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

-- Turning a message into a checklist now says how it splits. Turning it off
-- clears that, so the next time it is turned on it is asked again.
drop function if exists set_circle_message_checklist(uuid, boolean);
create or replace function set_circle_message_checklist(p_message uuid, p_on boolean, p_split text[] default null)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  m circle_messages%rowtype;
  split text[];
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
  if m.checks <> '{}'::jsonb then
    raise exception 'items are ticked' using errcode = '22023';
  end if;
  select nullif(array_agg(distinct s order by s), '{}'::text[]) into split
    from unnest(coalesce(p_split, '{}'::text[])) as s
   where s = any (array['plus','comma','amp','and','semicolon','slash']);
  update circle_messages
     set checklist = p_on, checklist_split = case when p_on then split else null end
   where id = p_message;
  return p_on;
end;
$$;
revoke all on function set_circle_message_checklist(uuid, boolean, text[]) from public, anon;
grant execute on function set_circle_message_checklist(uuid, boolean, text[]) to authenticated;

-- edit_circle_message as in circle_message_replies_history_migration.sql,
-- with the keys read through the message's own separators.
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
  hist := coalesce(m.edit_history, '[]'::jsonb)
       || jsonb_build_array(jsonb_build_object('body', m.body, 'at', coalesce(m.edited_at, m.created_at)));
  if jsonb_array_length(hist) > 20 then
    select coalesce(jsonb_agg(e order by n), '[]'::jsonb) into hist
      from jsonb_array_elements(hist) with ordinality as t(e, n)
     where n > jsonb_array_length(hist) - 20;
  end if;
  new_keys := circle_message_item_keys(new_body, m.checklist_split);
  if m.checks <> '{}'::jsonb then
    old_keys := circle_message_item_keys(m.body, m.checklist_split);
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
