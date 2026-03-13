-- Enrich v_users_with_permissions with company info and stable permission rows.
-- This view is streamed by the app; keep (id, permission_code) unique and non-null.

drop view if exists public.v_users_with_permissions;

create view public.v_users_with_permissions as
with perms as (
  select up.user_id, up.permission_code
  from public.user_permissions up
  union
  select u.id as user_id, rp.permission_code
  from public.users u
  join public.role_permissions rp on rp.role_id = u.role_id
)
select
  u.id,
  u.email,
  u.name,
  u.is_active,
  u.last_active,
  u.company_id,
  c.name as company_name,
  r.role_name,
  coalesce(p.permission_code, 'none') as permission_code
from public.users u
left join public.companies c on c.id = u.company_id
left join public.roles r on r.id = u.role_id
left join perms p on p.user_id = u.id;

grant select on public.v_users_with_permissions to authenticated;
notify pgrst, 'reload schema';

