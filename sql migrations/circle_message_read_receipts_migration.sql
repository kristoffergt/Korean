-- Read receipts: a check for sent, an eye once it has been read (real-user
-- request). Until now a person could only SELECT their own row in
-- circle_message_reads, so there was no way to know whether what you sent
-- had been read. Circle members may now see each other's marker, which is
-- precisely what a read receipt is -- it exposes how far through a thread
-- somebody has got and nothing else.
--
-- Writing stays own-row-only, so nobody can mark a thread read on somebody
-- else's behalf: the old ALL policy is replaced by one SELECT that reaches
-- the circle and three write policies that do not.
drop policy if exists "circle_message_reads_own" on circle_message_reads;

create policy "circle_message_reads_select" on circle_message_reads for select to authenticated
  using (user_id = auth.uid() or shared_circle(auth.uid(), user_id));
create policy "circle_message_reads_insert" on circle_message_reads for insert to authenticated
  with check (user_id = auth.uid());
create policy "circle_message_reads_update" on circle_message_reads for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "circle_message_reads_delete" on circle_message_reads for delete to authenticated
  using (user_id = auth.uid());

-- The eye must appear the moment they read it, not on the next reload. See
-- circle_messages_realtime_migration for why this line is easy to forget
-- and silent when missing.
alter publication supabase_realtime add table circle_message_reads;
