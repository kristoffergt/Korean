-- Required for the client's subscribeJobBoardRealtime() (index.html) to
-- actually receive postgres_changes events on yonsei_jobboard_items --
-- RLS alone doesn't turn on Realtime for a table, it also has to be added
-- to the supabase_realtime publication.
--
-- Applied live via apply_migration as "jobboard_items_realtime" -- this
-- file mirrors that for the record.

alter publication supabase_realtime add table public.yonsei_jobboard_items;
