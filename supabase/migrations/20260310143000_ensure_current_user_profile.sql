-- =====================================================
-- ENSURE CURRENT USER PROFILE
-- =====================================================

create extension if not exists "pgcrypto";

drop function if exists public.ensure_current_user_profile() cascade;

create or replace function public.ensure_current_user_profile()
returns json
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  current_uid uuid;
  auth_email text;
  auth_name text;
  assigned_role_id uuid;
  bootstrap_company_id uuid;
begin
  current_uid := auth.uid();

  if current_uid is null then
    raise exception 'Authentication required';
  end if;

  if exists (
    select 1 from public.users where id = current_uid
  ) then
    return json_build_object('status', 'ok', 'created', false);
  end if;

  select
    u.email,
    coalesce(u.raw_user_meta_data->>'name', split_part(coalesce(u.email, ''), '@', 1), 'User')
  into auth_email, auth_name
  from auth.users u
  where u.id = current_uid;

  if lower(coalesce(auth_email, '')) = 'c.markode@gmail.com' then
    select id into assigned_role_id
    from public.roles
    where role_name = 'Admin'
    limit 1;
  end if;

  if assigned_role_id is null then
    select id into assigned_role_id
    from public.roles
    where role_name in ('Employee', 'Viewer', 'Order Entry User')
    order by case
      when role_name = 'Employee' then 0
      when role_name = 'Order Entry User' then 1
      else 2
    end
    limit 1;
  end if;

  if assigned_role_id is null then
    select id into assigned_role_id
    from public.roles
    order by created_at
    limit 1;
  end if;

  select company_id into bootstrap_company_id
  from public.users
  where company_id is not null
  limit 1;

  if bootstrap_company_id is null then
    bootstrap_company_id := gen_random_uuid();
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
  values (
    current_uid,
    bootstrap_company_id,
    null,
    assigned_role_id,
    auth_name,
    auth_email,
    null,
    true,
    now(),
    now(),
    null
  )
  on conflict (id) do nothing;

  return json_build_object('status', 'ok', 'created', true);
end;
$$;

grant execute on function public.ensure_current_user_profile() to authenticated;

notify pgrst, 'reload schema';
