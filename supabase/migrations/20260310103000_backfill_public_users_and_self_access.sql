-- =====================================================
-- BACKFILL PUBLIC USERS AND SELF ACCESS
-- =====================================================

create extension if not exists "pgcrypto";

-- =====================================================
-- ALLOW AUTHENTICATED USERS TO READ THEIR OWN PROFILE
-- =====================================================
do $$
begin
  if exists (
    select 1
    from pg_class
    where relnamespace = 'public'::regnamespace
      and relname = 'users'
      and relkind = 'r'
  ) and not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'users'
      and policyname = 'users_read_own_profile'
  ) then
    execute '
      create policy "users_read_own_profile"
      on public.users
      for select
      to authenticated
      using (auth.uid() = id)
    ';
  end if;
end;
$$;

-- =====================================================
-- ENSURE ADMIN ROLE EXISTS
-- =====================================================
insert into public.roles (role_name, description)
values ('Admin', 'System Administrator')
on conflict (role_name) do nothing;

-- =====================================================
-- BACKFILL MISSING public.users ROWS FROM auth.users
-- =====================================================
do $$
declare
  default_role_id uuid;
  bootstrap_company_id uuid;
begin
  select id into default_role_id
  from public.roles
  where role_name = 'Admin'
  limit 1;

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
  select
    au.id,
    bootstrap_company_id,
    null,
    default_role_id,
    coalesce(au.raw_user_meta_data->>'name', split_part(coalesce(au.email, ''), '@', 1), 'User'),
    au.email,
    null,
    true,
    coalesce(au.created_at, now()),
    now(),
    null
  from auth.users au
  left join public.users pu on pu.id = au.id
  where pu.id is null;
end;
$$;

-- =====================================================
-- ENSURE ADMIN ACCOUNT EXISTS IN public.users
-- =====================================================
do $$
declare
  uid uuid;
  rid uuid;
  bootstrap_company_id uuid;
begin
  select id into uid
  from auth.users
  where email = 'c.markode@gmail.com'
  limit 1;

  if uid is null then
    return;
  end if;

  select id into rid
  from public.roles
  where role_name = 'Admin'
  limit 1;

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
    uid,
    bootstrap_company_id,
    null,
    rid,
    'Admin User',
    'c.markode@gmail.com',
    null,
    true,
    now(),
    now(),
    null
  )
  on conflict (id) do update
  set
    company_id = coalesce(public.users.company_id, excluded.company_id),
    role_id = rid,
    name = coalesce(public.users.name, excluded.name),
    email = excluded.email,
    is_active = true,
    updated_at = now();
end;
$$;

notify pgrst, 'reload schema';
