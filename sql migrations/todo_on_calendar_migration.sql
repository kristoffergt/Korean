-- ============================================================================
-- A to-do can be put on the calendar, or left off it, on its own (real-user
-- request, 29 Sep: "it's good with an overall checkbox, but we should be
-- able to individually pick certain to-dos to add/leave off calendar").
--
-- todos.on_calendar  null  = follow the list's switch, profiles.todos_on_calendar
--                    true  = on the calendar whatever the switch says
--                    false = off the calendar whatever the switch says
--
-- The page only ever stores a value that DIFFERS from the switch, and the
-- switch clears every value when it is pressed: it is the overall checkbox
-- and puts every to-do the same way.
--
-- Additive and nullable, so an older page that never sends the column keeps
-- working. The existing table-wide grant and own-row update policy cover it.
-- Safe to re-run.
-- ============================================================================

alter table public.todos add column if not exists on_calendar boolean;
