-- =====================================================
-- REPAIR LIVE USER PROFILES
-- =====================================================

create extension if not exists "pgcrypto";

-- =====================================================
-- ENSURE SELF-READ POLICY EXISTS
-- =====================================================
drop policy if exists "users_read_own_profile" on public.users;

create policy "users_read_own_profile"
on public.users
for select
to authenticated
using (auth.uid() = id);

-- =====================================================
-- BACKFILL ANY MISSING public.users ROWS
-- =====================================================
do $$
declare
  admin_role_id uuid;
  employee_role_id uuid;
  fallback_company_id uuid;
begin
  select id into admin_role_id
  from public.roles
  where role_name = 'Admin'
  limit 1;

  select id into employee_role_id
  from public.roles
  where role_name in ('Employee', 'Order Entry User', 'Viewer')
  order by case
    when role_name = 'Employee' then 0
    when role_name = 'Order Entry User' then 1
    else 2
  end
  limit 1;

  select company_id into fallback_company_id
  from public.users
  where company_id is not null
  limit 1;

  if fallback_company_id is null then
    fallback_company_id := gen_random_uuid();
  end if;

  insert into public.users (
    id,
    company_id,
    branch_id,
    role_id,
    name,
    email,
    username,
    is_active,
    created_at,
    updated_at,
    last_active
  )
  select
    au.id,
    fallback_company_id,
    null,
    case
      when lower(coalesce(au.email, '')) = 'c.markode@gmail.com' and admin_role_id is not null
        then admin_role_id
      else coalesce(employee_role_id, admin_role_id)
    end,
    coalesce(
      au.raw_user_meta_data->>'name',
      split_part(coalesce(au.email, ''), '@', 1),
      'User'
    ),
    au.email,
    null,
    true,
    coalesce(au.created_at, now()),
    now(),
    null
  from auth.users au
  left join public.users pu on pu.id = au.id
  where pu.id is null;

  if admin_role_id is not null then
    update public.users u
    set
      role_id = admin_role_id,
      company_id = coalesce(u.company_id, fallback_company_id),
      is_active = true,
      updated_at = now()
    where lower(coalesce(u.email, '')) = 'c.markode@gmail.com';
  end if;
end
$$;

-- =====================================================
-- ENSURE CURRENT-USER RPCS ARE PRESENT WITH GRANTS
-- =====================================================
drop function if exists public.ensure_current_user_profile() cascade;

create or replace function public.ensure_current_user_profile()
returns json
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  current_uid uuid;
  created_profile boolean := false;
begin
  current_uid := auth.uid();

  if current_uid is null then
    raise exception 'Authentication required';
  end if;

  if not exists (select 1 from public.users where id = current_uid) then
    perform 1;
    insert into public.users (
      id,
      company_id,
      branch_id,
      role_id,
      name,
      email,
      username,
      is_active,
      created_at,
      updated_at,
      last_active
    )
    select
      au.id,
      coalesce((select company_id from public.users where company_id is not null limit 1), gen_random_uuid()),
      null,
      (
        select r.id
        from public.roles r
        where r.role_name = case
          when lower(coalesce(au.email, '')) = 'c.markode@gmail.com' then 'Admin'
          else 'Order Entry User'
        end
        limit 1
      ),
      coalesce(au.raw_user_meta_data->>'name', split_part(coalesce(au.email, ''), '@', 1), 'User'),
      au.email,
      null,
      true,
      coalesce(au.created_at, now()),
      now(),
      null
    from auth.users au
    where au.id = current_uid
    on conflict (id) do nothing;

    created_profile := true;
  end if;

  return json_build_object('status', 'ok', 'created', created_profile);
end;
$$;

grant execute on function public.ensure_current_user_profile() to authenticated;

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

  if not exists (select 1 from public.users where id = current_uid) then
    perform public.ensure_current_user_profile();
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
