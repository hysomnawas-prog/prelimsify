-- Prelimsify accounts, shared scoreboard, saved papers and admin permissions.
-- Run in Supabase SQL Editor. Safe to run repeatedly.
create extension if not exists pgcrypto;

-- Make the profile schema compatible with both fresh and older Prelimsify projects.
alter table public.profiles add column if not exists display_name text;
alter table public.profiles add column if not exists avatar_url text;
alter table public.profiles add column if not exists email text;

-- ------------------------------------------------------------
-- 1. Student/admin profile
-- ------------------------------------------------------------
alter table public.profiles add column if not exists username text;
alter table public.profiles add column if not exists role text not null default 'student';
alter table public.profiles add column if not exists can_use_app boolean not null default true;

create unique index if not exists profiles_username_lower_uidx
  on public.profiles (lower(username)) where username is not null;

-- Existing profile trigger
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, username, display_name, avatar_url, email)
  values (
    new.id,
    lower(new.raw_user_meta_data ->> 'username'),
    coalesce(new.raw_user_meta_data ->> 'display_name', new.raw_user_meta_data ->> 'username', new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name'),
    new.raw_user_meta_data ->> 'avatar_url',
    new.email
  )
  on conflict (id) do update set
    username = coalesce(excluded.username, profiles.username),
    display_name = coalesce(excluded.display_name, profiles.display_name),
    avatar_url = coalesce(excluded.avatar_url, profiles.avatar_url),
    email = coalesce(excluded.email, profiles.email);
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

-- Backfill profiles for Auth users that were created before this trigger existed.
-- This is safe to re-run; existing profile rows are left untouched.
insert into public.profiles (id, username, display_name, avatar_url, email)
select
  u.id,
  lower(u.raw_user_meta_data ->> 'username'),
  coalesce(u.raw_user_meta_data ->> 'display_name', u.raw_user_meta_data ->> 'username', u.raw_user_meta_data ->> 'full_name', u.raw_user_meta_data ->> 'name'),
  u.raw_user_meta_data ->> 'avatar_url',
  u.email
from auth.users u
where not exists (select 1 from public.profiles p where p.id=u.id)
  and (u.raw_user_meta_data ->> 'username') is not null;

-- ------------------------------------------------------------
-- 2. Saved question-set projects
-- ------------------------------------------------------------
create table if not exists public.quiz_projects (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  project_number integer not null,
  paper jsonb not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint quiz_projects_user_project_number_key unique (user_id, project_number)
);
create index if not exists quiz_projects_user_id_idx on public.quiz_projects(user_id);

-- ------------------------------------------------------------
-- 3. Shared completed-test scoreboard
-- ------------------------------------------------------------
create table if not exists public.test_history (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  title text not null,
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
create index if not exists test_history_completed_at_idx on public.test_history(completed_at desc);
create index if not exists test_history_user_id_completed_at_idx on public.test_history(user_id, completed_at desc);

-- ------------------------------------------------------------
-- 4. Active / unfinished test
-- ------------------------------------------------------------
create table if not exists public.active_tests (
  user_id uuid primary key default auth.uid() references auth.users(id) on delete cascade,
  title text not null default 'Unfinished Test',
  state jsonb not null,
  updated_at timestamptz not null default now()
);

create or replace function public.set_updated_at()
returns trigger language plpgsql security invoker set search_path = public as $$
begin new.updated_at = now(); return new; end; $$;

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at before update on public.profiles for each row execute function public.set_updated_at();
drop trigger if exists quiz_projects_set_updated_at on public.quiz_projects;
create trigger quiz_projects_set_updated_at before update on public.quiz_projects for each row execute function public.set_updated_at();
drop trigger if exists active_tests_set_updated_at on public.active_tests;
create trigger active_tests_set_updated_at before update on public.active_tests for each row execute function public.set_updated_at();

-- ------------------------------------------------------------
-- 5. Secure scoreboard view: exposes only scoreboard fields.
--    Normal users do not get unrestricted profile-table access.
-- ------------------------------------------------------------
drop view if exists public.scoreboard_entries;
create view public.scoreboard_entries
with (security_invoker = false) as
select h.id, p.username, h.title, h.marks, h.max_marks, h.percentage,
       h.passed, h.correct, h.wrong, h.unanswered, h.completed_at
from public.test_history h
join public.profiles p on p.id = h.user_id
where p.can_use_app = true;

grant select on public.scoreboard_entries to authenticated;

-- ------------------------------------------------------------
-- 5b. Reliable profile loader/repair for browser login
-- ------------------------------------------------------------
create or replace function public.ensure_my_profile()
returns table (
  id uuid,
  username text,
  display_name text,
  role text,
  can_use_app boolean
)
language plpgsql
security definer
set search_path = public
as $$
declare
  u record;
  base_username text;
  final_username text;
  n integer := 0;
begin
  if auth.uid() is null then
    return;
  end if;

  select * into u from auth.users where auth.users.id = auth.uid();

  base_username := lower(coalesce(
    u.raw_user_meta_data ->> 'username',
    split_part(coalesce(u.email,''),'@',1),
    'user_' || substr(u.id::text,1,8)
  ));
  base_username := regexp_replace(base_username, '[^a-z0-9_.-]', '', 'g');
  if length(base_username) < 3 then
    base_username := 'user_' || substr(u.id::text,1,8);
  end if;
  final_username := left(base_username,32);

  -- Create the row if this is an older Auth account with no profile.
  begin
    insert into public.profiles (id, username, display_name, avatar_url, email, role, can_use_app)
    values (
      u.id, final_username, final_username,
      u.raw_user_meta_data ->> 'avatar_url', u.email, 'student', true
    )
    on conflict (id) do nothing;
  exception when unique_violation then
    -- Username already belongs to another account: generate a unique suffix.
    loop
      n := n + 1;
      final_username := left(base_username, greatest(3, 32 - length(n::text) - 1)) || '_' || n::text;
      begin
        insert into public.profiles (id, username, display_name, avatar_url, email, role, can_use_app)
        values (u.id, final_username, final_username, u.raw_user_meta_data ->> 'avatar_url', u.email, 'student', true)
        on conflict (id) do nothing;
        exit;
      exception when unique_violation then
        if n > 1000 then raise; end if;
      end;
    end loop;
  end;

  return query
  select p.id, p.username, p.display_name, p.role, p.can_use_app
  from public.profiles p
  where p.id = auth.uid();
end;
$$;

grant execute on function public.ensure_my_profile() to authenticated;

-- ------------------------------------------------------------
-- 6. Row Level Security
-- ------------------------------------------------------------
create or replace function public.is_admin(uid uuid default auth.uid())
returns boolean language sql stable security definer set search_path = public
as $$ select exists (select 1 from public.profiles where id=uid and role='admin'); $$;

create or replace function public.can_use_app(uid uuid default auth.uid())
returns boolean language sql stable security definer set search_path = public
as $$ select exists (select 1 from public.profiles where id=uid and can_use_app=true); $$;

alter table public.profiles enable row level security;
alter table public.quiz_projects enable row level security;
alter table public.test_history enable row level security;
alter table public.active_tests enable row level security;

-- Profiles: users read/update themselves; admins can manage all profiles.
drop policy if exists "profiles_select_own" on public.profiles;
drop policy if exists "profiles_select_admin" on public.profiles;
create policy "profiles_select_own" on public.profiles for select to authenticated using (id = auth.uid());
create policy "profiles_select_admin" on public.profiles for select to authenticated using (public.is_admin());

drop policy if exists "profiles_insert_own" on public.profiles;
create policy "profiles_insert_own" on public.profiles for insert to authenticated with check (id = auth.uid());

drop policy if exists "profiles_update_own" on public.profiles;
drop policy if exists "profiles_update_admin" on public.profiles;
create policy "profiles_update_own" on public.profiles for update to authenticated
using (id = auth.uid())
with check (id = auth.uid() and role = 'student');
create policy "profiles_update_admin" on public.profiles for update to authenticated
using (public.is_admin()) with check (true);

-- App data: only users who have permission can use/read their own data.
drop policy if exists "quiz_projects_select_own" on public.quiz_projects;
drop policy if exists "quiz_projects_insert_own" on public.quiz_projects;
drop policy if exists "quiz_projects_update_own" on public.quiz_projects;
drop policy if exists "quiz_projects_delete_own" on public.quiz_projects;
create policy "quiz_projects_select_own" on public.quiz_projects for select to authenticated using (user_id = auth.uid() and public.can_use_app());
create policy "quiz_projects_insert_own" on public.quiz_projects for insert to authenticated with check (user_id = auth.uid() and public.can_use_app());
create policy "quiz_projects_update_own" on public.quiz_projects for update to authenticated using (user_id = auth.uid() and public.can_use_app()) with check (user_id = auth.uid() and public.can_use_app());
create policy "quiz_projects_delete_own" on public.quiz_projects for delete to authenticated using (user_id = auth.uid() and public.can_use_app());

-- Completed history: users can insert/read their own rows; shared scoreboard is via the view.
drop policy if exists "test_history_select_own" on public.test_history;
drop policy if exists "test_history_insert_own" on public.test_history;
drop policy if exists "test_history_update_own" on public.test_history;
drop policy if exists "test_history_delete_own" on public.test_history;
create policy "test_history_select_own" on public.test_history for select to authenticated using (user_id = auth.uid() and public.can_use_app());
create policy "test_history_insert_own" on public.test_history for insert to authenticated with check (user_id = auth.uid() and public.can_use_app());
create policy "test_history_update_own" on public.test_history for update to authenticated using (user_id = auth.uid() and public.can_use_app()) with check (user_id = auth.uid() and public.can_use_app());
create policy "test_history_delete_own" on public.test_history for delete to authenticated using (user_id = auth.uid() and public.can_use_app());

-- Active tests
drop policy if exists "active_tests_select_own" on public.active_tests;
drop policy if exists "active_tests_insert_own" on public.active_tests;
drop policy if exists "active_tests_update_own" on public.active_tests;
drop policy if exists "active_tests_delete_own" on public.active_tests;
create policy "active_tests_select_own" on public.active_tests for select to authenticated using (user_id = auth.uid() and public.can_use_app());
create policy "active_tests_insert_own" on public.active_tests for insert to authenticated with check (user_id = auth.uid() and public.can_use_app());
create policy "active_tests_update_own" on public.active_tests for update to authenticated using (user_id = auth.uid() and public.can_use_app()) with check (user_id = auth.uid() and public.can_use_app());
create policy "active_tests_delete_own" on public.active_tests for delete to authenticated using (user_id = auth.uid() and public.can_use_app());

grant execute on function public.is_admin(uuid) to authenticated;
grant execute on function public.can_use_app(uuid) to authenticated;
grant select, insert, update, delete on public.profiles to authenticated;
grant select, insert, update, delete on public.quiz_projects to authenticated;
grant select, insert, update, delete on public.test_history to authenticated;
grant select, insert, update, delete on public.active_tests to authenticated;

-- ------------------------------------------------------------
-- 7. Make the first admin manually (run after creating that account):
-- UPDATE public.profiles SET role='admin', can_use_app=true WHERE username='your_admin_username';
-- ------------------------------------------------------------
