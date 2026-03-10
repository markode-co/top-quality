-- =====================================================
-- EXTENSIONS
-- =====================================================
create extension if not exists "uuid-ossp";
create extension if not exists "pgcrypto";

-- =====================================================
-- CLEAN OLD OBJECTS
-- =====================================================
drop view if exists public.v_users_with_permissions cascade;

drop table if exists public.activity_logs cascade;
drop table if exists public.user_permissions cascade;
drop table if exists public.role_permissions cascade;
drop table if exists public.permissions cascade;
drop table if exists public.roles cascade;
drop table if exists public.user_logins cascade;
drop table if exists public.users cascade;

drop function if exists public.record_user_login(uuid,timestamptz) cascade;
drop function if exists public.record_user_login(uuid) cascade;
drop function if exists public.write_activity_log(uuid,text,text,uuid,jsonb) cascade;
drop function if exists public.get_user_role(uuid) cascade;
drop function if exists public.is_admin() cascade;
drop function if exists public.handle_new_user() cascade;

-- =====================================================
-- USERS
-- =====================================================
create table public.users (
    id uuid primary key references auth.users(id) on delete cascade,
    company_id uuid,
    branch_id uuid,
    role_id uuid,
    name text,
    email text,
    username text,
    is_active boolean default true,
    created_at timestamptz default now(),
    updated_at timestamptz default now(),
    last_active timestamptz
);

create index idx_users_email on public.users(email);
create index idx_users_role on public.users(role_id);

-- =====================================================
-- ROLES
-- =====================================================
create table public.roles (
    id uuid primary key default gen_random_uuid(),
    role_name text unique not null,
    description text,
    created_at timestamptz default now()
);

alter table public.users
add constraint fk_user_role
foreign key (role_id)
references public.roles(id)
on delete set null;

-- =====================================================
-- PERMISSIONS
-- =====================================================
create table public.permissions (
    id uuid primary key default gen_random_uuid(),
    code text unique not null,
    description text
);

-- =====================================================
-- ROLE PERMISSIONS
-- =====================================================
create table public.role_permissions (
    id uuid primary key default gen_random_uuid(),
    role_id uuid references public.roles(id) on delete cascade,
    permission_code text,
    unique(role_id,permission_code)
);

create index idx_role_permissions_role on public.role_permissions(role_id);

-- =====================================================
-- USER PERMISSIONS
-- =====================================================
create table public.user_permissions (
    id uuid primary key default gen_random_uuid(),
    user_id uuid references public.users(id) on delete cascade,
    permission_code text,
    unique(user_id,permission_code)
);

-- =====================================================
-- LOGIN TRACKING
-- =====================================================
create table public.user_logins (
    user_id uuid primary key references public.users(id) on delete cascade,
    last_login_at timestamptz,
    login_count integer default 0
);

-- =====================================================
-- ACTIVITY LOGS
-- =====================================================
create table public.activity_logs (
    id uuid primary key default gen_random_uuid(),
    actor_id uuid,
    action text,
    entity_type text,
    entity_id uuid,
    metadata jsonb,
    created_at timestamptz default now()
);

create index idx_logs_actor on public.activity_logs(actor_id);
create index idx_logs_created on public.activity_logs(created_at);

-- =====================================================
-- DEFAULT ROLES
-- =====================================================
insert into public.roles(role_name,description) values
('Admin','System Administrator'),
('Order Reviewer','Reviews and approves orders'),
('Shipping User','Handles shipping and fulfillment'),
('Order Entry User','Creates and manages draft orders'),
('Viewer','Read Only')
on conflict do nothing;

