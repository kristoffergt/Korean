-- ============================================================================
-- Spaced repetition scheduling for grammar (SM-2, the same algorithm Anki is
-- loosely built on). Sits ALONGSIDE the existing manual reviewed/not-reviewed
-- toggle (grammar_review_overrides) rather than replacing it — this table is
-- purely additive.
--
-- Fully private, own-only, exactly like grammar_review_overrides: nobody
-- else (not even a core partner) needs to see your review schedule.
--
-- Fed automatically by the Grammar quiz: answering a question correctly
-- grows that pattern's interval, answering incorrectly resets it to due
-- again tomorrow, so quiz-taking and spaced repetition are one loop instead
-- of two separate systems to maintain.
--
-- Safe to re-run. No dependency on other migrations.
-- ============================================================================

CREATE TABLE IF NOT EXISTS grammar_srs (
  user_id uuid NOT NULL,
  pattern_id text NOT NULL,
  ease_factor numeric NOT NULL DEFAULT 2.5,
  interval_days numeric NOT NULL DEFAULT 0,
  repetitions integer NOT NULL DEFAULT 0,
  due_date date NOT NULL DEFAULT CURRENT_DATE,
  last_reviewed_at timestamptz,
  last_quality integer,
  PRIMARY KEY (user_id, pattern_id)
);
ALTER TABLE grammar_srs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "grammar_srs_select" ON grammar_srs;
CREATE POLICY "grammar_srs_select" ON grammar_srs FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "grammar_srs_insert" ON grammar_srs;
CREATE POLICY "grammar_srs_insert" ON grammar_srs FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "grammar_srs_update" ON grammar_srs;
CREATE POLICY "grammar_srs_update" ON grammar_srs FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);
