-- Ensure admin user markode exists with full permissions (idempotent)
-- Uses auth.users as source of truth; no password stored in public.users.

create extension if not exists "uuid-ossp";
create extension if not exists "pgcrypto";

do $$
declare
  v_email   text := 'markode@gmail.com';
  v_name    text := 'markode';
  v_user_id uuid;
  v_role_id uuid;
  v_company uuid;
begin
  -- Locate auth user
  select id into v_user_id from auth.users where lower(email) = lower(v_email) limit 1;
  if v_user_id is null then
    raise exception 'Auth user with email % not found. Create it in auth.users first.', v_email;
  end if;

  -- Ensure Admin role
  select id into v_role_id from public.roles where lower(role_name) = 'admin' limit 1;
  if v_role_id is null then
    insert into public.roles(role_name, description)
    values ('Admin', 'System administrator')
    returning id into v_role_id;
  end if;

  -- Fallback company
  select company_id into v_company from public.users where company_id is not null limit 1;
  if v_company is null then
    v_company := uuid_generate_v4();
  end if;

  -- Upsert public.users profile
  insert into public.users(id, email, name, is_active, company_id, role_id)
  values (v_user_id, v_email, v_name, true, v_company, v_role_id)
  on conflict (id) do update set
    email      = excluded.email,
    name       = excluded.name,
    is_active  = true,
    company_id = coalesce(public.users.company_id, excluded.company_id),
    role_id    = excluded.role_id;

  -- Grant all permissions to Admin role
  insert into public.role_permissions (role_id, permission_code)
  select v_role_id, p.code from public.permissions p
  on conflict do nothing;

  -- Also grant directly to the user (defensive)
  insert into public.user_permissions (user_id, permission_code)
  select v_user_id, p.code from public.permissions p
  on conflict do nothing;
end;
$$;

-- Refresh PostgREST cache
notify pgrst, 'reload schema';
