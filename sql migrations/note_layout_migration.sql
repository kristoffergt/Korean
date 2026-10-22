-- Notes can be dragged into place, sub-categories nest, and the course,
-- header and sub-category headings can be dragged into an order of their own
-- (real-user request: "add subcategories ... since subcats can have subcats",
-- and "freely drag around the subcats and the bigger overall categories").
--
-- 1. A nested sub-category is stored on the note as a PATH, its names joined
--    by "/" ("Week 1/Grammar"). Each name is still at most 60 characters and
--    the client stops at five levels, so a path is at most 5 x 60 + 4 = 304
--    characters; the old 60-character ceiling would refuse any nesting.
alter table public.course_notes drop constraint if exists course_notes_subcategory_check;
alter table public.course_notes
  add constraint course_notes_subcategory_check
  check (subcategory is null or char_length(subcategory) between 1 and 320);
alter table public.notebook_notes drop constraint if exists notebook_notes_subcategory_check;
alter table public.notebook_notes
  add constraint notebook_notes_subcategory_check
  check (subcategory is null or char_length(subcategory) between 1 and 320);

-- 2. The ORDER of the headings, and the sub-categories made before any note
--    is in them, belong to the person arranging them: the notes are shared in
--    the circle, but how each person lays out their view of them is not.
--    { "course": { "groups": [...], "subs": { "<group>": ["path", ...] } },
--      "notebook": { ... } }. Own-row update only, like every other profile
--    preference; `authenticated` already holds a table-wide UPDATE grant.
alter table public.profiles
  add column if not exists note_layout jsonb not null default '{}'::jsonb;
