-- ============================================================================
-- The Yonsei tab becomes the "school or work" tab (real-user request, 29 Sep):
-- a new account is asked at its first sign-in whether it is Yonsei, another
-- school, or work, and can give the tab its own name.
--
-- profiles.workspace_kind  'yonsei' | 'school' | 'work', NULL = not asked yet.
--                          NULL is what the client reads as "show the setup
--                          screen", so every account that exists when this
--                          runs is set to 'yonsei' -- they never see it.
-- profiles.workspace_name  the tab's own name, NULL = the kind's default
--                          (Yonsei / School / Work in the reader's language).
--
-- Own-row only, like hidden_tabs: the existing profiles_update_own policy
-- covers both columns and no column grants are involved.
--
-- Safe to re-run: the backfill only happens in the run that ADDS the column,
-- so a later re-run cannot turn a new account's NULL into 'yonsei' and skip
-- its setup screen.
-- ============================================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'profiles' AND column_name = 'workspace_kind'
  ) THEN
    ALTER TABLE public.profiles ADD COLUMN workspace_kind text;
    UPDATE public.profiles SET workspace_kind = 'yonsei';
  END IF;
END $$;

ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS workspace_name text;

ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_workspace_kind_check;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_workspace_kind_check
  CHECK (workspace_kind IS NULL OR workspace_kind IN ('yonsei', 'school', 'work'));

-- The client caps the name at 20 characters; the database agrees, and keeps
-- markup out of it the same way profiles_display_name_chars does for names.
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_workspace_name_check;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_workspace_name_check
  CHECK (workspace_name IS NULL OR (char_length(workspace_name) BETWEEN 1 AND 20 AND workspace_name !~ '[<>]'));