-- =====================================================
-- DEFAULT PERMISSIONS
-- =====================================================
insert into public.permissions(code,description) values
('dashboard_view','Read dashboard'),
('notifications_view','Read notifications'),
('users_view','Read users'),
('users_create','Create users'),
('users_edit','Edit users'),
('users_delete','Delete users'),
('users_assign_permissions','Assign permissions'),
('inventory_view','Read inventory'),
('inventory_edit','Modify inventory'),
('products_view','Read products'),
('products_create','Create products'),
('products_edit','Edit products'),
('products_delete','Delete products'),
('orders_view','Read orders'),
('orders_create','Create orders'),
('orders_edit','Modify orders'),
('orders_delete','Delete orders'),
('orders_approve','Approve orders'),
('orders_ship','Ship orders'),
('orders_override','Override order workflow'),
('reports_view','Read reports'),
('activity_logs_view','Read activity logs')
on conflict do nothing;

-- =====================================================
-- ADMIN FULL PERMISSIONS
-- =====================================================
insert into public.role_permissions(role_id,permission_code)
select r.id,p.code
from public.roles r
cross join public.permissions p
where r.role_name='Admin'
on conflict do nothing;

insert into public.role_permissions(role_id,permission_code)
select r.id, permission_code
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
) as perms(permission_code)
where r.role_name='Order Entry User'
on conflict do nothing;

insert into public.role_permissions(role_id,permission_code)
select r.id, permission_code
from public.roles r
cross join (
  values
    ('dashboard_view'),
    ('notifications_view'),
    ('orders_view'),
    ('orders_approve'),
    ('reports_view')
) as perms(permission_code)
where r.role_name='Order Reviewer'
on conflict do nothing;

insert into public.role_permissions(role_id,permission_code)
select r.id, permission_code
from public.roles r
cross join (
  values
    ('dashboard_view'),
    ('notifications_view'),
    ('orders_view'),
    ('orders_ship'),
    ('inventory_view'),
    ('products_view')
) as perms(permission_code)
where r.role_name='Shipping User'
on conflict do nothing;

-- =====================================================
-- VIEW USERS WITH PERMISSIONS
-- =====================================================
create or replace view public.v_users_with_permissions as
select
u.id,
u.email,
u.name,
r.role_name,
p.code as permission_code
from public.users u
left join public.roles r on r.id=u.role_id
left join public.role_permissions rp on rp.role_id=r.id
left join public.permissions p on p.code=rp.permission_code;

grant select on public.v_users_with_permissions to authenticated;

