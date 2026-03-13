-- Ensure markode@gmail.com has full permissions (role + direct grants)

do $$
declare
  v_email   text := 'markode@gmail.com';
  v_user_id uuid;
  v_role_id uuid;
begin
  select id into v_user_id from public.users where lower(email) = lower(v_email) limit 1;
  if v_user_id is null then
    -- if user row missing, stop silently
    return;
  end if;

  -- Ensure Admin role exists
  select id into v_role_id from public.roles where lower(role_name) = 'admin' limit 1;
  if v_role_id is null then
    insert into public.roles(role_name, description)
    values ('Admin', 'System administrator')
    returning id into v_role_id;
  end if;

  -- Promote user to Admin and keep active
  update public.users
  set role_id = v_role_id, is_active = true
  where id = v_user_id;

  -- Grant all permissions via role
  insert into public.role_permissions (role_id, permission_code)
  select v_role_id, p.code from public.permissions p
  on conflict do nothing;

  -- Also grant directly to the user (defensive)
  insert into public.user_permissions (user_id, permission_code)
  select v_user_id, p.code from public.permissions p
  on conflict do nothing;
end;
$$;
notify pgrst, 'reload schema';
