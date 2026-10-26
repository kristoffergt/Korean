-- @mentions in messages (real-user request: "Should be able to @mention the
-- other person. Should be a bigger type of notification, more noticable").
--
-- The client writes WHO is mentioned as ids, picked from the people in the
-- conversation, alongside the "@Name" it puts in the text. Names are not
-- unique and can change, so the text alone could not say who was meant.
--
-- A trigger turns each into a 'chat_mention' notification, which the existing
-- push trigger on notifications then sends to their devices. It only ever
-- notifies somebody who can see the message, so listing a stranger's id does
-- nothing, and never the sender.

alter table circle_messages add column if not exists mentions uuid[] not null default '{}';

alter table circle_messages drop constraint if exists circle_messages_mentions_size;
alter table circle_messages add constraint circle_messages_mentions_size
  check (coalesce(array_length(mentions, 1), 0) <= 20);

create or replace function notify_circle_mentions()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  target uuid;
  sender_name text;
begin
  if new.mentions is null or coalesce(array_length(new.mentions, 1), 0) = 0 then return new; end if;
  select display_name into sender_name from profiles where id = new.sender_id;
  for target in select distinct u from unnest(new.mentions) as u loop
    continue when target is null or target = new.sender_id;
    continue when not can_see_circle_message(target, new.sender_id, new.recipient_id, new.group_id);
    continue when not wants_in_app_notification(target, 'chat_mention');
    insert into notifications (user_id, type, title, body, params)
    values (target, 'chat_mention',
            coalesce(sender_name, 'Someone') || ' mentioned you',
            left(coalesce(nullif(btrim(new.body), ''), new.attachment_name, ''), 300),
            jsonb_build_object('message_id', new.id, 'sender_id', new.sender_id,
                               'name', sender_name, 'group_id', new.group_id,
                               'direct', new.recipient_id is not null));
  end loop;
  return new;
end;
$$;
revoke all on function notify_circle_mentions() from public, anon, authenticated;

drop trigger if exists circle_messages_notify_mentions on circle_messages;
create trigger circle_messages_notify_mentions
  after insert on circle_messages
  for each row execute function notify_circle_mentions();