-- =====================================================
-- WRITE ACTIVITY LOG
-- =====================================================
create or replace function public.write_activity_log(
p_actor_id uuid,
p_action text,
p_entity_type text,
p_entity_id uuid,
p_metadata jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin

insert into activity_logs(
actor_id,
action,
entity_type,
entity_id,
metadata
)
values(
p_actor_id,
p_action,
p_entity_type,
p_entity_id,
p_metadata
);

end;
$$;

grant execute on function public.write_activity_log(uuid,text,text,uuid,jsonb) to authenticated;

-- =====================================================
-- GET USER ROLE
-- =====================================================
create or replace function public.get_user_role(uid uuid)
returns text
language plpgsql
stable
set search_path = public
as $$
declare r text;
begin

select role_name
into r
from roles
where id=(select role_id from users where id=uid);

return r;

end;
$$;

-- =====================================================
-- ADMIN CHECK
-- =====================================================
create or replace function public.is_admin()
returns boolean
language plpgsql
security definer
stable
set search_path = public
as $$
begin

return public.get_user_role(auth.uid())='Admin';

end;
$$;

grant execute on function public.is_admin() to authenticated;

-- =====================================================
-- RECORD USER LOGIN
-- =====================================================
create or replace function public.record_user_login(
p_user_id uuid
)
returns json
language plpgsql
security definer
set search_path = public
as $$
begin

update users
set
last_active = now(),
updated_at = now()
where id=p_user_id;

insert into user_logins(user_id,last_login_at,login_count)
values(p_user_id,now(),1)
on conflict(user_id)
do update
set
last_login_at=excluded.last_login_at,
login_count=user_logins.login_count+1;

return json_build_object('status','ok');

end;
$$;

grant execute on function public.record_user_login(uuid) to anon;
grant execute on function public.record_user_login(uuid) to authenticated;

-- =====================================================
-- HANDLE NEW USER FROM AUTH
-- =====================================================
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin

insert into users(
id,
email,
name
)
values(
new.id,
new.email,
coalesce(new.raw_user_meta_data->>'name','User')
)
on conflict (id) do nothing;

return new;

end;
$$;

drop trigger if exists on_auth_user_created on auth.users;

create trigger on_auth_user_created
after insert on auth.users
for each row
execute procedure public.handle_new_user();

-- =====================================================
-- ENABLE RLS
-- =====================================================
alter table public.users enable row level security;
alter table public.activity_logs enable row level security;

-- =====================================================
-- RLS POLICIES
-- =====================================================
create policy "admin_manage_users"
on public.users
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

create policy "users_read_own_profile"
on public.users
for select
to authenticated
using (auth.uid() = id);

create policy "admin_logs_access"
on public.activity_logs
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

-- =====================================================
-- REFRESH API
-- =====================================================
notify pgrst,'reload schema';

-- =====================================================
-- CREATE ADMIN USER
-- =====================================================
do $$
declare
uid uuid;
rid uuid;
begin

select id into uid
from auth.users
where email='c.markode@gmail.com'
limit 1;

if uid is not null then

select id into rid
from public.roles
where role_name='Admin';

insert into public.users(
  id,
  email,
  name,
  is_active,
  company_id,
  role_id
)
values(
  uid,
  'c.markode@gmail.com',
  'Admin',
  true,
  gen_random_uuid(),
  rid
)
on conflict (id) do update
set
  email = excluded.email,
  name = coalesce(public.users.name, excluded.name),
  is_active = true,
  company_id = coalesce(public.users.company_id, excluded.company_id),
  role_id = excluded.role_id;

end if;

end $$;
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
-- =====================================================
-- BACKFILL PUBLIC USERS AND SELF ACCESS
-- =====================================================

create extension if not exists "pgcrypto";

-- =====================================================
-- ALLOW AUTHENTICATED USERS TO READ THEIR OWN PROFILE
-- =====================================================
do $$
begin
  if exists (
    select 1
    from pg_class
    where relnamespace = 'public'::regnamespace
      and relname = 'users'
      and relkind = 'r'
  ) and not exists (
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
-- ENSURE ADMIN ROLE EXISTS
-- =====================================================
insert into public.roles (role_name, description)
values ('Admin', 'System Administrator')
on conflict (role_name) do nothing;

-- =====================================================
-- BACKFILL MISSING public.users ROWS FROM auth.users
-- =====================================================
do $$
declare
  default_role_id uuid;
  bootstrap_company_id uuid;
begin
  select id into default_role_id
  from public.roles
  where role_name = 'Admin'
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
    company_id,
    branch_id,
    role_id,
    name,
    email,
    username,
    is_active,
    created_at,
    updated_at,
    last_active
  )
  select
    au.id,
    bootstrap_company_id,
    null,
    default_role_id,
    coalesce(au.raw_user_meta_data->>'name', split_part(coalesce(au.email, ''), '@', 1), 'User'),
    au.email,
    null,
    true,
    coalesce(au.created_at, now()),
    now(),
    null
  from auth.users au
  left join public.users pu on pu.id = au.id
  where pu.id is null;
end;
$$;

-- =====================================================
-- ENSURE ADMIN ACCOUNT EXISTS IN public.users
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
  where role_name = 'Admin'
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
    company_id,
    branch_id,
    role_id,
    name,
    email,
    username,
    is_active,
    created_at,
    updated_at,
    last_active
  )
  values (
    uid,
    bootstrap_company_id,
    null,
    rid,
    'Admin User',
    'c.markode@gmail.com',
    null,
    true,
    now(),
    now(),
    null
  )
  on conflict (id) do update
  set
    company_id = coalesce(public.users.company_id, excluded.company_id),
    role_id = rid,
    name = coalesce(public.users.name, excluded.name),
    email = excluded.email,
    is_active = true,
    updated_at = now();
