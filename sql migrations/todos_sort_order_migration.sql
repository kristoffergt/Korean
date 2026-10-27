-- The order a person has dragged their to-dos into. (Applied 27 Oct 2026.)
-- Null until a to-do has been placed by hand or added after this shipped;
-- the app sorts nulls by time and creation, before the ordered ones, and
-- renumbers a whole group (one day, week, month or year) when one is dropped.
alter table public.todos add column if not exists sort_order double precision;
