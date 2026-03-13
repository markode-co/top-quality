-- Recreate v_users_with_permissions to include direct user permissions,
-- fallback to role permissions, and ensure permission_code is never null
-- (Realtime primary keys cannot contain null).

create or replace view public.v_users_with_permissions as
select
  u.id,
  u.email,
  u.name,
  r.role_name,
  coalesce(up.permission_code, rp.permission_code, 'none') as permission_code
from public.users u
left join public.roles r on r.id = u.role_id
left join public.user_permissions up on up.user_id = u.id
left join public.role_permissions rp on rp.role_id = r.id;

grant select on public.v_users_with_permissions to authenticated;
