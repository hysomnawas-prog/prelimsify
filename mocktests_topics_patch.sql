-- Prelimsify: "Mocktests" shared library + topic headings.
-- Run this AFTER supabase_schema.sql and saved_projects_admin_patch.sql.
-- Safe to re-run.
--
-- What this does:
--   1. Adds a `topic` column to quiz_projects so each saved question set can
--      be filed under one of the fixed subject headings (or left
--      Uncategorized).
--   2. Adds a `topic_labels` table so an admin can rename those headings;
--      every user reads the current label from here.
--   3. Widens quiz_projects' SELECT policy so every signed-in user with
--      app access can see every saved project (Mocktests are a shared
--      library now, not per-user). INSERT/UPDATE/DELETE stay restricted to
--      the project's owner or an admin — this patch does not change who can
--      edit or delete, only who can read.

-- 1. Topic column -----------------------------------------------------------
alter table public.quiz_projects
  add column if not exists topic text;

-- 2. Topic labels -------------------------------------------------------------
create table if not exists public.topic_labels (
  key text primary key,
  label text not null,
  updated_at timestamptz not null default now()
);

alter table public.topic_labels enable row level security;

drop policy if exists "topic_labels_select_all" on public.topic_labels;
create policy "topic_labels_select_all"
on public.topic_labels
for select
to authenticated
using (public.can_use_app());

drop policy if exists "topic_labels_write_admin" on public.topic_labels;
create policy "topic_labels_write_admin"
on public.topic_labels
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

grant select, insert, update, delete on public.topic_labels to authenticated;

-- 3. Shared read access for quiz_projects --------------------------------------
-- Every signed-in user with app access may now SELECT every saved project
-- (this is additive: it does not remove the existing "own rows" or "admin"
-- select policies, and does not touch insert/update/delete policies).
drop policy if exists "quiz_projects_select_shared" on public.quiz_projects;
create policy "quiz_projects_select_shared"
on public.quiz_projects
for select
to authenticated
using (public.can_use_app());
