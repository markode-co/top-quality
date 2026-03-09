do $$
declare
  v_target_email text := 'c.markode@gmail.com';
  v_user_id uuid;
  v_user_name text;
  v_admin_role_id uuid;
  v_company_id uuid;
  v_branch_id uuid;
  v_permissions_code_column text;
  v_permissions_id_column text;
  v_role_permissions_column text;
  v_user_permissions_column text;
begin
  select
    au.id,
    coalesce(
      nullif(trim(coalesce(au.raw_user_meta_data ->> 'name', '')), ''),
      nullif(split_part(lower(coalesce(au.email, '')), '@', 1), ''),
      'Admin User'
    )
  into
    v_user_id,
    v_user_name
  from auth.users au
  where lower(coalesce(au.email, '')) = lower(v_target_email)
  order by au.created_at asc
  limit 1;

  if v_user_id is null then
    raise notice 'Auth user with email % was not found. Create the auth account first, then rerun migration.', v_target_email;
    return;
  end if;

  select r.id
  into v_admin_role_id
  from public.roles r
  where lower(coalesce(public.resolve_role_name(r.id), '')) = 'admin'
  order by r.id asc
  limit 1;

  if v_admin_role_id is null then
    raise exception 'Admin role was not found in public.roles.';
  end if;

  select public.default_company_id(), public.default_branch_id()
  into v_company_id, v_branch_id;

  if v_company_id is null or v_branch_id is null then
    raise exception 'Default company/branch is missing. Run multi-tenant setup migrations first.';
  end if;

  insert into public.users (
    id,
    company_id,
    branch_id,
    name,
    email,
    role_id,
    is_active,
    last_active
  )
  values (
    v_user_id,
    v_company_id,
    v_branch_id,
    v_user_name,
    lower(v_target_email),
    v_admin_role_id,
    true,
    now()
  )
  on conflict (id) do update
  set
    role_id = excluded.role_id,
    is_active = true,
    email = excluded.email,
    company_id = coalesce(public.users.company_id, excluded.company_id),
    branch_id = coalesce(public.users.branch_id, excluded.branch_id),
    updated_at = now(),
    last_active = now();

  select c.column_name
  into v_permissions_code_column
  from information_schema.columns c
  where c.table_schema = 'public'
    and c.table_name = 'permissions'
    and c.column_name in ('code', 'name')
  order by case when c.column_name = 'code' then 0 else 1 end
  limit 1;

  select c.column_name
  into v_permissions_id_column
  from information_schema.columns c
  where c.table_schema = 'public'
    and c.table_name = 'permissions'
    and c.column_name in ('id', 'permission_id')
  order by case when c.column_name = 'id' then 0 else 1 end
  limit 1;

  select c.column_name
  into v_role_permissions_column
  from information_schema.columns c
  where c.table_schema = 'public'
    and c.table_name = 'role_permissions'
    and c.column_name in ('permission_code', 'permission_id')
  order by case when c.column_name = 'permission_code' then 0 else 1 end
  limit 1;

  select c.column_name
  into v_user_permissions_column
  from information_schema.columns c
  where c.table_schema = 'public'
    and c.table_name = 'user_permissions'
    and c.column_name in ('permission_code', 'permission_id')
  order by case when c.column_name = 'permission_code' then 0 else 1 end
  limit 1;

  -- Ensure Admin role carries every permission in the system.
  if v_role_permissions_column = 'permission_code' and v_permissions_code_column is not null then
    execute format(
      'insert into public.role_permissions (role_id, permission_code)
       select $1, p.%I
       from public.permissions p
       on conflict do nothing',
      v_permissions_code_column
    )
    using v_admin_role_id;
  elsif v_role_permissions_column = 'permission_id' and v_permissions_id_column is not null then
    execute format(
      'insert into public.role_permissions (role_id, permission_id)
       select $1, p.%I
       from public.permissions p
       on conflict do nothing',
      v_permissions_id_column
    )
    using v_admin_role_id;
  end if;

  -- Ensure this user has every permission directly as well.
  if v_user_permissions_column = 'permission_code' and v_permissions_code_column is not null then
    execute format(
      'insert into public.user_permissions (user_id, permission_code)
       select $1, p.%I
       from public.permissions p
       on conflict do nothing',
      v_permissions_code_column
    )
    using v_user_id;
  elsif v_user_permissions_column = 'permission_id' and v_permissions_id_column is not null then
    execute format(
      'insert into public.user_permissions (user_id, permission_id)
       select $1, p.%I
       from public.permissions p
       on conflict do nothing',
      v_permissions_id_column
    )
    using v_user_id;
  end if;
end;
$$;