end;
$$;

notify pgrst, 'reload schema';
-- =====================================================
-- ENSURE CURRENT USER PROFILE
-- =====================================================

create extension if not exists "pgcrypto";

drop function if exists public.ensure_current_user_profile() cascade;

create or replace function public.ensure_current_user_profile()
returns json
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  current_uid uuid;
  auth_email text;
  auth_name text;
  assigned_role_id uuid;
  bootstrap_company_id uuid;
begin
  current_uid := auth.uid();

  if current_uid is null then
    raise exception 'Authentication required';
  end if;

  if exists (
    select 1 from public.users where id = current_uid
  ) then
    return json_build_object('status', 'ok', 'created', false);
  end if;

  select
    u.email,
    coalesce(u.raw_user_meta_data->>'name', split_part(coalesce(u.email, ''), '@', 1), 'User')
  into auth_email, auth_name
  from auth.users u
  where u.id = current_uid;

  if lower(coalesce(auth_email, '')) = 'c.markode@gmail.com' then
    select id into assigned_role_id
    from public.roles
    where role_name = 'Admin'
    limit 1;
  end if;

  if assigned_role_id is null then
    select id into assigned_role_id
    from public.roles
    where role_name in ('Employee', 'Viewer', 'Order Entry User')
    order by case
      when role_name = 'Employee' then 0
      when role_name = 'Order Entry User' then 1
      else 2
    end
    limit 1;
  end if;

  if assigned_role_id is null then
    select id into assigned_role_id
    from public.roles
    order by created_at
    limit 1;
  end if;

  select company_id into bootstrap_company_id
  from public.users
  where company_id is not null
  limit 1;

  if bootstrap_company_id is null then
    bootstrap_company_id := gen_random_uuid();
  end if;

  insert into public.users (
    id,
    company_id,
    branch_id,
    role_id,
    name,
    email,
    username,
    is_active,
    created_at,
    updated_at,
    last_active
  )
  values (
    current_uid,
    bootstrap_company_id,
    null,
    assigned_role_id,
    auth_name,
    auth_email,
    null,
    true,
    now(),
    now(),
    null
  )
  on conflict (id) do nothing;

  return json_build_object('status', 'ok', 'created', true);
end;
$$;

grant execute on function public.ensure_current_user_profile() to authenticated;

notify pgrst, 'reload schema';
-- =====================================================
-- FORCE USERS SELF SELECT POLICY
-- =====================================================

do $$
begin
  if exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'users'
      and policyname = 'users_read_own_profile'
  ) then
    execute 'drop policy "users_read_own_profile" on public.users';
  end if;

  execute '
    create policy "users_read_own_profile"
    on public.users
    for select
    to authenticated
    using (auth.uid() = id)
  ';
end;
$$;

notify pgrst, 'reload schema';
-- =====================================================
-- GET CURRENT USER PROFILE RPC
-- =====================================================

drop function if exists public.get_current_user_profile() cascade;

create or replace function public.get_current_user_profile()
returns json
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  current_uid uuid;
  user_row public.users%rowtype;
  resolved_role_name text;
  resolved_permissions text[];
begin
  current_uid := auth.uid();

  if current_uid is null then
    return null;
  end if;

  select *
  into user_row
  from public.users
  where id = current_uid;

  if not found then
    return null;
  end if;

  select role_name
  into resolved_role_name
  from public.roles
  where id = user_row.role_id;

  select coalesce(array_agg(distinct permission_code), '{}'::text[])
  into resolved_permissions
  from (
    select rp.permission_code
    from public.role_permissions rp
    where rp.role_id = user_row.role_id
    union
    select up.permission_code
    from public.user_permissions up
    where up.user_id = user_row.id
  ) permissions;

  return json_build_object(
    'id', user_row.id,
    'name', user_row.name,
    'email', user_row.email,
    'role_id', user_row.role_id,
    'role_name', coalesce(resolved_role_name, ''),
    'permissions', coalesce(resolved_permissions, '{}'::text[]),
    'created_at', user_row.created_at,
    'updated_at', user_row.updated_at,
    'last_active', user_row.last_active,
    'is_active', user_row.is_active
  );
