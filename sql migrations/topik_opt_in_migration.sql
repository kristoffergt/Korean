-- TOPIK becomes an opt-in (real-user report: "all the TOPIK, I realize,
-- it's not for everyone"). show_topik gates the countdown card and, when
-- on, the app creates REAL events rows for the TOPIK dates (tagged via
-- events.topik_key so toggling off can find and remove exactly them) --
-- real rows are what makes recaps, 1-day-ahead reminders and the calendar
-- all work through the existing pipelines with no backend changes.
alter table profiles add column show_topik boolean not null default false;
alter table events add column topik_key text;
