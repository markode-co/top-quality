-- Seed default role permissions to align backend RBAC with app expectations.
-- Idempotent: safe to re-run.

insert into public.permissions (code, description)
values
  ('dashboard_view', 'Read dashboard'),
  ('notifications_view', 'Read notifications'),
  ('users_view', 'Read users'),
  ('users_create', 'Create users'),
  ('users_edit', 'Edit users'),
  ('users_delete', 'Delete users'),
  ('users_assign_permissions', 'Assign permissions'),
  ('products_view', 'Read products'),
  ('products_create', 'Create products'),
  ('products_edit', 'Edit products'),
  ('products_delete', 'Delete products'),
  ('inventory_view', 'Read inventory'),
  ('inventory_edit', 'Modify inventory'),
  ('orders_view', 'Read orders'),
  ('orders_create', 'Create orders'),
  ('orders_edit', 'Edit orders'),
  ('orders_delete', 'Delete orders'),
  ('orders_approve', 'Approve orders'),
  ('orders_ship', 'Ship orders'),
  ('orders_override', 'Override order workflow'),
  ('reports_view', 'Read reports'),
  ('activity_logs_view', 'Read activity logs'),
  ('activity_logs_view_all', 'Read activity logs for all companies'),
  ('activity_logs_company_view', 'Read activity logs for own company')
on conflict do nothing;

do $$
declare
  v_role uuid;
begin
  -- Reviewer / Manager
  for v_role in
    select id from public.roles
    where lower(role_name) in ('order reviewer', 'manager')
  loop
    insert into public.role_permissions (role_id, permission_code)
    select v_role, p.code
    from public.permissions p
    where p.code in (
      'dashboard_view',
      'notifications_view',
      'users_view',
      'users_create',
      'users_edit',
      'users_delete',
      'users_assign_permissions',
      'products_view',
      'inventory_view',
      'orders_view',
      'orders_edit',
      'orders_approve',
      'reports_view',
      'activity_logs_view'
    )
    on conflict do nothing;
  end loop;

  -- Order Entry / Employee
  for v_role in
    select id from public.roles
    where lower(role_name) in ('order entry user', 'order entry', 'employee')
  loop
    insert into public.role_permissions (role_id, permission_code)
    select v_role, p.code
    from public.permissions p
    where p.code in (
      'dashboard_view',
      'notifications_view',
      'users_view',
      'products_view',
      'inventory_view',
      'orders_view',
      'orders_create',
      'orders_edit'
    )
    on conflict do nothing;
  end loop;

  -- Shipping
  for v_role in
    select id from public.roles
    where lower(role_name) in ('shipping user', 'shipping')
  loop
    insert into public.role_permissions (role_id, permission_code)
    select v_role, p.code
    from public.permissions p
    where p.code in (
      'dashboard_view',
      'notifications_view',
      'users_view',
      'products_view',
      'inventory_view',
      'orders_view',
      'orders_ship'
    )
    on conflict do nothing;
  end loop;

  -- Viewer (read-only)
  for v_role in
    select id from public.roles
    where lower(role_name) in ('viewer')
  loop
    insert into public.role_permissions (role_id, permission_code)
    select v_role, p.code
    from public.permissions p
    where p.code in (
      'dashboard_view',
      'notifications_view',
      'users_view',
      'products_view',
      'inventory_view',
      'orders_view',
      'reports_view'
    )
    on conflict do nothing;
  end loop;
end $$;

notify pgrst, 'reload schema';
