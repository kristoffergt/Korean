-- Roxy could not be added to a vacation despite being in Kristoffer's
-- circle, because his circle group (link_group_members) only ever
-- contained himself -- the circle-based invite list in
-- renderVacationMembersModal was genuinely empty for him, not broken.
-- Rather than forcing a full circle-connect-and-accept round trip before a
-- one-off vacation invite, this adds a direct search-and-invite fallback
-- alongside the existing circle-based list.

create or replace function vacation_search_invitable_users(p_vacation_id uuid, p_query text)
returns table(id uuid, display_name text)
language sql stable security definer set search_path = public as $$
  select p.id, p.display_name from profiles p
  where p.id <> auth.uid()
    and p.display_name ilike '%' || p_query || '%'
    and is_vacation_member(p_vacation_id, auth.uid())
    and not exists (
      select 1 from vacation_members vm
      where vm.vacation_id = p_vacation_id and vm.user_id = p.id
        and vm.status in ('pending','accepted')
    )
  order by p.display_name limit 20;
$$;
revoke execute on function vacation_search_invitable_users(uuid,text) from public;
revoke execute on function vacation_search_invitable_users(uuid,text) from anon;
grant execute on function vacation_search_invitable_users(uuid,text) to authenticated;
