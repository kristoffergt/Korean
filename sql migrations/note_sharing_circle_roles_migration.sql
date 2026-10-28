-- ============================================================================
-- Note sharing, part 2: the circle edits by default, with a level per
-- category and a per-note restriction (owner's request: "They should be
-- allowed to do everything. Be an editor ... default just full access.
-- However, you should just make it so you can restrict people from your
-- circle on specific notes if you want.").
-- Runs on top of note_sharing_migration.sql, which is already applied.
--
-- 1. THE CIRCLE'S LEVEL. link_sharing_settings.note_role, for the two note
--    categories only: 'editor' | 'commenter' | 'viewer', null = editor.
--    Resolved exactly the way shared_circle_cat resolves `enabled`: the
--    owner's per-partner row, then the owner's own default row, then
--    'editor' (circle_note_role). The core pair is not governed by
--    link_sharing_settings anywhere, so it is 'editor' here too.
--    The category check on link_sharing_settings did not include
--    'notebook_notes' (so the Notebook's circle toggle could not be stored
--    at all); it is added, and nothing else in that list changes.
-- 2. A PER-NOTE RESTRICTION. note_shares.role takes 'none' as well. An
--    explicit row always wins over the circle: 'none' hides the note from
--    that person (SELECT policies, comments, my_note_role), any other role
--    is what they get on that note.
-- 3. WRITES. The UPDATE policies already call note_editable_by_me; it now
--    means "my role on this note is editor", circle or explicit. The edit
--    guard triggers stay as they were, and so does the core-member
--    "notes update" policy on course_notes.
--
-- note_access_role, in order: owner -> 'owner'; owner pending deletion ->
-- null; an explicit note_shares row -> its role ('none' -> null); circle
-- access (shared_circle_cat) -> circle_note_role; else null.
--
-- Idempotent; safe to run again. Not applied by the session that wrote it.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Columns and constraints
-- ---------------------------------------------------------------------------
alter table public.link_sharing_settings add column if not exists note_role text;

alter table public.link_sharing_settings drop constraint if exists link_sharing_settings_note_role_check;
alter table public.link_sharing_settings add constraint link_sharing_settings_note_role_check
  check (note_role is null or (category in ('notebook_notes', 'course_notes') and note_role in ('viewer', 'commenter', 'editor')));

-- The list as it stands live, plus 'notebook_notes'.
alter table public.link_sharing_settings drop constraint if exists link_sharing_settings_category_check;
alter table public.link_sharing_settings add constraint link_sharing_settings_category_check
  check (category = any (array['study_entries', 'books', 'job_applications', 'grammar_notes', 'course_notes',
                               'writing_samples', 'recap', 'readiness', 'certifications', 'notebook_notes']));

alter table public.note_shares drop constraint if exists note_shares_role_check;
alter table public.note_shares add constraint note_shares_role_check
  check (role in ('viewer', 'commenter', 'editor', 'none'));

-- ---------------------------------------------------------------------------
-- 2. Who may do what
-- ---------------------------------------------------------------------------
-- The level the circle gives p_viewer on p_owner's notes in p_table, or null
-- when the circle does not show them that table at all. Internal.
create or replace function public.circle_note_role(p_viewer uuid, p_owner uuid, p_table text)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select case
    when shared_circle_cat(p_viewer, p_owner, p_table) is not true then null
    when p_viewer = p_owner then 'owner'
    when is_core_member(p_viewer) is true and is_core_member(p_owner) is true then 'editor'
    else coalesce(
      (select s.note_role from link_sharing_settings s
        where s.user_id = p_owner and s.target_user_id = p_viewer and s.category = p_table),
      (select s.note_role from link_sharing_settings s
        where s.user_id = p_owner and s.target_user_id = p_owner and s.category = p_table),
      'editor')
  end;
$$;
revoke all on function public.circle_note_role(uuid, uuid, text) from public, anon, authenticated;

-- The role when the note's owner is already known (policies have it on the
-- row). Internal.
create or replace function public.note_role_with_owner(p_uid uuid, p_owner uuid, p_table text, p_note_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_role text;
begin
  if p_uid is null or p_owner is null or p_note_id is null then
    return null;
  end if;
  if p_owner = p_uid then
    return 'owner';
  end if;
  if account_pending_deletion(p_owner) is true then
    return null;
  end if;
  select s.role into v_role
    from note_shares s
   where s.note_table = p_table and s.note_id = p_note_id
     and s.owner_id = p_owner and s.grantee_id = p_uid;
  if v_role is not null then
    return nullif(v_role, 'none');
  end if;
  return circle_note_role(p_uid, p_owner, p_table);
end;
$$;
revoke all on function public.note_role_with_owner(uuid, uuid, text, uuid) from public, anon, authenticated;

-- Same signature as before; internal as before.
create or replace function public.note_access_role(p_uid uuid, p_table text, p_note_id uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select note_role_with_owner(p_uid, note_owner_of(p_table, p_note_id), p_table, p_note_id);
$$;
revoke all on function public.note_access_role(uuid, text, uuid) from public, anon, authenticated;

-- A share row for the caller that gives them the note ('none' gives nothing).
create or replace function public.note_shared_with_me(p_table text, p_note_id uuid, p_owner uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() is not null
     and account_pending_deletion(p_owner) is not true
     and exists (
       select 1 from note_shares s
        where s.note_table = p_table and s.note_id = p_note_id
          and s.owner_id = p_owner and s.grantee_id = auth.uid()
          and s.role <> 'none'
     );
$$;
revoke all on function public.note_shared_with_me(text, uuid, uuid) from public, anon;
grant execute on function public.note_shared_with_me(text, uuid, uuid) to authenticated;

-- The owner has taken this note away from the caller.
create or replace function public.note_hidden_from_me(p_table text, p_note_id uuid, p_owner uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() is not null and exists (
    select 1 from note_shares s
     where s.note_table = p_table and s.note_id = p_note_id
       and s.owner_id = p_owner and s.grantee_id = auth.uid()
       and s.role = 'none'
  );
$$;
revoke all on function public.note_hidden_from_me(text, uuid, uuid) from public, anon;
grant execute on function public.note_hidden_from_me(text, uuid, uuid) to authenticated;

-- Editor on this note, from the circle or from a share.
create or replace function public.note_editable_by_me(p_table text, p_note_id uuid, p_owner uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() is not null
     and note_role_with_owner(auth.uid(), p_owner, p_table, p_note_id) = 'editor';
$$;
revoke all on function public.note_editable_by_me(text, uuid, uuid) from public, anon;
grant execute on function public.note_editable_by_me(text, uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Policies
-- ---------------------------------------------------------------------------
-- Read: the circle, unless this note is restricted for you; or a share.
alter policy notebook_notes_select on public.notebook_notes
  using (
    (shared_circle_cat(auth.uid(), user_id, 'notebook_notes')
      and public.note_hidden_from_me('notebook_notes', id, user_id) is not true)
    or public.note_shared_with_me('notebook_notes', id, user_id)
  );
alter policy course_notes_select on public.course_notes
  using (
    (shared_circle_cat(auth.uid(), user_id, 'course_notes')
      and public.note_hidden_from_me('course_notes', id, user_id) is not true)
    or public.note_shared_with_me('course_notes', id, user_id)
  );
-- The older core-member read policy on course_notes would otherwise still
-- show a restricted note to the core partner. Same rule, plus the
-- restriction; the owner's own branch is untouched.
do $$
begin
  if exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'course_notes' and policyname = 'notes select') then
    alter policy "notes select" on public.course_notes
      using (
        (auth.uid() = user_id)
        or (is_core_member(auth.uid()) and is_core_member(user_id)
            and public.note_hidden_from_me('course_notes', id, user_id) is not true)
      );
  end if;
end $$;

-- Write: the owner, or anyone whose role on the note is editor (restated;
-- the change is in note_editable_by_me). "notes update" is left alone.
alter policy notebook_notes_update on public.notebook_notes
  using (auth.uid() = user_id or public.note_editable_by_me('notebook_notes', id, user_id))
  with check (auth.uid() = user_id or public.note_editable_by_me('notebook_notes', id, user_id));
alter policy course_notes_update on public.course_notes
  using (auth.uid() = user_id or public.note_editable_by_me('course_notes', id, user_id))
  with check (auth.uid() = user_id or public.note_editable_by_me('course_notes', id, user_id));
