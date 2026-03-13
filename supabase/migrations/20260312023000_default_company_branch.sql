-- Ensure every user has company_id and branch_id with sensible defaults
-- Also update ensure_current_user_profile to assign both.

create extension if not exists "pgcrypto";
do $$
declare
  v_company_id uuid;
  v_branch_id uuid;
begin
  -- Ensure a default company exists
  select id into v_company_id from public.companies limit 1;
  if v_company_id is null then
    insert into public.companies(id, name, is_active)
    values (gen_random_uuid(), 'Default Company', true)
    returning id into v_company_id;
  end if;

  -- Ensure a default branch for that company
  select id into v_branch_id from public.branches where company_id = v_company_id limit 1;
  if v_branch_id is null then
    insert into public.branches(id, company_id, name, is_active)
    values (gen_random_uuid(), v_company_id, 'Main Branch', true)
    returning id into v_branch_id;
  end if;

  -- Backfill users
  update public.users
  set
    company_id = coalesce(company_id, v_company_id),
    branch_id  = coalesce(branch_id, v_branch_id)
  where company_id is null or branch_id is null;
end;
$$;
-- Replace ensure_current_user_profile to set default company/branch
drop function if exists public.ensure_current_user_profile() cascade;
create or replace function public.ensure_current_user_profile()
returns json
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  current_uid uuid := auth.uid();
  created_profile boolean := false;
  company_id uuid;
  branch_id uuid;
  role_id uuid;
begin
  if current_uid is null then
    raise exception 'Authentication required';
  end if;

  -- If exists already, return
  if exists (select 1 from public.users where id = current_uid) then
    return json_build_object('status','ok','created',false);
  end if;

  -- Default company / branch
  select id into company_id from public.companies limit 1;
  if company_id is null then
    insert into public.companies(id, name, is_active)
    values (gen_random_uuid(), 'Default Company', true)
    returning id into company_id;
  end if;

  select id into branch_id from public.branches where company_id = company_id limit 1;
  if branch_id is null then
    insert into public.branches(id, company_id, name, is_active)
    values (gen_random_uuid(), company_id, 'Main Branch', true)
    returning id into branch_id;
  end if;

  -- Default role
  select id into role_id from public.roles where role_name = 'Order Entry User' limit 1;
  if role_id is null then
    select id into role_id from public.roles order by created_at limit 1;
  end if;

  insert into public.users(
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
    company_id,
    branch_id,
    role_id,
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

  return json_build_object('status','ok','created',created_profile);
end;
$$;
grant execute on function public.ensure_current_user_profile() to authenticated;
notify pgrst, 'reload schema';
