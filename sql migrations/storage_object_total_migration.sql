-- Applied live 26 Sep as migration `storage_object_total`.
--
-- purge-orphan-files needs the total number of stored files to apply its
-- brake (refuse when "orphaned" comes back as most of storage), and
-- PostgREST does not expose the storage schema, so the count is asked for
-- through a function. Service role only: nothing else has a reason to know.

create or replace function public.storage_object_total()
returns integer
language sql
security definer
set search_path = ''
as $$
  select count(*)::integer from storage.objects;
$$;

revoke all on function public.storage_object_total() from public, anon, authenticated;
grant execute on function public.storage_object_total() to service_role;
