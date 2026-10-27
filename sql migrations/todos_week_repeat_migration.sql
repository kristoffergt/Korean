-- To-dos for a WEEK, a MONTH or a YEAR rather than a day, and to-dos that
-- repeat. (Applied 27 Oct 2026.)
--
-- todos.scope        null for a day (due_date) or an undated to-do; otherwise
--                    'week' | 'month' | 'year'.
-- todos.scope_start  the first day of that period: the Sunday a week starts on
--                    (the calendar's own week start), the 1st of a month, 1 Jan.
--                    Never set together with due_date.
-- todos.repeat       'daily' | 'weekly' | 'monthly' | 'yearly'. Ticking a
--                    repeating to-do off makes the next one (the app does that;
--                    the database only holds the answer).
alter table public.todos drop constraint if exists todos_day_or_week;
alter table public.todos drop constraint if exists todos_repeat_ok;
alter table public.todos drop constraint if exists todos_scope_ok;
alter table public.todos drop column if exists due_week;
alter table public.todos add column if not exists scope text;
alter table public.todos add column if not exists scope_start date;
alter table public.todos add column if not exists repeat text;
alter table public.todos add constraint todos_scope_ok check (
  (scope is null and scope_start is null)
  or (scope in ('week','month','year') and scope_start is not null and due_date is null));
alter table public.todos add constraint todos_repeat_ok
  check (repeat is null or repeat in ('daily','weekly','monthly','yearly'));
