do $$
declare
  v_target_email text := 'c.markode@gmail.com';
  v_user_id uuid;
  v_user_name text;
  v_admin_role_id uuid;
  v_company_id uuid;
  v_branch_id uuid;
  v_perm_value_column text;
  v_perm_id_column text;
  v_role_perm_column text;
  v_user_perm_column text;
  v_has_name_column boolean;
  v_has_description_column boolean;
  v_code text;
  v_codes text[] := array[
    'orders_view',
    'orders_create',
    'orders_edit',
    'orders_delete',
    'orders_approve',
    'orders_ship',
    'orders_override',
    'inventory_view',
    'inventory_edit',
    'products_view',
    'products_create',
    'products_edit',
    'products_delete',
    'reports_view',
    'users_view',
    'users_create',
    'users_edit',
    'users_delete',
    'users_assign_permissions',
    'dashboard_view',
    'notifications_view',
    'activity_logs_view'
  ];
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
    raise notice 'Auth user with email % was not found.', v_target_email;
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
    raise exception 'Default company/branch is missing.';
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
  into v_perm_value_column
  from information_schema.columns c
  where c.table_schema = 'public'
    and c.table_name = 'permissions'
    and c.column_name in ('code', 'permission_code', 'name')
  order by case
    when c.column_name = 'code' then 0
    when c.column_name = 'permission_code' then 1
    else 2
  end
  limit 1;

  if v_perm_value_column is null then
    raise exception 'Could not resolve permissions value column.';
  end if;

  select c.column_name
  into v_perm_id_column
  from information_schema.columns c
  where c.table_schema = 'public'
    and c.table_name = 'permissions'
    and c.column_name in ('id', 'permission_id')
  order by case when c.column_name = 'id' then 0 else 1 end
  limit 1;

  select exists (
    select 1
    from information_schema.columns c
    where c.table_schema = 'public'
      and c.table_name = 'permissions'
      and c.column_name = 'name'
  )
  into v_has_name_column;

  select exists (
    select 1
    from information_schema.columns c
    where c.table_schema = 'public'
      and c.table_name = 'permissions'
      and c.column_name = 'description'
  )
  into v_has_description_column;

  foreach v_code in array v_codes
  loop
    if v_has_name_column and v_has_description_column then
      execute format(
        'insert into public.permissions (%1$I, name, description)
         select $1, $2, $3
         where not exists (
           select 1 from public.permissions p where p.%1$I = $1
         )',
        v_perm_value_column
      )
      using
        v_code,
        initcap(replace(v_code, '_', ' ')),
        'Auto-seeded app permission';
    elsif v_has_name_column then
      execute format(
        'insert into public.permissions (%1$I, name)
         select $1, $2
         where not exists (
           select 1 from public.permissions p where p.%1$I = $1
         )',
        v_perm_value_column
      )
      using
        v_code,
        initcap(replace(v_code, '_', ' '));
    else
      execute format(
        'insert into public.permissions (%1$I)
         select $1
         where not exists (
           select 1 from public.permissions p where p.%1$I = $1
         )',
        v_perm_value_column
      )
      using v_code;
    end if;
  end loop;

  select c.column_name
  into v_role_perm_column
  from information_schema.columns c
  where c.table_schema = 'public'
    and c.table_name = 'role_permissions'
    and c.column_name in ('permission_code', 'permission_id')
  order by case when c.column_name = 'permission_code' then 0 else 1 end
  limit 1;

  if v_role_perm_column = 'permission_code' then
    foreach v_code in array v_codes
    loop
      insert into public.role_permissions (role_id, permission_code)
      select v_admin_role_id, v_code
      where not exists (
        select 1
        from public.role_permissions rp
        where rp.role_id = v_admin_role_id
          and rp.permission_code = v_code
      );
    end loop;
  elsif v_role_perm_column = 'permission_id' and v_perm_id_column is not null then
    foreach v_code in array v_codes
    loop
      execute format(
        'insert into public.role_permissions (role_id, permission_id)
         select $1, p.%1$I
         from public.permissions p
         where p.%2$I = $2
           and not exists (
             select 1
             from public.role_permissions rp
             where rp.role_id = $1
               and rp.permission_id = p.%1$I
           )',
        v_perm_id_column,
        v_perm_value_column
      )
      using v_admin_role_id, v_code;
    end loop;
  end if;

  select c.column_name
  into v_user_perm_column
  from information_schema.columns c
  where c.table_schema = 'public'
    and c.table_name = 'user_permissions'
    and c.column_name in ('permission_code', 'permission_id')
  order by case when c.column_name = 'permission_code' then 0 else 1 end
  limit 1;

  if v_user_perm_column = 'permission_code' then
    foreach v_code in array v_codes
    loop
      insert into public.user_permissions (user_id, permission_code)
      select v_user_id, v_code
      where not exists (
        select 1
        from public.user_permissions up
        where up.user_id = v_user_id
          and up.permission_code = v_code
      );
    end loop;
  elsif v_user_perm_column = 'permission_id' and v_perm_id_column is not null then
    foreach v_code in array v_codes
    loop
      execute format(
        'insert into public.user_permissions (user_id, permission_id)
         select $1, p.%1$I
         from public.permissions p
         where p.%2$I = $2
           and not exists (
             select 1
             from public.user_permissions up
             where up.user_id = $1
               and up.permission_id = p.%1$I
           )',
        v_perm_id_column,
        v_perm_value_column
      )
      using v_user_id, v_code;
    end loop;
  end if;
end;
$$;
