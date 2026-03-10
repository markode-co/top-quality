-- =====================================================
-- LIVE PERMISSION COMPATIBILITY PATCH
-- =====================================================

create extension if not exists "pgcrypto";

-- =====================================================
-- CANONICAL PERMISSIONS
-- =====================================================
insert into public.permissions (code, description)
values
  ('dashboard_view', 'Read dashboard'),
  ('notifications_view', 'Read notifications'),
  ('users_view', 'Read users'),
  ('users_create', 'Create users'),
  ('users_edit', 'Edit users'),
  ('users_delete', 'Delete users'),
  ('users_assign_permissions', 'Assign permissions'),
  ('inventory_view', 'Read inventory'),
  ('inventory_edit', 'Modify inventory'),
  ('products_view', 'Read products'),
  ('products_create', 'Create products'),
  ('products_edit', 'Edit products'),
  ('products_delete', 'Delete products'),
  ('orders_view', 'Read orders'),
  ('orders_create', 'Create orders'),
  ('orders_edit', 'Modify orders'),
  ('orders_delete', 'Delete orders'),
  ('orders_approve', 'Approve orders'),
  ('orders_ship', 'Ship orders'),
  ('orders_override', 'Override order workflow'),
  ('reports_view', 'Read reports'),
  ('activity_logs_view', 'Read activity logs')
on conflict (code) do nothing;

-- =====================================================
-- PERMISSION MIGRATION: ROLE PERMISSIONS
-- =====================================================
insert into public.role_permissions (role_id, permission_code)
select rp.role_id, mapped.permission_code
from public.role_permissions rp
join lateral (
  values
    ('orders_read', 'orders_view'),
    ('orders_write', 'orders_view'),
    ('orders_write', 'orders_create'),
    ('orders_write', 'orders_edit'),
    ('inventory_read', 'inventory_view'),
    ('inventory_read', 'products_view'),
    ('inventory_write', 'inventory_view'),
    ('inventory_write', 'inventory_edit'),
    ('inventory_write', 'products_view'),
    ('inventory_write', 'products_edit'),
    ('manage_users', 'users_view'),
    ('manage_users', 'users_create'),
    ('manage_users', 'users_edit'),
    ('manage_users', 'users_delete'),
    ('manage_users', 'users_assign_permissions'),
    ('manage_inventory', 'inventory_view'),
    ('manage_inventory', 'inventory_edit'),
    ('manage_inventory', 'products_view'),
    ('manage_inventory', 'products_create'),
    ('manage_inventory', 'products_edit'),
    ('manage_inventory', 'products_delete'),
    ('read', 'dashboard_view'),
    ('read', 'notifications_view'),
    ('read', 'orders_view'),
    ('read', 'inventory_view'),
    ('read', 'products_view'),
    ('read', 'reports_view'),
    ('read', 'users_view'),
    ('write', 'orders_create'),
    ('write', 'orders_edit'),
    ('write', 'inventory_edit'),
    ('write', 'products_create'),
    ('write', 'products_edit'),
    ('delete', 'orders_delete'),
    ('delete', 'products_delete'),
    ('delete', 'users_delete')
) as mapped(source_code, permission_code)
  on rp.permission_code = mapped.source_code
on conflict (role_id, permission_code) do nothing;

-- =====================================================
-- PERMISSION MIGRATION: USER PERMISSIONS
-- =====================================================
insert into public.user_permissions (user_id, permission_code)
select up.user_id, mapped.permission_code
from public.user_permissions up
join lateral (
  values
    ('orders_read', 'orders_view'),
    ('orders_write', 'orders_view'),
    ('orders_write', 'orders_create'),
    ('orders_write', 'orders_edit'),
    ('inventory_read', 'inventory_view'),
    ('inventory_read', 'products_view'),
    ('inventory_write', 'inventory_view'),
    ('inventory_write', 'inventory_edit'),
    ('inventory_write', 'products_view'),
    ('inventory_write', 'products_edit'),
    ('manage_users', 'users_view'),
    ('manage_users', 'users_create'),
    ('manage_users', 'users_edit'),
    ('manage_users', 'users_delete'),
    ('manage_users', 'users_assign_permissions'),
    ('manage_inventory', 'inventory_view'),
    ('manage_inventory', 'inventory_edit'),
    ('manage_inventory', 'products_view'),
    ('manage_inventory', 'products_create'),
    ('manage_inventory', 'products_edit'),
    ('manage_inventory', 'products_delete'),
    ('read', 'dashboard_view'),
    ('read', 'notifications_view'),
    ('read', 'orders_view'),
    ('read', 'inventory_view'),
    ('read', 'products_view'),
    ('read', 'reports_view'),
    ('read', 'users_view'),
    ('write', 'orders_create'),
    ('write', 'orders_edit'),
    ('write', 'inventory_edit'),
    ('write', 'products_create'),
    ('write', 'products_edit'),
    ('delete', 'orders_delete'),
    ('delete', 'products_delete'),
    ('delete', 'users_delete')
) as mapped(source_code, permission_code)
  on up.permission_code = mapped.source_code
on conflict (user_id, permission_code) do nothing;

-- =====================================================
-- ADMIN ROLE HARDENING
-- =====================================================
insert into public.role_permissions (role_id, permission_code)
select r.id, p.code
from public.roles r
cross join public.permissions p
where lower(r.role_name) in ('admin', 'system administrator', 'administrator')
on conflict (role_id, permission_code) do nothing;

-- =====================================================
-- SELF-READ POLICY FOR AUTHENTICATED USER
-- =====================================================
do $$
begin
  if not exists (
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
-- ADMIN BOOTSTRAP FOR CURRENT ACCOUNT
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
  where lower(role_name) in ('admin', 'system administrator', 'administrator')
  order by case when role_name = 'Admin' then 0 else 1 end
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
    email,
    name,
    is_active,
    company_id,
    role_id
  )
  values (
    uid,
    'c.markode@gmail.com',
    'Admin User',
    true,
    bootstrap_company_id,
    rid
  )
  on conflict (id) do update
  set
    email = excluded.email,
    name = coalesce(public.users.name, excluded.name),
    is_active = true,
    company_id = coalesce(public.users.company_id, excluded.company_id),
    role_id = coalesce(excluded.role_id, public.users.role_id);
end;
$$;

notify pgrst, 'reload schema';
