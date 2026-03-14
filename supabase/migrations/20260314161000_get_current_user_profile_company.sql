-- Enrich get_current_user_profile with company info for UI use.

create or replace function public.get_current_user_profile()
returns json
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  current_uid uuid := auth.uid();
  user_row public.users%rowtype;
  resolved_role_name text;
  resolved_permissions text[];
  company_name text;
begin
  if current_uid is null then
    return null;
  end if;

  if not exists (select 1 from public.users where id = current_uid) then
    perform public.ensure_current_user_profile();
  end if;

  select * into user_row from public.users where id = current_uid;

  select role_name into resolved_role_name from public.roles where id = user_row.role_id;

  select coalesce(array_agg(distinct permission_code), '{}'::text[])
  into resolved_permissions
  from (
    select rp.permission_code from public.role_permissions rp where rp.role_id = user_row.role_id
    union
    select up.permission_code from public.user_permissions up where up.user_id = user_row.id
  ) p;

  select name into company_name from public.companies where id = user_row.company_id;

  return json_build_object(
    'id', user_row.id,
    'name', user_row.name,
    'email', user_row.email,
    'company_id', user_row.company_id,
    'company_name', company_name,
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
