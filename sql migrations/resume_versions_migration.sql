-- ============================================================================
-- More than one resume: besides 'main' (/resume), resume_content holds one row
-- per version shown at /kr/resume ('kr-en', 'kr-ko') and /vn/resume ('vn-en',
-- 'vn-vi'). Each row can carry the public link to its own PDF, written by the
-- upload in Account settings, so a page shows a download only for a version
-- that has one. The content rows themselves are written from Account
-- settings (or once by hand), never from a migration: they hold contact
-- details, and this folder is public.
--
-- Safe to re-run.
-- ============================================================================

alter table resume_content add column if not exists pdf_url text;
