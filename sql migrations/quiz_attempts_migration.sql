-- ============================================================================
-- Grammar quiz attempt history.
--
-- Purely personal — each user's own quiz scores are visible only to
-- themselves, not shared with their core partner or anyone else (unlike
-- most other data in this app). Used for the small "Your quiz history"
-- fold-out inside the Grammar quiz card (best score, attempt count,
-- average, and the last 10 attempts).
--
-- Safe to re-run. No dependency on other migrations.
-- ============================================================================

CREATE TABLE IF NOT EXISTS quiz_attempts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  score integer NOT NULL,
  total integer NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE quiz_attempts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "quiz_attempts_select" ON quiz_attempts;
CREATE POLICY "quiz_attempts_select" ON quiz_attempts FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "quiz_attempts_insert" ON quiz_attempts;
CREATE POLICY "quiz_attempts_insert" ON quiz_attempts FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);
