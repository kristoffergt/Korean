-- Your own picture for any top-level tab (the school tab above all, once it is
-- not Yonsei). One row per account, own-only: nobody else ever reads it.
-- icons = { "<tab key>": { "src": <64px PNG data URL>, "mask": <one-colour
-- PNG data URL>, "mono": true|false } }. The pictures are shrunk in the
-- browser before they are sent, so the row stays small; the size check is a
-- ceiling against a client that does not.
create table if not exists public.user_tab_icons (
  user_id uuid primary key default auth.uid() references auth.users(id) on delete cascade,
  icons jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  constraint user_tab_icons_size check (pg_column_size(icons) < 400000)
);

alter table public.user_tab_icons enable row level security;
drop policy if exists user_tab_icons_select on public.user_tab_icons;
drop policy if exists user_tab_icons_insert on public.user_tab_icons;
drop policy if exists user_tab_icons_update on public.user_tab_icons;
drop policy if exists user_tab_icons_delete on public.user_tab_icons;
create policy user_tab_icons_select on public.user_tab_icons for select to authenticated
  using (user_id = auth.uid());
create policy user_tab_icons_insert on public.user_tab_icons for insert to authenticated
  with check (user_id = auth.uid());
create policy user_tab_icons_update on public.user_tab_icons for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy user_tab_icons_delete on public.user_tab_icons for delete to authenticated
  using (user_id = auth.uid());

grant select, insert, update, delete on public.user_tab_icons to authenticated;
