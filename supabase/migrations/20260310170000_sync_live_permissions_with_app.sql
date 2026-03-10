-- =====================================================
-- SYNC LIVE PERMISSIONS WITH APP
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

insert into public.role_permissions (role_id, permission_code)
select r.id, p.code
from public.roles r
cross join public.permissions p
where r.role_name = 'Admin'
on conflict (role_id, permission_code) do nothing;

insert into public.role_permissions (role_id, permission_code)
select r.id, v.permission_code
from public.roles r
cross join (
  values
    ('dashboard_view'),
    ('notifications_view'),
    ('orders_view'),
    ('orders_create'),
    ('orders_edit'),
    ('inventory_view'),
    ('products_view')
) as v(permission_code)
where r.role_name = 'Order Entry User'
on conflict (role_id, permission_code) do nothing;

insert into public.role_permissions (role_id, permission_code)
select r.id, v.permission_code
from public.roles r
cross join (
  values
    ('dashboard_view'),
    ('notifications_view'),
    ('orders_view'),
    ('orders_approve'),
    ('reports_view')
) as v(permission_code)
where r.role_name = 'Order Reviewer'
on conflict (role_id, permission_code) do nothing;

insert into public.role_permissions (role_id, permission_code)
select r.id, v.permission_code
from public.roles r
cross join (
  values
    ('dashboard_view'),
    ('notifications_view'),
    ('orders_view'),
    ('orders_ship'),
    ('inventory_view'),
    ('products_view')
) as v(permission_code)
where r.role_name = 'Shipping User'
on conflict (role_id, permission_code) do nothing;

notify pgrst, 'reload schema';
