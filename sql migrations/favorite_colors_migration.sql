-- Favourite name colours (real-user request: "if I really like this one and
-- wanna save it for later ... so I can change my color, and still have that
-- one later"). Saved from the popover the name pill in the header opens, most
-- recent first, twelve at most; the app writes the whole list each time.
--
-- Until this has been run the app keeps the list on each device instead
-- (localStorage, keyed by the account) and carries it up to this column the
-- first time the column is there. Written through the same own-row update the
-- app already uses for profiles.color, so no new policy is needed.
--
-- Applied live via apply_migration as "favorite_colors" on 12 Sep 2026; this
-- file mirrors that for the record.

alter table public.profiles
  add column if not exists favorite_colors text[] not null default '{}';
