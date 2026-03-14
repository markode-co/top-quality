-- Add missing permissions for activity logs scope.

insert into public.permissions (code, description)
values
  ('activity_logs_view_all', 'Read activity logs for all companies'),
  ('activity_logs_company_view', 'Read activity logs for own company')
on conflict do nothing;

-- Grant to Admin role by default
insert into public.role_permissions (role_id, permission_code)
select r.id, p.code
from public.roles r
join public.permissions p on p.code in ('activity_logs_view_all')
where lower(r.role_name) = 'admin'
on conflict do nothing;

notify pgrst, 'reload schema';
