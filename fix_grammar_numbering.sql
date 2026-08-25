-- Fix: grammar point numbers were originally generated with a Python sort,
-- which orders punctuation ('(', '/', etc.) differently than Postgres does.
-- That mismatch is why numbers appeared scattered / skipped when browsing
-- the list in the app (which loads rows via ORDER BY pattern).
--
-- This recomputes the number column directly in Postgres, using the exact
-- same ordering the app's own query uses (`.order('pattern', {ascending:true})`),
-- so the numbers are guaranteed to run 1..N in the order you actually see
-- entries on screen.
WITH numbered AS (
  SELECT id, ROW_NUMBER() OVER (ORDER BY pattern ASC) AS rn
  FROM grammar_points
)
UPDATE grammar_points g
SET number = numbered.rn
FROM numbered
WHERE g.id = numbered.id;

-- Sanity check: should return 123 rows, numbers 1..123, no gaps or dupes.
SELECT count(*) AS total, min(number) AS min_num, max(number) AS max_num, count(DISTINCT number) AS distinct_nums
FROM grammar_points;

-- Visual check: pattern order should match number order exactly.
SELECT number, pattern FROM grammar_points ORDER BY pattern ASC LIMIT 20;
