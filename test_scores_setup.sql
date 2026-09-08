-- =========================================================
-- PRELIMSIFY: SHARED SCOREBOARD
-- Run this whole script in Supabase SQL Editor.
-- =========================================================

create table if not exists public.test_scores (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  project_number integer,
  test_name text not null default 'Prelimsify Test',
  marks numeric not null default 0,
  max_marks numeric not null default 0,
  percentage numeric not null default 0,
  passed boolean not null default false,
  correct integer not null default 0,
  wrong integer not null default 0,
  unanswered integer not null default 0,
  completed_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

-- If a test_scores table was created earlier, make sure every column used
-- by the current website is present without deleting existing score rows.
alter table public.test_scores add column if not exists project_number integer;
alter table public.test_scores add column if not exists test_name text;
alter table public.test_scores add column if not exists marks numeric not null default 0;
alter table public.test_scores add column if not exists max_marks numeric not null default 0;
alter table public.test_scores add column if not exists percentage numeric not null default 0;
alter table public.test_scores add column if not exists passed boolean not null default false;
alter table public.test_scores add column if not exists correct integer not null default 0;
alter table public.test_scores add column if not exists wrong integer not null default 0;
alter table public.test_scores add column if not exists unanswered integer not null default 0;
alter table public.test_scores add column if not exists completed_at timestamptz not null default now();
alter table public.test_scores add column if not exists created_at timestamptz not null default now();

update public.test_scores
set test_name = coalesce(nullif(test_name, ''), 'Prelimsify Test')
where test_name is null or test_name = '';

alter table public.test_scores alter column test_name set not null;

create index if not exists test_scores_completed_at_idx
  on public.test_scores(completed_at desc);

create index if not exists test_scores_user_id_completed_at_idx
  on public.test_scores(user_id, completed_at desc);

alter table public.test_scores enable row level security;

drop policy if exists "test_scores_select_all_authenticated" on public.test_scores;
drop policy if exists "test_scores_insert_own" on public.test_scores;
drop policy if exists "test_scores_update_own" on public.test_scores;
drop policy if exists "test_scores_delete_own" on public.test_scores;

-- Everyone who is logged in can see the complete shared scoreboard.
create policy "test_scores_select_all_authenticated"
on public.test_scores
for select
to authenticated
using (true);

-- A user can only submit a score under their own account.
create policy "test_scores_insert_own"
on public.test_scores
for insert
to authenticated
with check (user_id = auth.uid());

create policy "test_scores_update_own"
on public.test_scores
for update
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

create policy "test_scores_delete_own"
on public.test_scores
for delete
to authenticated
using (user_id = auth.uid());

-- Shared scoreboard view. LEFT JOIN keeps a score visible even if its
-- profile row is missing; username is shown when available.
drop view if exists public.scoreboard_entries;

create view public.scoreboard_entries
with (security_invoker = false) as
select
  s.id,
  s.user_id,
  coalesce(
    nullif(p.username, ''),
    nullif(p.display_name, ''),
    'Unknown User'
  ) as username,
  s.test_name as title,
  s.project_number,
  s.marks,
  s.max_marks,
  s.percentage,
  s.passed,
  s.correct,
  s.wrong,
  s.unanswered,
  s.completed_at
from public.test_scores s
left join public.profiles p
  on p.id = s.user_id;

grant select on public.scoreboard_entries to authenticated;

grant select, insert, update, delete on public.test_scores to authenticated;

-- Verify the table/view are ready.
select
  id,
  user_id,
  test_name,
  project_number,
  marks,
  max_marks,
  percentage,
  passed,
  correct,
  wrong,
  unanswered,
  completed_at
from public.test_scores
order by completed_at desc;
