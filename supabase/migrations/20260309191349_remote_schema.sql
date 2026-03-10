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
