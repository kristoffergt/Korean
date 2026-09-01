-- Where a course actually meets (real-user request). Free text -- rooms at
-- Yonsei read like "New Millennium Hall B121", not something worth a lookup
-- table.
alter table courses add column classroom text;
