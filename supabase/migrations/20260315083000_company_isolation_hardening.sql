-- Company isolation hardening and employee profile consistency
-- Date: 2026-03-15

begin;

create extension if not exists "pgcrypto";

-- -----------------------------------------------------
-- Company helpers used by RLS and profile RPCs
-- -----------------------------------------------------
create or replace function public.current_company_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select u.company_id
  from public.users u
  where u.id = auth.uid()
  limit 1
$$;

grant execute on function public.current_company_id() to authenticated;

create or replace function public.current_company_name()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select c.name
  from public.companies c
  where c.id = public.current_company_id()
  limit 1
$$;

grant execute on function public.current_company_name() to authenticated;

create or replace function public.__is_base_table(target_table text)
returns boolean
language sql
stable
set search_path = public
as $$
  select exists (
    select 1
    from pg_class c
    join pg_namespace n
      on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = target_table
      and c.relkind in ('r', 'p')
  )
$$;

grant execute on function public.__is_base_table(text) to authenticated;

-- -----------------------------------------------------
-- Backfill company_id where possible
-- -----------------------------------------------------
do $$
declare
  fallback_company_id uuid;
begin
  if to_regclass('public.companies') is null then
    return;
  end if;

  select id into fallback_company_id
  from public.companies
  limit 1;

  if fallback_company_id is null then
    insert into public.companies (id, name, is_active)
    values (gen_random_uuid(), 'Default Company', true)
    returning id into fallback_company_id;
  end if;

  if public.__is_base_table('users') and exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'users'
      and column_name = 'company_id'
  ) then
    update public.users
    set company_id = coalesce(company_id, fallback_company_id)
    where company_id is null;
  end if;

  if public.__is_base_table('orders') and exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'orders' and column_name = 'company_id'
  ) and exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'orders' and column_name = 'created_by'
  ) and public.__is_base_table('users') then
    update public.orders o
    set company_id = coalesce(o.company_id, u.company_id, fallback_company_id)
    from public.users u
    where o.created_by = u.id
      and o.company_id is null;

    update public.orders
    set company_id = fallback_company_id
    where company_id is null;
  end if;

  if public.__is_base_table('products') and exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'products' and column_name = 'company_id'
  ) then
    update public.products
    set company_id = coalesce(company_id, fallback_company_id)
    where company_id is null;
  end if;

  if public.__is_base_table('inventory') and exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'inventory' and column_name = 'company_id'
  ) and public.__is_base_table('products') and exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'inventory' and column_name = 'product_id'
  ) then
    update public.inventory i
    set company_id = coalesce(i.company_id, p.company_id, fallback_company_id)
    from public.products p
    where p.id = i.product_id
      and i.company_id is null;

    update public.inventory
    set company_id = fallback_company_id
    where company_id is null;
  end if;

  if public.__is_base_table('notifications') and exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'notifications' and column_name = 'company_id'
  ) and public.__is_base_table('users') and exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'notifications' and column_name = 'user_id'
  ) then
    update public.notifications n
    set company_id = coalesce(n.company_id, u.company_id, fallback_company_id)
    from public.users u
    where n.user_id = u.id
      and n.company_id is null;

    update public.notifications
    set company_id = fallback_company_id
    where company_id is null;
  end if;

  if public.__is_base_table('activity_logs') and exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'activity_logs' and column_name = 'company_id'
  ) and public.__is_base_table('users') and exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'activity_logs' and column_name = 'actor_id'
  ) then
    update public.activity_logs l
    set company_id = coalesce(l.company_id, u.company_id, fallback_company_id)
    from public.users u
    where l.actor_id = u.id
      and l.company_id is null;

    update public.activity_logs
    set company_id = fallback_company_id
    where company_id is null;
  end if;
end;
$$;

-- -----------------------------------------------------
-- Rebuild user and product views with security_invoker
-- -----------------------------------------------------
drop view if exists public.v_users_with_permissions cascade;

create view public.v_users_with_permissions
with (security_invoker = true)
as
select
  u.id,
  u.name,
  u.email,
  u.is_active,
  u.last_active,
  u.company_id,
  c.name as company_name,
  u.role_id,
  r.role_name,
  perms.permission_code
from public.users u
left join public.companies c
  on c.id = u.company_id
left join public.roles r
  on r.id = u.role_id
left join lateral (
  select rp.permission_code
  from public.role_permissions rp
  where rp.role_id = u.role_id
  union
  select up.permission_code
  from public.user_permissions up
  where up.user_id = u.id
) perms
  on true;

