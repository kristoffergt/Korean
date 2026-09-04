-- Texting your circle, as a group and one to one (real-user request: "make
-- it possible to text your circle too, in a group and individually").
--
-- One table for both. A NULL recipient_id is the group message -- it goes to
-- "everyone who shares with you", which is the app's existing idea of a
-- circle (shared_circle) rather than a new membership concept to keep in
-- step with link groups and core members. A set recipient_id is a direct
-- message between exactly two people.
--
-- Read is the only place the two differ, and the policy says so plainly:
-- your own messages, messages addressed to you, and group messages from
-- someone in your circle. Note the asymmetry that follows and is intended:
-- a group message is readable by the SENDER'S circle, so what you send goes
-- to the people you share with, not to some group id that might drift.
create table circle_messages (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references profiles(id) on delete cascade,
  recipient_id uuid references profiles(id) on delete cascade,
  body text not null,
  created_at timestamptz not null default now(),
  constraint circle_messages_body_len check (length(btrim(body)) between 1 and 4000),
  constraint circle_messages_not_self check (recipient_id is null or recipient_id <> sender_id)
);
create index circle_messages_created_idx on circle_messages(created_at);
create index circle_messages_sender_idx on circle_messages(sender_id, created_at);
create index circle_messages_recipient_idx on circle_messages(recipient_id, created_at);
alter table circle_messages enable row level security;

create policy "circle_messages_select" on circle_messages for select to authenticated
  using (
    sender_id = auth.uid()
    or recipient_id = auth.uid()
    or (recipient_id is null and shared_circle(auth.uid(), sender_id))
  );
-- You may only address someone you actually share with, so an account
-- cannot be messaged by a stranger who happens to know its id.
create policy "circle_messages_insert" on circle_messages for insert to authenticated
  with check (
    sender_id = auth.uid()
    and (recipient_id is null or shared_circle(auth.uid(), recipient_id))
  );
-- Delete your own only: taking back what you said is yours to do, removing
-- what somebody else said is not.
create policy "circle_messages_delete" on circle_messages for delete to authenticated
  using (sender_id = auth.uid());

-- Where each person has read up to, per thread. `thread` is the other
-- person's id for a direct thread and the literal '__circle__' for the
-- group one, which is the same key the client uses, so unread counts need
-- no second notion of what a thread is.
create table circle_message_reads (
  user_id uuid not null references profiles(id) on delete cascade,
  thread text not null,
  last_read_at timestamptz not null default now(),
  primary key (user_id, thread)
);
alter table circle_message_reads enable row level security;
create policy "circle_message_reads_own" on circle_message_reads for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
