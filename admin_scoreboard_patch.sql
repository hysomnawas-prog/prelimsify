-- =========================================================
-- PRELIMSIFY: let an administrator change PASS/FAIL on the
-- shared scoreboard for ANY user's completed test.
--
-- Run this whole script once in the Supabase SQL Editor,
-- AFTER supabase_schema.sql has been applied.
-- =========================================================

-- 1. The browser needs the row id to target an update, and the
--    scoreboard view must keep exposing it.
drop view if exists public.scoreboard_entries;
create view public.scoreboard_entries
with (security_invoker = false) as
select h.id, h.user_id, p.username, h.title, h.marks, h.max_marks, h.percentage,
       h.passed, h.correct, h.wrong, h.unanswered, h.completed_at
from public.test_history h
join public.profiles p on p.id = h.user_id
where p.can_use_app = true;

grant select on public.scoreboard_entries to authenticated;

-- 2. Existing policy only allows a user to update their own rows.
--    Add a separate policy so an admin can update any row.
drop policy if exists "test_history_update_admin" on public.test_history;
create policy "test_history_update_admin"
on public.test_history
for update
to authenticated
using (public.is_admin())
with check (public.is_admin());

-- 3. Admins should also be able to see every row directly on the table
--    (the scoreboard view already shows them, this keeps things consistent).
drop policy if exists "test_history_select_admin" on public.test_history;
create policy "test_history_select_admin"
on public.test_history
for select
to authenticated
using (public.is_admin());

grant select, insert, update, delete on public.test_history to authenticated;

-- 4. Quick check: should list your own role as 'admin'.
select id, username, role from public.profiles where id = auth.uid();
