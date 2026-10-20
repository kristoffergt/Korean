-- A note can sit under a sub-category inside its group (real-user request:
-- "and add sub categories" to the notes list). The group is the course or
-- the custom header, as before; the sub-category is a second, optional level
-- under it, typed freely like the header. Null is "no sub-category".
-- Same 60-character ceiling the group chats' names use: a sub-heading longer
-- than that is a sentence, not a heading.
alter table public.course_notes
  add column if not exists subcategory text
  check (subcategory is null or char_length(subcategory) between 1 and 60);
alter table public.notebook_notes
  add column if not exists subcategory text
  check (subcategory is null or char_length(subcategory) between 1 and 60);
