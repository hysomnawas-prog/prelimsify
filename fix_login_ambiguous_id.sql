-- Prelimsify: fixes "Login succeeded, but the account profile could not be
-- loaded: column reference \"id\" is ambiguous".
--
-- Cause: ensure_my_profile() is declared as
--   RETURNS TABLE (id uuid, username text, display_name text, role text, can_use_app boolean)
-- Inside a PL/pgSQL function, every RETURNS TABLE column also becomes an
-- OUT variable with that same name, in scope for the whole function body.
-- So the bare word `id` used anywhere inside the function's SQL could mean
-- either that OUT variable or a real table column (profiles.id / auth.users.id),
-- and Postgres refuses to guess which one you meant.
--
-- Fix: add the `#variable_conflict use_column` pragma, which tells Postgres
-- "whenever this happens, always mean the table column" — which is what
-- this function wants everywhere it currently runs into the ambiguity.
-- This changes nothing about what the function does, only resolves the
-- naming clash. Safe to re-run.

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
#variable_conflict use_column
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
