-- Expenditure -- vacation expense tracker, built as a new Home sub-tab in
-- this same app rather than a standalone product. Reuses this app's
-- existing profiles/auth and existing linked-circle (link_group_members)
-- as the pool of people you can invite into a vacation -- no new circle
-- concept needed. Categories are a small fixed JS-side list (see
-- EXPENSE_CATEGORIES in index.html), not a table, matching how job/book
-- status are already handled as fixed enums in this app rather than
-- database rows.

create table vacations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  date_start date not null,
  date_end date not null,
  currency text not null default 'USD',
  created_by uuid not null references profiles(id),
  created_at timestamptz not null default now(),
  archived boolean not null default false,
  constraint vacations_date_range check (date_end >= date_start)
);
alter table vacations enable row level security;

create table vacation_members (
  vacation_id uuid not null references vacations(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','accepted','declined')),
  role text not null default 'member' check (role in ('owner','member')),
  invited_by uuid not null references profiles(id),
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  primary key (vacation_id, user_id)
);
create index vacation_members_user_idx on vacation_members(user_id);
alter table vacation_members enable row level security;

create or replace function is_vacation_member(vid uuid, uid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists(
    select 1 from vacation_members
    where vacation_id = vid and user_id = uid and status = 'accepted'
  );
$$;

create or replace function is_vacation_owner(vid uuid, uid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists(
    select 1 from vacation_members
    where vacation_id = vid and user_id = uid and status = 'accepted' and role = 'owner'
  );
$$;

create policy "vacations_select" on vacations for select
  to authenticated using (is_vacation_member(id, auth.uid()));
create policy "vacations_update" on vacations for update
  to authenticated using (is_vacation_owner(id, auth.uid())) with check (is_vacation_owner(id, auth.uid()));
create policy "vacations_delete" on vacations for delete
  to authenticated using (is_vacation_owner(id, auth.uid()));
-- no direct INSERT policy -- must go through create_vacation() RPC

create policy "vacation_members_select" on vacation_members for select
  to authenticated using (
    user_id = auth.uid() or is_vacation_member(vacation_id, auth.uid())
  );
-- no direct INSERT/UPDATE/DELETE -- RPCs only

create table expenses (
  id uuid primary key default gen_random_uuid(),
  vacation_id uuid not null references vacations(id) on delete cascade,
  date date not null,
  amount numeric(12,2) not null check (amount > 0),
  category text not null default 'other',
  description text,
  paid_by uuid not null references profiles(id),
  created_by uuid not null references profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index expenses_vacation_date_idx on expenses(vacation_id, date);
alter table expenses enable row level security;

create policy "expenses_select" on expenses for select
  to authenticated using (is_vacation_member(vacation_id, auth.uid()));
create policy "expenses_insert" on expenses for insert
  to authenticated with check (
    is_vacation_member(vacation_id, auth.uid()) and created_by = auth.uid()
  );
create policy "expenses_update" on expenses for update
  to authenticated using (is_vacation_member(vacation_id, auth.uid()))
  with check (is_vacation_member(vacation_id, auth.uid()));
create policy "expenses_delete" on expenses for delete
  to authenticated using (is_vacation_member(vacation_id, auth.uid()));

-- ---------------------------------------------------------------------------
-- RPCs -- same SECURITY DEFINER / RPC-only-writes shape as link_groups_migration.sql
-- ---------------------------------------------------------------------------
create or replace function create_vacation(
  p_name text, p_date_start date, p_date_end date, p_currency text
) returns uuid language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); vid uuid;
begin
  if me is null then raise exception 'Not authenticated'; end if;
  insert into vacations (name, date_start, date_end, currency, created_by)
    values (p_name, p_date_start, p_date_end, p_currency, me) returning id into vid;
  insert into vacation_members (vacation_id, user_id, status, role, invited_by, responded_at)
    values (vid, me, 'accepted', 'owner', me, now());
  return vid;
end; $$;
grant execute on function create_vacation(text,date,date,text) to authenticated;

create or replace function vacation_invite(p_vacation_id uuid, p_invitee_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  if not is_vacation_member(p_vacation_id, me) then
    raise exception 'Not a member of this vacation';
  end if;
  if p_invitee_id = me then raise exception 'Cannot invite yourself'; end if;
  insert into vacation_members (vacation_id, user_id, status, role, invited_by)
    values (p_vacation_id, p_invitee_id, 'pending', 'member', me)
    on conflict (vacation_id, user_id) do update
      set status = 'pending', invited_by = excluded.invited_by,
          created_at = now(), responded_at = null
      where vacation_members.status = 'declined';
end; $$;
grant execute on function vacation_invite(uuid,uuid) to authenticated;

create or replace function vacation_accept_invite(p_vacation_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  update vacation_members set status = 'accepted', responded_at = now()
    where vacation_id = p_vacation_id and user_id = auth.uid() and status = 'pending';
end; $$;
grant execute on function vacation_accept_invite(uuid) to authenticated;

create or replace function vacation_decline_invite(p_vacation_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  update vacation_members set status = 'declined', responded_at = now()
    where vacation_id = p_vacation_id and user_id = auth.uid() and status = 'pending';
end; $$;
grant execute on function vacation_decline_invite(uuid) to authenticated;

create or replace function vacation_remove_member(p_vacation_id uuid, p_target_user_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_vacation_owner(p_vacation_id, auth.uid()) then
    raise exception 'Only the owner can remove members';
  end if;
  if p_target_user_id = auth.uid() then
    raise exception 'Owner cannot remove themself -- delete the vacation instead';
  end if;
  delete from vacation_members where vacation_id = p_vacation_id and user_id = p_target_user_id;
end; $$;
grant execute on function vacation_remove_member(uuid,uuid) to authenticated;

create or replace function vacation_leave(p_vacation_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if is_vacation_owner(p_vacation_id, auth.uid()) then
    raise exception 'Owner cannot leave -- delete the vacation instead';
  end if;
  delete from vacation_members where vacation_id = p_vacation_id and user_id = auth.uid();
end; $$;
grant execute on function vacation_leave(uuid) to authenticated;
