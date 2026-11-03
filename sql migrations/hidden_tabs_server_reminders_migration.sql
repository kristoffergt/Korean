-- ============================================================================
-- The server stops notifying about what a hidden tab owns.
--
-- profiles.hidden_tabs was read by no SQL function, so to-do reminders, board
-- notices and event reminders went on arriving for a tab the person had
-- hidden. tab_shown_for() asks the page's own question (tabsShown() and
-- workspaceHidesTab() in index.html): a key is shown unless it or its top tab
-- is in hidden_tabs, and the Yonsei-only tabs show only for a Yonsei
-- workspace. Then:
--   * send_todo_reminders: nothing while yonsei.todos is not shown.
--   * notify_yonsei_board_new_items: nobody whose yonsei.boards is not shown.
--   * send_due_reminders: what eventShownForTabs() takes off the calendar, a
--     course's own events while yonsei.courses is not shown and the TOPIK
--     dates while study is not.
-- A reminder that comes due while its tab is hidden is still written to its
-- log, so showing the tab again does not send what it was hiding.
--
-- The three senders are patched in place (each anchor must match exactly,
-- or the migration stops) rather than restated, so nothing else in them can
-- drift. Safe to re-run: a function already patched is left alone.
-- ============================================================================

create or replace function public.tab_shown_for(p_user uuid, p_key text)
returns boolean
language sql
stable
set search_path = public
as $$
  select coalesce((
    select not (coalesce(p.hidden_tabs, '{}'::text[]) && array[p_key, split_part(p_key, '.', 1)])
       and not (p_key in ('yonsei.boards', 'jobs.jobboard') and p.workspace_kind is distinct from 'yonsei')
    from profiles p where p.id = p_user
  ), true);
$$;
-- Only the senders above use it, and they run as the owner.
revoke all on function public.tab_shown_for(uuid, text) from public, anon, authenticated;

do $migrate$
declare
  d text;
  n text;
  shown constant text := '(rec.course_id is null or tab_shown_for(rec.user_id, ''yonsei.courses'')) and (rec.topik_key is null or tab_shown_for(rec.user_id, ''study'')) and ';
begin
  -- To-do reminders: logged as before, then skipped while the tab is hidden.
  d := pg_get_functiondef('public.send_todo_reminders'::regproc);
  if position('tab_shown_for' in d) = 0 then
    n := replace(d,
      E'    if not found then\n      continue;\n    end if;\n',
      E'    if not found then\n      continue;\n    end if;\n    if not tab_shown_for(rec.user_id, ''yonsei.todos'') then\n      continue;\n    end if;\n');
    if n = d then raise exception 'send_todo_reminders: anchor not found'; end if;
    execute n;
  end if;

  -- Board notices: only to people whose Boards tab is showing.
  d := pg_get_functiondef('public.notify_yonsei_board_new_items'::regproc);
  if position('tab_shown_for' in d) = 0 then
    n := replace(d,
      E'    WHERE p.notify_yonsei_board = true\n',
      E'    WHERE p.notify_yonsei_board = true\n      AND tab_shown_for(p.id, ''yonsei.boards'')\n');
    if n = d then raise exception 'notify_yonsei_board_new_items: anchor not found'; end if;
    execute n;
  end if;

  -- Event reminders: read the two columns that tie an event to a tab, and
  -- send neither the email nor the in-app row for an event that tab hides.
  -- reminder_log is still written below them.
  d := pg_get_functiondef('public.send_due_reminders'::regproc);
  if position('tab_shown_for' in d) = 0 then
    n := replace(d, E'      ev.recur_end_date,\n', E'      ev.recur_end_date,\n      ev.course_id,\n      ev.topik_key,\n');
    if n = d then raise exception 'send_due_reminders: column anchor not found'; end if;
    d := n;
    n := replace(d, E'if wants_email_notification(rec.user_id, ''reminder'') then', 'if ' || shown || E'wants_email_notification(rec.user_id, ''reminder'') then');
    if n = d then raise exception 'send_due_reminders: email anchor not found'; end if;
    d := n;
    n := replace(d, E'if wants_in_app_notification(rec.user_id, ''reminder'') then', 'if ' || shown || E'wants_in_app_notification(rec.user_id, ''reminder'') then');
    if n = d then raise exception 'send_due_reminders: in-app anchor not found'; end if;
    execute n;
  end if;
end;
$migrate$;
