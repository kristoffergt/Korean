-- Fix: grammar point numbers need two corrections.
--
-- 1) They were originally generated with a Python sort, which orders
--    punctuation ('(', '/', etc.) differently than Postgres does — that
--    mismatch is why numbers appeared scattered when browsing the list in
--    the app (which loads rows via ORDER BY pattern).
-- 2) They were numbered in one global alphabetical sweep across BOTH
--    levels mixed together, instead of per-section. Since the app displays
--    Intermediate and Advanced as separate groups, the numbering should be
--    too: Intermediate gets 1..74, Advanced continues 75..123.
--
-- This recomputes the number column directly in Postgres so both are fixed
-- at once: each level is sorted with the same ordering the app's own query
-- uses (`.order('pattern', {ascending:true})`), and Advanced picks up
-- immediately where Intermediate leaves off.
-- The unique index on `number` (from the earlier numbering migration)
-- checks each row as it's written, so reassigning numbers in place would
-- collide with whatever old value still sits in another row mid-update.
-- Drop it first, update, then recreate it.
DROP INDEX IF EXISTS grammar_points_number_idx;

WITH ordered AS (
  SELECT id, level,
    ROW_NUMBER() OVER (PARTITION BY level ORDER BY pattern ASC) AS level_rn
  FROM grammar_points
),
intermediate_count AS (
  SELECT count(*) AS n FROM grammar_points WHERE level = 'intermediate'
)
UPDATE grammar_points g
SET number = CASE
  WHEN o.level = 'intermediate' THEN o.level_rn
  ELSE (SELECT n FROM intermediate_count) + o.level_rn
END
FROM ordered o
WHERE g.id = o.id;

CREATE UNIQUE INDEX IF NOT EXISTS grammar_points_number_idx ON grammar_points(number);

-- Sanity check: intermediate should be 1..74, advanced should be 75..123,
-- with no gaps or dupes anywhere.
SELECT level, count(*) AS total, min(number) AS min_num, max(number) AS max_num, count(DISTINCT number) AS distinct_nums
FROM grammar_points
GROUP BY level;

-- Visual check: pattern order within each level should match number order.
SELECT number, level, pattern FROM grammar_points ORDER BY level, pattern ASC LIMIT 20;
