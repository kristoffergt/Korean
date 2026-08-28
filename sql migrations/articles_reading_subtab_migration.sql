-- Articles: a second Reading sub-tab alongside Books, same shape (status,
-- notes, shared_circle_cat visibility, public leaderboard) but with fields
-- that fit an article rather than a book -- source/journal and a link to
-- the article itself instead of page counts, which don't mean much for
-- something usually read in one sitting.

create table articles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  title text not null,
  author text,
  source text,
  link text,
  status text not null default 'to_read',
  finished_at date,
  created_at timestamptz not null default now(),
  notes jsonb default '[]'::jsonb
);
alter table articles enable row level security;

create policy "articles_select" on articles for select
  to authenticated using (shared_circle_cat(auth.uid(), user_id, 'articles'));
create policy "articles_insert" on articles for insert
  to authenticated with check (auth.uid() = user_id);
create policy "articles_update" on articles for update
  to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "articles_delete" on articles for delete
  to authenticated using (auth.uid() = user_id);

-- Same public-aggregate shape as reading_leaderboard() (finished counts
-- only, never titles) -- deliberately left with its default PUBLIC/anon
-- grant to match that sibling function exactly rather than introducing an
-- asymmetry between the two leaderboards.
create or replace function articles_leaderboard()
returns table(user_id uuid, finished_count bigint)
language sql stable security definer set search_path = public as $$
  select a.user_id, count(*) filter (where a.status = 'finished') as finished_count
  from articles a
  join profiles p on p.id = a.user_id
  where coalesce(p.hide_from_leaderboards, false) = false
     or shared_circle(auth.uid(), p.id)
     or current_is_admin()
  group by a.user_id;
$$;
