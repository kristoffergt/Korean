-- ============================================================================
-- jobboard_items_seen had an INSERT policy but no UPDATE policy. The client
-- always writes via .upsert(..., {onConflict:'user_id,item_idx'}), which
-- Postgres implements as INSERT ... ON CONFLICT DO UPDATE -- and RLS
-- requires a valid UPDATE policy for that ON CONFLICT DO UPDATE clause to
-- be permitted at all, regardless of whether any given row actually ends
-- up conflicting. Without one, the whole upsert statement was silently
-- rejected (the client-side call isn't error-checked), so nothing was ever
-- actually recorded as seen -- items kept showing the NEW badge forever,
-- even after being viewed and even across fresh page loads.
--
-- Safe to re-run.
-- ============================================================================

drop policy if exists "jobboard_items_seen_update_own" on jobboard_items_seen;
create policy "jobboard_items_seen_update_own" on jobboard_items_seen
  for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
