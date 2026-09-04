-- Live delivery. A postgres_changes subscription receives NOTHING unless
-- the table is in the supabase_realtime publication -- the subscription
-- still reports SUBSCRIBED, so the failure is silent and looks like the
-- client's fault (real-user report: "she texted me and it didn't get to me,
-- I have to refresh"). Every other realtime table in this project is in the
-- publication; circle_messages was added after the fact.
alter publication supabase_realtime add table circle_messages;
