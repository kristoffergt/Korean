-- Item cards in messages (real-user request: "one-click send as a message",
-- and a "quick view ... that you can give directly to someone else with an
-- account"). A card is a SNAPSHOT of the item when it was sent:
-- {kind, title, sub, fields:[{label,value}], body, from_id}. The reader sees
-- it without any right to the source row, so no other table's RLS changes.
-- The insert policy needs nothing new: it constrains who and where, not this
-- column, and there is still no UPDATE policy, so a card cannot be rewritten.
-- Idempotent; safe to run again.
alter table circle_messages add column if not exists card jsonb;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'circle_messages_card_shape') then
    alter table circle_messages add constraint circle_messages_card_shape
      check (card is null or (jsonb_typeof(card) = 'object' and pg_column_size(card) <= 16000));
  end if;
end $$;
