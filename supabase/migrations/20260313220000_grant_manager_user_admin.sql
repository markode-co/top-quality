-- Grant employee management permissions to the manager/reviewer role
-- This fixes 403 errors when non-admin managers call admin-manage-employee.

do $$
declare
  v_role_ids uuid[];
begin
  -- Collect role ids for manager-style roles
  select array_agg(id) into v_role_ids
  from public.roles
  where lower(role_name) in ('manager', 'order reviewer');

  if v_role_ids is not null then
    insert into public.role_permissions (role_id, permission_code)
    select unnest(v_role_ids), perm
    from (values
      ('users_view'),
      ('users_create'),
      ('users_edit'),
      ('users_delete'),
      ('users_assign_permissions')
    ) as p(perm)
    on conflict do nothing;
  end if;
end $$;

-- Ensure permissions exist
insert into public.permissions (code, description)
values
  ('users_view', 'Read users'),
  ('users_create', 'Create users'),
  ('users_edit', 'Edit users'),
  ('users_delete', 'Delete users'),
  ('users_assign_permissions', 'Assign permissions')
on conflict do nothing;
