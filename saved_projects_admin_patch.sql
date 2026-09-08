-- Prelimsify: allow the admin to recover/view/manage all saved question sets.
-- Run this AFTER the main schema. It does not delete or alter existing questions.

create policy "quiz_projects_select_admin"
on public.quiz_projects
for select
to authenticated
using (public.is_admin());

drop policy if exists "quiz_projects_update_admin" on public.quiz_projects;
create policy "quiz_projects_update_admin"
on public.quiz_projects
for update
to authenticated
using (public.is_admin())
with check (public.is_admin());

drop policy if exists "quiz_projects_delete_admin" on public.quiz_projects;
create policy "quiz_projects_delete_admin"
on public.quiz_projects
for delete
to authenticated
using (public.is_admin());