grant select on public.v_users_with_permissions to authenticated;

drop view if exists public.v_products cascade;

create view public.v_products
with (security_invoker = true)
as
select
  p.id,
  p.name,
  p.sku,
  p.category,
  p.purchase_price,
  p.sale_price,
  coalesce(i.stock, 0)::integer as stock,
  coalesce(i.min_stock, 0)::integer as min_stock,
  p.company_id,
  i.branch_id
from public.products p
left join public.inventory i
  on i.product_id = p.id;

grant select on public.v_products to authenticated;

drop view if exists public.v_activity_logs cascade;

create view public.v_activity_logs
with (security_invoker = true)
as
select
  l.id,
  l.actor_id,
  coalesce(u.name, l.metadata->>'actor_name', 'Unknown User') as actor_name,
  coalesce(u.email, l.metadata->>'actor_email') as actor_email,
  l.action,
  l.entity_type,
  l.entity_id,
  l.metadata,
  l.created_at,
  l.company_id
from public.activity_logs l
left join public.users u
  on u.id = l.actor_id;

grant select on public.v_activity_logs to authenticated;

-- -----------------------------------------------------
-- Profile RPC includes company fields
-- -----------------------------------------------------
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
  resolved_company_name text;
  resolved_permissions text[];
begin
  current_uid := auth.uid();

  if current_uid is null then
    return null;
  end if;

  if exists (
    select 1 from pg_proc
    where pronamespace = 'public'::regnamespace
      and proname = 'ensure_current_user_profile'
  ) then
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
  where id = user_row.role_id
  limit 1;

  select name
  into resolved_company_name
  from public.companies
  where id = user_row.company_id
  limit 1;

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
  ) p;

  return json_build_object(
    'id', user_row.id,
    'name', user_row.name,
    'email', user_row.email,
    'role_id', user_row.role_id,
    'role_name', coalesce(resolved_role_name, ''),
    'permissions', coalesce(resolved_permissions, '{}'::text[]),
    'company_id', user_row.company_id,
    'company_name', resolved_company_name,
    'created_at', user_row.created_at,
    'updated_at', user_row.updated_at,
    'last_active', user_row.last_active,
    'is_active', user_row.is_active
  );
end;
$$;

grant execute on function public.get_current_user_profile() to authenticated;

