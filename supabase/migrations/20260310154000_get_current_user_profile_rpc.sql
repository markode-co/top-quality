-- =====================================================
-- GET CURRENT USER PROFILE RPC
-- =====================================================

drop function if exists public.get_current_user_profile() cascade;

create or replace function public.get_current_user_profile()
returns json
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  current_uid uuid;
  user_row public.users%rowtype;
  resolved_role_name text;
  resolved_permissions text[];
begin
  current_uid := auth.uid();

  if current_uid is null then
    return null;
  end if;

  select *
  into user_row
  from public.users
  where id = current_uid;

  if not found then
    return null;
  end if;

  select role_name
  into resolved_role_name
  from public.roles
  where id = user_row.role_id;

  select coalesce(array_agg(distinct permission_code), '{}'::text[])
  into resolved_permissions
  from (
    select rp.permission_code
    from public.role_permissions rp
    where rp.role_id = user_row.role_id
    union
    select up.permission_code
    from public.user_permissions up
    where up.user_id = user_row.id
  ) permissions;

  return json_build_object(
    'id', user_row.id,
    'name', user_row.name,
    'email', user_row.email,
    'role_id', user_row.role_id,
    'role_name', coalesce(resolved_role_name, ''),
    'permissions', coalesce(resolved_permissions, '{}'::text[]),
    'created_at', user_row.created_at,
    'updated_at', user_row.updated_at,
    'last_active', user_row.last_active,
    'is_active', user_row.is_active
  );
end;
$$;

grant execute on function public.get_current_user_profile() to authenticated;

notify pgrst, 'reload schema';
