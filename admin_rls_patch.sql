-- PRELIMSIFY ADMIN ACCESS PATCH
-- Run this once in Supabase SQL Editor.
-- It fixes admin.html access without exposing service_role credentials.

create or replace function public.admin_get_me()
returns table (
  id uuid,
  username text,
  role text,
  can_use_app boolean
)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  select p.id, p.username, p.role, p.can_use_app
  from public.profiles p
  where p.id = auth.uid()
    and p.role = 'admin';
end;
$$;

grant execute on function public.admin_get_me() to authenticated;

create or replace function public.admin_list_users()
returns table (
  id uuid,
  username text,
  role text,
  can_use_app boolean,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from public.profiles AS admin_profile
    where admin_profile.id = auth.uid()
      and admin_profile.role = 'admin'
  ) then
    raise exception 'Only an administrator can manage users';
  end if;

  return query
  select p.id, p.username, p.role, p.can_use_app, p.created_at
  from public.profiles p
  order by p.created_at asc;
end;
$$;

grant execute on function public.admin_list_users() to authenticated;

create or replace function public.admin_set_user_permission(
  target_user_id uuid,
  new_permission boolean
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  target_role text;
begin
  if not exists (
    select 1 from public.profiles AS admin_profile
    where admin_profile.id = auth.uid()
      and admin_profile.role = 'admin'
  ) then
    raise exception 'Only an administrator can change permissions';
  end if;

  select target_profile.role
  into target_role
  from public.profiles AS target_profile
  where target_profile.id = target_user_id;

  if target_role is null then
    raise exception 'User profile not found';
  end if;

  -- Do not allow an admin to accidentally disable administrator access.
  if target_role = 'admin' and new_permission = false then
    raise exception 'Administrator access cannot be revoked here';
  end if;

  update public.profiles
  set can_use_app = new_permission,
      updated_at = now()
  where public.profiles.id = target_user_id;

  return true;
end;
$$;

grant execute on function public.admin_set_user_permission(uuid, boolean) to authenticated;

-- Ensure your account remains administrator.
update public.profiles
set role = 'admin', can_use_app = true, updated_at = now()
where lower(username) = 'hysomnawas';

-- Verify.
select id, username, role, can_use_app
from public.profiles
where lower(username) = 'hysomnawas';
