-- ============================================================================
-- Chat attachments that no message points at any more join the daily purge.
--
-- A group chat is deleted in SQL when its last member leaves
-- (leave_chat_group), and its messages go with it (on delete cascade), but
-- storage cannot be emptied from SQL, so the pictures and files sent in it
-- stayed in circle-attachments for good. orphaned_storage_objects() is what
-- the purge-orphan-files job (daily, and after an account deletion) asks
-- which files to remove, so it now also answers with every attachment that
-- no circle_messages row references. The day's grace covers an upload whose
-- message row is still on its way: the file is stored first, the row second.
--
-- Safe to re-run. create or replace keeps the function's existing grants.
-- ============================================================================

create or replace function public.orphaned_storage_objects()
returns table(bucket_id text, name text)
language sql
stable security definer
set search_path to 'public', 'storage'
as $function$
  select o.bucket_id, o.name from storage.objects o
  where split_part(o.name, '/', 1) ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    and not exists (select 1 from auth.users u where u.id::text = split_part(o.name, '/', 1))
  union
  select o.bucket_id, o.name from storage.objects o
  where o.bucket_id = 'circle-attachments'
    and o.created_at < now() - interval '1 day'
    and not exists (select 1 from public.circle_messages m where m.attachment_path = o.name);
$function$;
