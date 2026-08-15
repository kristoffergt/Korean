-- ============================================================================
-- Writing Practice: task prompts + framework for future Q53-style
-- (graph/table description) writing tasks.
--
-- Run this after new_features_migration.sql. Safe to re-run (IF NOT EXISTS).
-- ============================================================================

-- Snapshot of the full TOPIK-style task text (context paragraph + guiding
-- questions) shown when a sample was started from the topic library, so it
-- stays stable even if the in-app topic list is edited later. Null for
-- custom (self-typed) topics.
ALTER TABLE writing_samples ADD COLUMN IF NOT EXISTS task_prompt text;

-- 'essay' = Q54-style argumentative essay (600~700자, the only type in use
-- today). 'data' is reserved for a future Q53-style graph/table description
-- task (200~300자) — the app already knows how to render and character-count
-- either type, so turning that mode on later is just a matter of populating
-- the WRITING_DATA_TASKS array in the app, no further schema changes needed.
ALTER TABLE writing_samples ADD COLUMN IF NOT EXISTS task_type text NOT NULL DEFAULT 'essay';

-- Target character-count range (자, not words) shown next to the live
-- counter in the editor. Snapshotted per-sample for the same reason as
-- task_prompt above.
ALTER TABLE writing_samples ADD COLUMN IF NOT EXISTS char_min integer;
ALTER TABLE writing_samples ADD COLUMN IF NOT EXISTS char_max integer;