end;
$$;

grant execute on function public.get_current_user_profile() to authenticated;

notify pgrst, 'reload schema';
-- =====================================================
-- REPAIR LIVE USER PROFILES
-- =====================================================

create extension if not exists "pgcrypto";

-- =====================================================
-- ENSURE SELF-READ POLICY EXISTS
-- =====================================================
drop policy if exists "users_read_own_profile" on public.users;

create policy "users_read_own_profile"
on public.users
for select
to authenticated
using (auth.uid() = id);

-- =====================================================
-- BACKFILL ANY MISSING public.users ROWS
-- =====================================================
do $$
declare
  admin_role_id uuid;
  employee_role_id uuid;
  fallback_company_id uuid;
begin
  select id into admin_role_id
  from public.roles
  where role_name = 'Admin'
  limit 1;

  select id into employee_role_id
  from public.roles
  where role_name in ('Employee', 'Order Entry User', 'Viewer')
  order by case
    when role_name = 'Employee' then 0
    when role_name = 'Order Entry User' then 1
    else 2
  end
  limit 1;

  select company_id into fallback_company_id
  from public.users
  where company_id is not null
  limit 1;

  if fallback_company_id is null then
    fallback_company_id := gen_random_uuid();
  end if;

  insert into public.users (
    id,
    company_id,
    branch_id,
    role_id,
    name,
    email,
    username,
    is_active,
    created_at,
    updated_at,
    last_active
  )
  select
    au.id,
    fallback_company_id,
    null,
    case
      when lower(coalesce(au.email, '')) = 'c.markode@gmail.com' and admin_role_id is not null
        then admin_role_id
      else coalesce(employee_role_id, admin_role_id)
    end,
    coalesce(
      au.raw_user_meta_data->>'name',
      split_part(coalesce(au.email, ''), '@', 1),
      'User'
    ),
    au.email,
    null,
    true,
    coalesce(au.created_at, now()),
    now(),
    null
  from auth.users au
  left join public.users pu on pu.id = au.id
  where pu.id is null;

  if admin_role_id is not null then
    update public.users u
    set
      role_id = admin_role_id,
      company_id = coalesce(u.company_id, fallback_company_id),
      is_active = true,
      updated_at = now()
    where lower(coalesce(u.email, '')) = 'c.markode@gmail.com';
  end if;
end
$$;

-- =====================================================
-- ENSURE CURRENT-USER RPCS ARE PRESENT WITH GRANTS
-- =====================================================
drop function if exists public.ensure_current_user_profile() cascade;

create or replace function public.ensure_current_user_profile()
returns json
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  current_uid uuid;
  created_profile boolean := false;
begin
  current_uid := auth.uid();

  if current_uid is null then
    raise exception 'Authentication required';
  end if;

  if not exists (select 1 from public.users where id = current_uid) then
    perform 1;
    insert into public.users (
      id,
      company_id,
      branch_id,
      role_id,
      name,
      email,
      username,
      is_active,
      created_at,
      updated_at,
      last_active
    )
    select
      au.id,
      coalesce((select company_id from public.users where company_id is not null limit 1), gen_random_uuid()),
      null,
      (
        select r.id
        from public.roles r
        where r.role_name = case
          when lower(coalesce(au.email, '')) = 'c.markode@gmail.com' then 'Admin'
          else 'Order Entry User'
        end
        limit 1
      ),
      coalesce(au.raw_user_meta_data->>'name', split_part(coalesce(au.email, ''), '@', 1), 'User'),
      au.email,
      null,
      true,
      coalesce(au.created_at, now()),
      now(),
      null
    from auth.users au
    where au.id = current_uid
    on conflict (id) do nothing;

    created_profile := true;
  end if;

  return json_build_object('status', 'ok', 'created', created_profile);
