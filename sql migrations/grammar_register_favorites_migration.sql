-- ============================================================================
-- Adds two new features to the Grammar reference:
--   1) A colloquial <-> written "register" slider per grammar point (same
--      shape as the existing difficulty/formality/politeness sliders).
--   2) Per-user favorites (star a pattern as especially difficult/important,
--      then sort the list to bring favorites to the top).
--
-- Safe to re-run. Run after new_features_migration.sql and
-- topik_numbering_migration.sql.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1) Register slider: 0 = strongly colloquial/spoken, 100 = strongly
-- written/literary. Values below are a best-effort linguistic estimate per
-- pattern (same editable-metadata treatment as difficulty/formality/
-- politeness) — nudge any of them in the SQL editor if a pattern feels off.
-- ---------------------------------------------------------------------------
ALTER TABLE grammar_points ADD COLUMN IF NOT EXISTS colloquial integer NOT NULL DEFAULT 50;

UPDATE grammar_points AS g
SET colloquial = v.colloquial
FROM (VALUES
  ('아무리-기로서니', 65),
  ('으-련만-으-련마는', 75),
  ('으-ㄹ-듯하다', 55),
  ('으-ㄹ-리가-없다', 40),
  ('으-ㄹ-수밖에-없다', 45),
  ('으-ㄹ-정도로', 50),
  ('으-ㄹ걸-요', 10),
  ('으-ㄹ까-하다', 25),
  ('으-ㄹ수록', 50),
  ('으-ㄹ지도-모르다', 45),
  ('으-나-마나', 25),
  ('으-랴-으-랴', 70),
  ('으-려고', 45),
  ('으-려나-보다', 15),
  ('으-려다가', 35),
  ('으-려던-참이다', 35),
  ('으-려면', 45),
  ('으-로서-으-로써', 75),
  ('으-리라-고', 85),
  ('으-면-몰라도', 30),
  ('으-면서', 50),
  ('이-나마', 70),
  ('ㄴ-는다기보다-는', 60),
  ('거나', 45),
  ('거니와', 85),
  ('거든-요', 10),
  ('건만-건마는', 80),
  ('게', 45),
  ('게-되다', 45),
  ('고-나서', 45),
  ('고-말다', 50),
  ('고-해서', 25),
  ('고-요', 15),
  ('고도', 60),
  ('고말고-요', 10),
  ('고서야-아-어서야', 70),
  ('고자-하다', 80),
  ('곤-하다', 45),
  ('기-나름이다-n-나름이다', 35),
  ('기-마련이다', 50),
  ('기-일쑤이다', 55),
  ('기가-무섭게', 25),
  ('기는요', 5),
  ('기는커녕', 50),
  ('기로-하다', 40),
  ('기에', 60),
  ('기에는', 50),
  ('긴-나-봐요', 10),
  ('길래', 25),
  ('느니-차라리', 45),
  ('느라고', 45),
  ('는-감이-있다', 65),
  ('는-길에', 30),
  ('는-대로', 45),
  ('는-대신-에', 45),
  ('는-데', 55),
  ('는-데다가', 45),
  ('는-둥-마는-둥-하다', 25),
  ('는-바람에', 35),
  ('는-반면-에', 65),
  ('는-셈-치다-ㄴ-는다고-치다', 35),
  ('는-수가-있다', 30),
  ('는-탓에-탓이다', 55),
  ('는-편이다', 45),
  ('는-한', 60),
  ('는-은-ㄴ-모양이다', 40),
  ('는-ㄴ-셈이다', 55),
  ('는-ㄴ-다-싶다', 25),
  ('는-ㄴ다는-것이', 45),
  ('는-은-법이다', 70),
  ('는-은-줄-모르다-알다', 40),
  ('는-은-ㄴ-을-ㄹ-듯-이', 60),
  ('는가-은-ㄴ가-하면', 70),
  ('는걸요-으-ㄴ걸요', 10),
  ('는지-은지-ㄴ지', 45),
  ('다-가-보면', 40),
  ('다가는', 30),
  ('다니-이-라니', 35),
  ('다시피-하다', 60),
  ('더니', 45),
  ('더라고-요', 15),
  ('더라도', 45),
  ('던', 45),
  ('던데요', 15),
  ('도록', 50),
  ('되', 85),
  ('든지', 45),
  ('마저-도', 55),
  ('만-못하다', 55),
  ('만-하다', 40),
  ('만에', 40),
  ('아-어-대다', 25),
  ('아-어-보니-까-고-보니-까', 40),
  ('아-어-있다', 45),
  ('아-어-여-놓다-두다', 40),
  ('아-어-여-버리다', 35),
  ('아-어다가', 45),
  ('아-어도', 45),
  ('았-었-였더니', 45),
  ('았-었-였더라면', 55),
  ('았-었으면-하다', 40),
  ('에-따라-서', 55),
  ('에다가', 30),
  ('으라고-라고', 40),
  ('은-ㄴ-채-로', 60),
  ('을-ㄹ-뻔하다', 40),
  ('을-ㄹ-뿐-만-아니라', 60),
  ('을-ㄹ-뿐이다', 55),
  ('을-ㄹ-수가-있어야지-요', 15),
  ('을-ㄹ-줄만-알았지', 25),
  ('을-ㄹ까-봐', 40),
  ('을까-나-지-싶다', 25),
  ('을락-말락-하다', 30),
  ('음으로써', 85),
  ('이야말로', 55),
  ('이자', 60),
  ('자마자', 40),
  ('조차', 55),
  ('치고-는', 35),
  ('간접화법-축약형-abbreviated-indirect-speech', 5),
  ('같아선-같아서는', 15),
  ('사동-causative-voice', 50),
  ('피동-passive-voice', 60)
) AS v(id, colloquial)
WHERE g.id = v.id;

-- Also allow the register value through the same narrow client-writable
-- surface as the other editable metadata columns edited from the app's
-- grammar-point edit form. If your grammar_points table only currently
-- grants the `resources` column (see new_features_migration.sql), the
-- pattern/level/senses/difficulty/formality/politeness fields in that edit
-- form are already not actually writable by the client — this migration
-- doesn't change that; `colloquial` simply joins the same locked-down set.

-- ---------------------------------------------------------------------------
-- 2) Per-user grammar favorites — star a pattern as especially difficult or
-- important, then sort the Grammar list to bring your favorites to the top.
-- Fully private to each user, same shape as grammar_review_overrides.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS grammar_favorites (
  user_id uuid NOT NULL,
  pattern_id text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, pattern_id)
);
ALTER TABLE grammar_favorites ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "grammar_favorites_select" ON grammar_favorites;
CREATE POLICY "grammar_favorites_select" ON grammar_favorites FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "grammar_favorites_insert" ON grammar_favorites;
CREATE POLICY "grammar_favorites_insert" ON grammar_favorites FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "grammar_favorites_update" ON grammar_favorites;
CREATE POLICY "grammar_favorites_update" ON grammar_favorites FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "grammar_favorites_delete" ON grammar_favorites;
CREATE POLICY "grammar_favorites_delete" ON grammar_favorites FOR DELETE
  TO authenticated
  USING (auth.uid() = user_id);
