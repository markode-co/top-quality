-- Ensure admin user markode with full permissions and correct email

do $$
declare
  v_admin_role uuid;
  v_company uuid;
  v_user uuid;
begin
  select id into v_admin_role from public.roles where role_name = 'Admin' limit 1;
  if v_admin_role is null then
    insert into public.roles(role_name, description)
    values ('Admin', 'System Administrator')
    on conflict (role_name) do nothing
    returning id into v_admin_role;
  end if;

  select company_id into v_company from public.users where company_id is not null limit 1;
  if v_company is null then
    v_company := uuid_generate_v4();
  end if;

  select id into v_user from public.users where username = 'markode' limit 1;

  if v_user is null then
    insert into public.users(
      username, email, password, name, role_id, is_active, company_id
    )
    values (
      'markode',
      'markode@gmail.com',
      crypt('123456', gen_salt('bf')),
      'Mark ODE',
      v_admin_role,
      true,
      v_company
    )
    returning id into v_user;
  else
    update public.users
       set email      = 'markode@gmail.com',
           role_id    = v_admin_role,
           is_active  = true,
           company_id = coalesce(company_id, v_company),
           password   = coalesce(password, crypt('123456', gen_salt('bf')))
     where id = v_user;
  end if;

  -- Grant all permissions to markode (in case role policies are insufficient)
  insert into public.user_permissions(user_id, permission_code)
  select v_user, p.code
  from public.permissions p
  on conflict do nothing;
end$$;

-- Refresh PostgREST cache
notify pgrst, 'reload schema';