end;
$$;

grant execute on function public.ensure_current_user_profile() to authenticated;

drop function if exists public.get_current_user_profile() cascade;

create or replace function public.get_current_user_profile()
returns json
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  current_uid uuid;
  user_row public.users%rowtype;
  resolved_role_name text;
  resolved_permissions text[];
begin
  current_uid := auth.uid();

  if current_uid is null then
    return null;
  end if;

  if not exists (select 1 from public.users where id = current_uid) then
    perform public.ensure_current_user_profile();
  end if;

  select *
  into user_row
  from public.users
  where id = current_uid;

  if not found then
    return null;
  end if;

  select role_name
  into resolved_role_name
  from public.roles
  where id = user_row.role_id;

  select coalesce(array_agg(distinct permission_code), '{}'::text[])
  into resolved_permissions
  from (
    select rp.permission_code
    from public.role_permissions rp
    where rp.role_id = user_row.role_id
    union
    select up.permission_code
    from public.user_permissions up
    where up.user_id = user_row.id
  ) permissions;

  return json_build_object(
    'id', user_row.id,
    'name', user_row.name,
    'email', user_row.email,
    'role_id', user_row.role_id,
    'role_name', coalesce(resolved_role_name, ''),
    'permissions', coalesce(resolved_permissions, '{}'::text[]),
    'created_at', user_row.created_at,
    'updated_at', user_row.updated_at,
    'last_active', user_row.last_active,
    'is_active', user_row.is_active
  );
end;
$$;

grant execute on function public.get_current_user_profile() to authenticated;

notify pgrst, 'reload schema';
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
-- Add company_id to activity logs and propagate existing rows

alter table public.activity_logs
  add column if not exists company_id uuid;

-- Backfill from actor profile when possible
update public.activity_logs log
set company_id = coalesce(
  log.company_id,
  (
    select company_id
    from public.users u
    where u.id = log.actor_id
    limit 1
  )
)
where company_id is null;

create index if not exists idx_activity_logs_company on public.activity_logs(company_id);

-- Replace write_activity_log to auto-populate company_id
create or replace function public.write_activity_log(
  p_actor_id uuid,
  p_action text,
  p_entity_type text,
  p_entity_id uuid,
  p_metadata jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company_id uuid;
begin
  select company_id into v_company_id
  from public.users
  where id = p_actor_id
  limit 1;

  insert into activity_logs(
    actor_id,
    action,
    entity_type,
    entity_id,
    metadata,
    company_id
  )
  values(
    p_actor_id,
    p_action,
    p_entity_type,
    p_entity_id,
    p_metadata,
    v_company_id
  );
end;
$$;

grant execute on function public.write_activity_log(uuid,text,text,uuid,jsonb) to authenticated;
-- Strengthen activity_logs RLS for company scoping and explicit permission

drop policy if exists "admin_logs_access" on public.activity_logs;

create policy "activity_logs_admin_all"
on public.activity_logs
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

create policy "activity_logs_company_view"
on public.activity_logs
for select
to authenticated
using (
  exists (
    select 1
    from public.users u
    where u.id = auth.uid()
      and u.is_active
      and coalesce(activity_logs.company_id, u.company_id) = u.company_id
      and (
        public.is_admin()
        or exists (
          select 1
          from public.role_permissions rp
          join public.permissions p
            on p.code = rp.permission_code
          where rp.role_id = u.role_id
            and p.code = 'activity_logs_view'
        )
        or exists (
          select 1
          from public.user_permissions up
          where up.user_id = u.id
            and up.permission_code = 'activity_logs_view'
        )
      )
  )
);

notify pgrst, 'reload schema';
