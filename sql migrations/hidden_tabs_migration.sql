-- ============================================================================
-- Generalizes the one-off "Show Yonsei Boards tab" toggle
-- (show_yonsei_boards, see yonsei_boards_migration.sql) into a single
-- mechanism that can hide any top-level tab or sub-tab, per the ask for
-- a real "manage visible tabs" settings menu instead of a single bespoke
-- checkbox.
--
-- profiles.hidden_tabs text[]: own-row-only, same pattern as every other
-- personal display preference in this app -- plain client .update(), no
-- RPC, no new RLS policy needed (profiles already has an own-row UPDATE
-- policy). Keys are "top-level" (e.g. 'calendar', 'study', 'yonsei',
-- 'reading', 'jobs') or "group.sub" (e.g. 'study.grammar',
-- 'yonsei.boards', 'jobs.jobboard') -- see the client's TAB_STRUCTURE
-- constant for the authoritative list. A key's absence from the array
-- means visible (default state for everyone, including new signups, is
-- everything visible).
--
-- show_yonsei_boards is left in place (not dropped -- dropping columns is
-- a needless one-way door for what's now dead data) but no longer read or
-- written by the client; existing false values are migrated forward once
-- here so nobody's current "Boards tab hidden" preference silently resets
-- to visible.
--
-- Safe to re-run.
-- ============================================================================

ALTER TABLE profiles ADD COLUMN IF NOT EXISTS hidden_tabs text[] NOT NULL DEFAULT '{}';

UPDATE profiles
SET hidden_tabs = array_append(hidden_tabs, 'yonsei.boards')
WHERE show_yonsei_boards = false
  AND NOT ('yonsei.boards' = ANY(hidden_tabs));
