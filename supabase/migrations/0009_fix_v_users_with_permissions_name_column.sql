do $$
declare
  v_relkind "char";
  v_company_expr text := 'null::uuid';
  v_branch_expr text := 'null::uuid';
  v_name_expr text := '''Unknown''::text';
  v_email_expr text := 'null::text';
  v_username_expr text := 'null::text';
  v_role_expr text := 'null::uuid';
  v_active_expr text := 'true::boolean';
  v_created_expr text := 'now()::timestamptz';
  v_updated_expr text := 'now()::timestamptz';
  v_last_active_expr text := 'null::timestamptz';
begin
  select c.relkind
  into v_relkind
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname = 'v_users_with_permissions';

  if v_relkind = 'v' then
    execute 'drop view public.v_users_with_permissions cascade';
  elsif v_relkind = 'm' then
    execute 'drop materialized view public.v_users_with_permissions cascade';
  elsif v_relkind in ('r', 'p') then
    execute 'drop table public.v_users_with_permissions cascade';
  elsif v_relkind = 'f' then
    execute 'drop foreign table public.v_users_with_permissions cascade';
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'users'
      and column_name = 'company_id'
  ) then
    v_company_expr := 'u.company_id';
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'users'
      and column_name = 'branch_id'
  ) then
    v_branch_expr := 'u.branch_id';
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'users'
      and column_name = 'name'
  ) then
    v_name_expr := 'u.name';
  elsif exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'users'
      and column_name = 'full_name'
  ) then
    v_name_expr := 'u.full_name';
  elsif exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'users'
      and column_name = 'display_name'
  ) then
    v_name_expr := 'u.display_name';
  elsif exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'users'
      and column_name = 'username'
  ) then
    v_name_expr := 'u.username';
  elsif exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'users'
      and column_name = 'email'
  ) then
    v_name_expr := 'u.email';
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'users'
      and column_name = 'email'
  ) then
    v_email_expr := 'u.email';
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'users'
      and column_name = 'username'
  ) then
    v_username_expr := 'u.username';
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'users'
      and column_name = 'role_id'
  ) then
    v_role_expr := 'u.role_id';
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'users'
      and column_name = 'is_active'
  ) then
    v_active_expr := 'u.is_active';
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'users'
      and column_name = 'created_at'
  ) then
    v_created_expr := 'u.created_at';
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'users'
      and column_name = 'updated_at'
  ) then
    v_updated_expr := 'u.updated_at';
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'users'
      and column_name = 'last_active'
  ) then
    v_last_active_expr := 'u.last_active';
  end if;

  execute format(
    $sql$
    create view public.v_users_with_permissions
    with (security_invoker = true)
    as
    select
      u.id as id,
      %1$s as company_id,
      %2$s as branch_id,
      %3$s as name,
      %4$s as email,
      %5$s as username,
      %6$s as role_id,
      public.resolve_role_name(%6$s) as role_name,
      %7$s as is_active,
      %8$s as created_at,
      %9$s as updated_at,
      %10$s as last_active,
      public.user_effective_permissions(u.id, %6$s) as permissions
    from public.users u
    $sql$,
    v_company_expr,
    v_branch_expr,
    v_name_expr,
    v_email_expr,
    v_username_expr,
    v_role_expr,
    v_active_expr,
    v_created_expr,
    v_updated_expr,
    v_last_active_expr
  );
end;
$$;

notify pgrst, 'reload schema';