-- -----------------------------------------------------
-- RLS policy reset helper
-- -----------------------------------------------------
create or replace function public.__drop_all_policies(target_table text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  pol record;
begin
  for pol in
    select policyname
    from pg_policies
    where schemaname = 'public'
      and tablename = target_table
  loop
    execute format(
      'drop policy if exists %I on public.%I',
      pol.policyname,
      target_table
    );
  end loop;
end;
$$;

grant execute on function public.__drop_all_policies(text) to postgres, service_role;

-- -----------------------------------------------------
-- Baseline grants
-- -----------------------------------------------------
grant usage on schema public to authenticated;

do $$
begin
  if public.__is_base_table('roles') then
    execute 'grant select on public.roles to authenticated';
  end if;
  if public.__is_base_table('permissions') then
    execute 'grant select on public.permissions to authenticated';
  end if;
  if public.__is_base_table('role_permissions') then
    execute 'grant select on public.role_permissions to authenticated';
  end if;
  if public.__is_base_table('user_permissions') then
    execute 'grant select on public.user_permissions to authenticated';
  end if;
  if public.__is_base_table('companies') then
    execute 'grant select on public.companies to authenticated';
  end if;
  if public.__is_base_table('branches') then
    execute 'grant select on public.branches to authenticated';
  end if;
end;
$$;

-- -----------------------------------------------------
-- Users: visible only within caller company
-- -----------------------------------------------------
do $$
begin
  if not public.__is_base_table('users') then
    return;
  end if;

  execute 'alter table public.users enable row level security';
  perform public.__drop_all_policies('users');

  execute $sql$
    create policy users_company_select
    on public.users
    for select
    to authenticated
    using (company_id = public.current_company_id())
  $sql$;

  execute $sql$
    create policy users_self_update
    on public.users
    for update
    to authenticated
    using (id = auth.uid())
    with check (id = auth.uid() and company_id = public.current_company_id())
  $sql$;
end;
$$;

-- -----------------------------------------------------
-- User permissions: visible only for users in same company
-- -----------------------------------------------------
do $$
begin
  if not public.__is_base_table('user_permissions') then
    return;
  end if;

  execute 'alter table public.user_permissions enable row level security';
  perform public.__drop_all_policies('user_permissions');

  execute $sql$
    create policy user_permissions_company_select
    on public.user_permissions
    for select
    to authenticated
    using (
      exists (
        select 1
        from public.users u
        where u.id = user_permissions.user_id
          and u.company_id = public.current_company_id()
      )
    )
  $sql$;
end;
$$;

-- -----------------------------------------------------
-- Companies and branches: only own company scope
-- -----------------------------------------------------
do $$
begin
  if public.__is_base_table('companies') then
    execute 'alter table public.companies enable row level security';
    perform public.__drop_all_policies('companies');
    execute $sql$
      create policy companies_current_select
      on public.companies
      for select
      to authenticated
      using (id = public.current_company_id())
    $sql$;
  end if;

  if public.__is_base_table('branches') then
    execute 'alter table public.branches enable row level security';
    perform public.__drop_all_policies('branches');
    execute $sql$
      create policy branches_company_select
      on public.branches
      for select
      to authenticated
      using (company_id = public.current_company_id())
    $sql$;
  end if;
end;
$$;

-- -----------------------------------------------------
-- Products and inventory: strict company isolation
-- -----------------------------------------------------
do $$
begin
  if public.__is_base_table('products') then
    execute 'alter table public.products enable row level security';
    perform public.__drop_all_policies('products');
    execute $sql$
      create policy products_company_select
      on public.products
      for select
      to authenticated
      using (company_id = public.current_company_id())
    $sql$;
  end if;

  if public.__is_base_table('inventory') then
    execute 'alter table public.inventory enable row level security';
    perform public.__drop_all_policies('inventory');
    execute $sql$
      create policy inventory_company_select
      on public.inventory
      for select
      to authenticated
      using (company_id = public.current_company_id())
    $sql$;
  end if;
end;
$$;

-- -----------------------------------------------------
-- Orders, items, status history: strict company isolation
-- -----------------------------------------------------
do $$
begin
  if public.__is_base_table('orders') then
    execute 'alter table public.orders enable row level security';
    perform public.__drop_all_policies('orders');
    execute $sql$
      create policy orders_company_select
      on public.orders
      for select
      to authenticated
      using (company_id = public.current_company_id())
    $sql$;
  end if;

  if public.__is_base_table('order_items') then
    execute 'alter table public.order_items enable row level security';
    perform public.__drop_all_policies('order_items');
    execute $sql$
      create policy order_items_company_select
      on public.order_items
      for select
      to authenticated
      using (
        exists (
          select 1
          from public.orders o
          where o.id = order_items.order_id
            and o.company_id = public.current_company_id()
        )
      )
    $sql$;
  end if;

  if public.__is_base_table('order_status_history') then
    execute 'alter table public.order_status_history enable row level security';
    perform public.__drop_all_policies('order_status_history');
    execute $sql$
      create policy order_status_history_company_select
      on public.order_status_history
      for select
      to authenticated
      using (
        exists (
          select 1
          from public.orders o
          where o.id = order_status_history.order_id
            and o.company_id = public.current_company_id()
        )
      )
    $sql$;
  end if;
end;
$$;

-- -----------------------------------------------------
-- Notifications and activity logs: strict company/user scope
-- -----------------------------------------------------
do $$
begin
  if public.__is_base_table('notifications') then
    execute 'alter table public.notifications enable row level security';
    perform public.__drop_all_policies('notifications');

    execute $sql$
      create policy notifications_own_select
      on public.notifications
      for select
      to authenticated
      using (
        user_id = auth.uid()
        and company_id = public.current_company_id()
      )
    $sql$;

    execute $sql$
      create policy notifications_own_update
      on public.notifications
      for update
      to authenticated
      using (
        user_id = auth.uid()
        and company_id = public.current_company_id()
      )
      with check (
        user_id = auth.uid()
        and company_id = public.current_company_id()
      )
    $sql$;
  end if;

  if public.__is_base_table('activity_logs') then
    execute 'alter table public.activity_logs enable row level security';
    perform public.__drop_all_policies('activity_logs');
    execute $sql$
      create policy activity_logs_company_select
      on public.activity_logs
      for select
      to authenticated
      using (company_id = public.current_company_id())
    $sql$;
  end if;
end;
$$;

-- helper no longer needed
drop function if exists public.__drop_all_policies(text);
drop function if exists public.__is_base_table(text);

notify pgrst, 'reload schema';

commit;
