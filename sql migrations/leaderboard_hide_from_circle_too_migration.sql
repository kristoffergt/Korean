-- hide_from_leaderboards already hides you from everyone except yourself,
-- the admin, and (if you're a core member) your one core partner. This adds
-- a stricter sub-option: hide_from_circle_too removes that last exception
-- too, so a core member can hide from absolutely everyone, including their
-- own core partner, with no exceptions at all besides admin/self.
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS hide_from_circle_too boolean NOT NULL DEFAULT false;
