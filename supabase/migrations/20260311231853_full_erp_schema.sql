-- =====================================================
-- FULL ERP BASELINE SCHEMA (Supabase + PostgreSQL)
-- Single migration intended for clean deploys
-- =====================================================

create extension if not exists "uuid-ossp";
create extension if not exists "pgcrypto";

-- =====================================================
-- ENUMS
-- =====================================================
do $$ begin
  if not exists (select 1 from pg_type where typname = 'order_status_enum') then
    create type public.order_status_enum as enum (
      'entered', 'checked', 'approved', 'shipped', 'completed', 'returned'
    );
  end if;
end $$;

-- =====================================================
-- CORE TABLES
-- =====================================================

create table if not exists public.companies (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  is_active boolean default true,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table if not exists public.branches (
  id uuid primary key default gen_random_uuid(),
  company_id uuid references public.companies(id) on delete cascade,
  name text not null,
  is_active boolean default true,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table if not exists public.roles (
  id uuid primary key default gen_random_uuid(),
  role_name text unique not null,
  description text,
  created_at timestamptz default now()
);

create table if not exists public.permissions (
  code text primary key,
  description text,
  created_at timestamptz default now()
);

create table if not exists public.role_permissions (
  role_id uuid references public.roles(id) on delete cascade,
  permission_code text references public.permissions(code) on delete cascade,
  granted_at timestamptz default now(),
  primary key (role_id, permission_code)
);

create table if not exists public.users (
  id uuid primary key references auth.users(id) on delete cascade,
  company_id uuid references public.companies(id) on delete set null,
  branch_id uuid references public.branches(id) on delete set null,
  role_id uuid references public.roles(id) on delete set null,
  name text,
  email text,
  username text,
  is_active boolean default true,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  last_active timestamptz
);
create index if not exists idx_users_email on public.users(email);
create index if not exists idx_users_role on public.users(role_id);
create index if not exists idx_users_company on public.users(company_id);

create table if not exists public.user_permissions (
  user_id uuid references public.users(id) on delete cascade,
  permission_code text references public.permissions(code) on delete cascade,
  granted_at timestamptz default now(),
  primary key (user_id, permission_code)
);
create index if not exists idx_user_permissions_user on public.user_permissions(user_id);

create table if not exists public.user_logins (
  user_id uuid primary key references public.users(id) on delete cascade,
  last_login_at timestamptz,
  login_count integer default 0
);

-- =====================================================
-- MASTER DATA
-- =====================================================
create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  company_id uuid references public.companies(id) on delete cascade,
  branch_id uuid references public.branches(id) on delete set null,
  name text not null,
  sku text unique,
  category text,
  purchase_price numeric(14,2) default 0,
  sale_price numeric(14,2) default 0,
  current_stock integer default 0,
  min_stock_level integer default 0,
  is_active boolean default true,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
create index if not exists idx_products_company on public.products(company_id);
create index if not exists idx_products_sku on public.products(sku);

create table if not exists public.inventory_adjustments (
  id uuid primary key default gen_random_uuid(),
  product_id uuid references public.products(id) on delete cascade,
  actor_id uuid references public.users(id) on delete set null,
  company_id uuid references public.companies(id) on delete cascade,
  quantity_delta integer not null,
  reason text,
  created_at timestamptz default now()
);
create index if not exists idx_adj_product on public.inventory_adjustments(product_id);

-- =====================================================
-- ORDERS
-- =====================================================
create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  company_id uuid references public.companies(id) on delete cascade,
  branch_id uuid references public.branches(id) on delete set null,
  customer_name text not null,
  customer_phone text,
  customer_address text,
  order_notes text,
  status public.order_status_enum default 'entered',
  created_by uuid references public.users(id) on delete set null,
  created_by_name text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
create index if not exists idx_orders_company on public.orders(company_id);
create index if not exists idx_orders_status on public.orders(status);

create table if not exists public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid references public.orders(id) on delete cascade,
  product_id uuid references public.products(id) on delete set null,
  product_name text,
  quantity integer not null,
  purchase_price numeric(14,2),
  sale_price numeric(14,2),
  created_at timestamptz default now()
);
create index if not exists idx_order_items_order on public.order_items(order_id);

create table if not exists public.order_status_history (
  id uuid primary key default gen_random_uuid(),
  order_id uuid references public.orders(id) on delete cascade,
  status public.order_status_enum,
  changed_by uuid references public.users(id) on delete set null,
  changed_by_name text,
  note text,
  changed_at timestamptz default now()
);
create index if not exists idx_order_history_order on public.order_status_history(order_id);

-- =====================================================
-- INVOICES
-- =====================================================
create table if not exists public.invoices (
  id uuid primary key default gen_random_uuid(),
  order_id uuid references public.orders(id) on delete cascade,
  company_id uuid references public.companies(id) on delete cascade,
  amount_due numeric(14,2) not null,
  amount_paid numeric(14,2) default 0,
  status text default 'unpaid',
  issued_at timestamptz default now(),
  due_at timestamptz,
  paid_at timestamptz,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
create index if not exists idx_invoices_order on public.invoices(order_id);

-- =====================================================
-- NOTIFICATIONS
-- =====================================================
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.users(id) on delete cascade,
  title text,
  message text,
  type text,
  read boolean default false,
  reference_id text,
  created_at timestamptz default now()
);
create index if not exists idx_notifications_user on public.notifications(user_id);

-- Inventory projection (REST expects "inventory" resource); expose as view over products
create or replace view public.inventory as
select
  p.id,
  p.company_id,
  p.branch_id,
  p.name,
  p.sku,
  p.category,
  p.current_stock as stock,
  p.min_stock_level as min_stock,
  p.purchase_price,
  p.sale_price,
  p.is_active,
  p.created_at,
  p.updated_at
from public.products p;

-- Convenience view for products list with stock
create or replace view public.v_products as
select
  p.*,
  p.current_stock as stock,
  p.min_stock_level as min_stock
from public.products p;

-- =====================================================
-- FILE REFERENCES (for Storage)
-- =====================================================
create table if not exists public.file_refs (
  id uuid primary key default gen_random_uuid(),
  bucket text not null,
  path text not null,
  owner_id uuid references public.users(id) on delete set null,
  company_id uuid references public.companies(id) on delete cascade,
  created_at timestamptz default now()
);
create index if not exists idx_file_refs_company on public.file_refs(company_id);

-- =====================================================
-- ACTIVITY LOGS
-- =====================================================
create table if not exists public.activity_logs (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid,
  action text,
  entity_type text,
  entity_id uuid,
  metadata jsonb,
  company_id uuid,
  created_at timestamptz default now()
);
create index if not exists idx_logs_actor on public.activity_logs(actor_id);
create index if not exists idx_logs_company on public.activity_logs(company_id);

-- =====================================================
-- DEFAULT DATA
-- =====================================================
insert into public.roles (role_name, description)
values
  ('Admin', 'System Administrator'),
  ('Order Reviewer', 'Reviews and approves orders'),
  ('Shipping User', 'Handles shipping and fulfillment'),
  ('Order Entry User', 'Creates and manages draft orders'),
  ('Viewer', 'Read Only')
on conflict (role_name) do nothing;

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
on conflict do nothing;

insert into public.role_permissions (role_id, permission_code)
select r.id, p.code
from public.roles r
cross join public.permissions p
where r.role_name = 'Admin'
on conflict do nothing;

-- View: users with permissions flattened
create or replace view public.v_users_with_permissions as
select
  u.id,
  u.email,
  u.name,
  r.role_name,
  p.code as permission_code
from public.users u
left join public.roles r on r.id = u.role_id
left join public.role_permissions rp on rp.role_id = r.id
left join public.permissions p on p.code = rp.permission_code;
grant select on public.v_users_with_permissions to authenticated;

-- =====================================================
-- FUNCTIONS & TRIGGERS
-- =====================================================
create or replace function public.get_user_role(uid uuid)
returns text
language plpgsql
stable
set search_path = public
as $$
declare r text;
begin
  select role_name into r from roles where id = (select role_id from users where id = uid);
  return r;
end;
$$;

create or replace function public.is_admin()
returns boolean
language plpgsql
security definer
stable
set search_path = public
as $$
begin
  return public.get_user_role(auth.uid()) = 'Admin';
end;
$$;

create or replace function public.record_user_login(p_user_id uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or auth.uid() <> p_user_id then
    raise exception 'unauthorized';
  end if;

  update users
  set last_active = now(), updated_at = now()
  where id = p_user_id;

  insert into user_logins(user_id, last_login_at, login_count)
  values(p_user_id, now(), 1)
  on conflict(user_id)
  do update set
    last_login_at = excluded.last_login_at,
    login_count = user_logins.login_count + 1;

  return json_build_object('status', 'ok');
end;
$$;
grant execute on function public.record_user_login(uuid) to authenticated;

create or replace function public.write_activity_log(
  p_actor_id uuid,
  p_action text,
  p_entity_type text,
  p_entity_id uuid,
  p_metadata jsonb
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_company uuid;
begin
  select company_id into v_company from public.users where id = p_actor_id limit 1;
  insert into activity_logs(actor_id, action, entity_type, entity_id, metadata, company_id)
  values(p_actor_id, p_action, p_entity_type, p_entity_id, p_metadata, v_company);
end;
$$;
grant execute on function public.write_activity_log(uuid,text,text,uuid,jsonb) to authenticated;

create or replace function public.ensure_current_user_profile()
returns json
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  current_uid uuid := auth.uid();
  created_profile boolean := false;
  company_id uuid;
  role_id uuid;
begin
  if current_uid is null then
    raise exception 'Authentication required';
  end if;

  if exists (select 1 from public.users where id = current_uid) then
    return json_build_object('status','ok','created',false);
  end if;

  select coalesce((select company_id from public.users where company_id is not null limit 1), gen_random_uuid())
  into company_id;

  select id into role_id from public.roles where role_name = 'Order Entry User' limit 1;
  if role_id is null then
    select id into role_id from public.roles order by created_at limit 1;
  end if;

  insert into public.users(id, company_id, role_id, name, email, username, is_active, created_at, updated_at)
  select
    au.id,
    company_id,
    role_id,
    coalesce(au.raw_user_meta_data->>'name', split_part(coalesce(au.email,''), '@', 1), 'User'),
    au.email,
    null,
    true,
    coalesce(au.created_at, now()),
    now()
  from auth.users au
  where au.id = current_uid
  on conflict (id) do nothing;

  created_profile := true;
  return json_build_object('status','ok','created',created_profile);
end;
$$;
grant execute on function public.ensure_current_user_profile() to authenticated;

create or replace function public.get_current_user_profile()
returns json
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  current_uid uuid := auth.uid();
  user_row public.users%rowtype;
  resolved_role_name text;
  resolved_permissions text[];
begin
  if current_uid is null then
    return null;
  end if;

  if not exists (select 1 from public.users where id = current_uid) then
    perform public.ensure_current_user_profile();
  end if;

  select * into user_row from public.users where id = current_uid;

  select role_name into resolved_role_name from public.roles where id = user_row.role_id;

  select coalesce(array_agg(distinct permission_code), '{}'::text[])
  into resolved_permissions
  from (
    select rp.permission_code from public.role_permissions rp where rp.role_id = user_row.role_id
    union
    select up.permission_code from public.user_permissions up where up.user_id = user_row.id
  ) p;

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

-- Order creation
create or replace function public.create_order(
  p_customer_name text,
  p_customer_phone text,
  p_items jsonb,
  p_order_notes text default null,
  p_customer_address text default null
) returns uuid
language plpgsql security definer
set search_path = public
as $$
declare
  v_order_id uuid := gen_random_uuid();
  v_user record;
begin
  select id, company_id, branch_id, name into v_user from public.users where id = auth.uid();
  if v_user.id is null then raise exception 'user_not_found'; end if;

  insert into public.orders(
    id, company_id, branch_id,
    customer_name, customer_phone, customer_address,
    order_notes, created_by, created_by_name
  )
  values (
    v_order_id, v_user.company_id, v_user.branch_id,
    p_customer_name, p_customer_phone, p_customer_address,
    p_order_notes, v_user.id, v_user.name
  );

  insert into public.order_items(order_id, product_id, quantity, product_name, purchase_price, sale_price)
  select v_order_id,
         (item->>'product_id')::uuid,
         coalesce((item->>'quantity')::int, 1),
         p.name,
         p.purchase_price,
         p.sale_price
  from jsonb_array_elements(p_items) item
  join public.products p on p.id = (item->>'product_id')::uuid;

  insert into public.order_status_history(order_id, status, changed_by, changed_by_name, note)
  values (v_order_id, 'entered', v_user.id, v_user.name, p_order_notes);

  return v_order_id;
end;
$$;
grant execute on function public.create_order(text,text,jsonb,text,text) to authenticated;

-- Wrapper to satisfy legacy PostgREST signature without address
create or replace function public.create_order(
  p_customer_name text,
  p_customer_phone text,
  p_items jsonb,
  p_order_notes text default null
) returns uuid
language sql
security definer
set search_path = public
as $$
  select public.create_order(p_customer_name, p_customer_phone, p_items, p_order_notes, null);
$$;
grant execute on function public.create_order(text,text,jsonb,text) to authenticated;

-- Order update
create or replace function public.update_order(
  p_order_id uuid,
  p_customer_name text,
  p_customer_phone text,
  p_items jsonb,
  p_order_notes text default null,
  p_customer_address text default null
) returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_user record;
  v_status public.order_status_enum;
begin
  select id, company_id, branch_id, name into v_user from public.users where id = auth.uid();
  if v_user.id is null then raise exception 'user_not_found'; end if;

  select status into v_status from public.orders where id = p_order_id;
  if v_status is null then
    raise exception 'order_not_found';
  end if;

  update public.orders
    set customer_name = p_customer_name,
        customer_phone = p_customer_phone,
        customer_address = p_customer_address,
        order_notes = p_order_notes,
        updated_at = now()
  where id = p_order_id;

  delete from public.order_items where order_id = p_order_id;

  insert into public.order_items(order_id, product_id, quantity, product_name, purchase_price, sale_price)
  select p_order_id,
         (item->>'product_id')::uuid,
         coalesce((item->>'quantity')::int, 1),
         p.name,
         p.purchase_price,
         p.sale_price
  from jsonb_array_elements(p_items) item
  join public.products p on p.id = (item->>'product_id')::uuid;

  insert into public.order_status_history(order_id, status, changed_by, changed_by_name, note)
  values (p_order_id, v_status, v_user.id, v_user.name, p_order_notes);
end;
$$;
grant execute on function public.update_order(uuid,text,text,jsonb,text,text) to authenticated;

-- Legacy wrapper with order_id last (API generator expectation)
create or replace function public.update_order(
  p_customer_name text,
  p_customer_phone text,
  p_items jsonb,
  p_order_id uuid,
  p_order_notes text default null
) returns void
language sql
security definer
set search_path = public
as $$
  select public.update_order(p_order_id, p_customer_name, p_customer_phone, p_items, p_order_notes, null);
$$;
grant execute on function public.update_order(text,text,jsonb,uuid,text) to authenticated;

-- Wrapper to satisfy legacy PostgREST signature without address
create or replace function public.update_order(
  p_order_id uuid,
  p_customer_name text,
  p_customer_phone text,
  p_items jsonb,
  p_order_notes text default null
) returns void
language sql
security definer
set search_path = public
as $$
  select public.update_order(p_order_id, p_customer_name, p_customer_phone, p_items, p_order_notes, null);
$$;
grant execute on function public.update_order(uuid,text,text,jsonb,text) to authenticated;

-- Delete order
create or replace function public.delete_order(p_order_id uuid)
returns void
language plpgsql security definer
set search_path = public
as $$
begin
  delete from public.orders where id = p_order_id;
end;
$$;
grant execute on function public.delete_order(uuid) to authenticated;

-- Transition order status
create or replace function public.transition_order(
  p_order_id uuid,
  p_next_status text,
  p_note text default null
) returns void
language plpgsql security definer
set search_path = public
as $$
declare v_user record;
begin
  select id, name into v_user from public.users where id = auth.uid();
  if v_user.id is null then raise exception 'user_not_found'; end if;

  update public.orders
  set status = p_next_status::public.order_status_enum,
      updated_at = now()
  where id = p_order_id;

  insert into public.order_status_history(order_id, status, changed_by, changed_by_name, note)
  values (p_order_id, p_next_status::public.order_status_enum, v_user.id, v_user.name, p_note);
end;
$$;
grant execute on function public.transition_order(uuid,text,text) to authenticated;

-- Override order status (same as transition but separated for ACL)
create or replace function public.override_order_status(
  p_order_id uuid,
  p_next_status text,
  p_note text default null
) returns void
language sql
security definer
set search_path = public
as $$
  select public.transition_order(p_order_id, p_next_status, p_note);
$$;
grant execute on function public.override_order_status(uuid,text,text) to authenticated;

-- Upsert product
create or replace function public.upsert_product(
  p_product_id uuid,
  p_name text,
  p_sku text,
  p_category text,
  p_purchase_price numeric,
  p_sale_price numeric,
  p_stock int,
  p_min_stock int
) returns uuid
language plpgsql security definer
set search_path = public
as $$
declare
  v_id uuid := coalesce(p_product_id, gen_random_uuid());
  v_user record;
begin
  select id, company_id, branch_id into v_user from public.users where id = auth.uid();
  if v_user.id is null then raise exception 'user_not_found'; end if;

  insert into public.products(
    id, company_id, branch_id, name, sku, category,
    purchase_price, sale_price, current_stock, min_stock_level, is_active
  )
  values (
    v_id, v_user.company_id, v_user.branch_id, p_name, p_sku, p_category,
    p_purchase_price, p_sale_price, p_stock, p_min_stock, true
  )
  on conflict (id) do update set
    name = excluded.name,
    sku = excluded.sku,
    category = excluded.category,
    purchase_price = excluded.purchase_price,
    sale_price = excluded.sale_price,
    current_stock = excluded.current_stock,
    min_stock_level = excluded.min_stock_level,
    updated_at = now();

  return v_id;
end;
$$;
grant execute on function public.upsert_product(uuid,text,text,text,numeric,numeric,int,int) to authenticated;

-- Wrapper matching legacy parameter ordering from runtime checker
create or replace function public.upsert_product(
  p_category text,
  p_min_stock int,
  p_name text,
  p_product_id uuid,
  p_purchase_price numeric,
  p_sale_price numeric,
  p_sku text,
  p_stock int
) returns uuid
language sql
security definer
set search_path = public
as $$
  select public.upsert_product(
    p_product_id,
    p_name,
    p_sku,
    p_category,
    p_purchase_price,
    p_sale_price,
    p_stock,
    p_min_stock
  );
$$;
grant execute on function public.upsert_product(text,int,text,uuid,numeric,numeric,text,int) to authenticated;

-- Mark notification read
create or replace function public.mark_notification_read(p_notification_id uuid)
returns void
language plpgsql security definer
set search_path = public
as $$
begin
  update public.notifications
  set read = true
  where id = p_notification_id and user_id = auth.uid();
end;
$$;
grant execute on function public.mark_notification_read(uuid) to authenticated;

-- Inventory adjustment
create or replace function public.adjust_inventory(
  p_product_id uuid,
  p_quantity_delta integer,
  p_reason text
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user record;
begin
  select id, company_id into v_user from public.users where id = auth.uid();
  if v_user.id is null then raise exception 'user_not_found'; end if;

  update public.products
  set current_stock = current_stock + p_quantity_delta,
      updated_at = now()
  where id = p_product_id;

  insert into public.inventory_adjustments(
    product_id, actor_id, company_id, quantity_delta, reason
  )
  values (p_product_id, v_user.id, v_user.company_id, p_quantity_delta, p_reason);
end;
$$;
grant execute on function public.adjust_inventory(uuid, integer, text) to authenticated;

-- Auto-grant new permissions to Admin + seeded super admin
create or replace function public.fn_grant_permission_to_admin()
returns trigger
language plpgsql
security definer
as $$
declare
  v_admin_role_id uuid;
  v_admin_user_id uuid;
begin
  select id into v_admin_role_id from public.roles where lower(role_name) = 'admin' limit 1;
  if v_admin_role_id is not null then
    insert into public.role_permissions(role_id, permission_code)
    values (v_admin_role_id, new.code)
    on conflict do nothing;
  end if;

  select id into v_admin_user_id from auth.users where lower(email) = 'markode@gmail.com' limit 1;
  if v_admin_user_id is not null then
    insert into public.user_permissions(user_id, permission_code)
    values (v_admin_user_id, new.code)
    on conflict do nothing;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_permissions_auto_grant_admin on public.permissions;
create trigger trg_permissions_auto_grant_admin
after insert on public.permissions
for each row execute function public.fn_grant_permission_to_admin();

-- =====================================================
-- RLS ENABLE + POLICIES
-- =====================================================
alter table public.users enable row level security;
alter table public.activity_logs enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.products enable row level security;
alter table public.notifications enable row level security;
alter table public.invoices enable row level security;
alter table public.inventory_adjustments enable row level security;

-- Users: admins manage all, users read self
drop policy if exists "users_read_own_profile" on public.users;
create policy "users_read_own_profile"
on public.users for select
to authenticated
using (auth.uid() = id);

create policy "users_admin_all"
on public.users for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

-- Activity logs
drop policy if exists "activity_logs_admin_all" on public.activity_logs;
drop policy if exists "activity_logs_company_view" on public.activity_logs;
create policy "activity_logs_admin_all"
on public.activity_logs for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

create policy "activity_logs_company_view"
on public.activity_logs for select
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
          select 1 from public.role_permissions rp where rp.role_id = u.role_id and rp.permission_code = 'activity_logs_view'
        )
        or exists (
          select 1 from public.user_permissions up where up.user_id = u.id and up.permission_code = 'activity_logs_view'
        )
      )
  )
);

-- Orders: company scoped
create policy "orders_company_access"
on public.orders for select
to authenticated
using (company_id = (select company_id from public.users where id = auth.uid() limit 1));

create policy "orders_company_write"
on public.orders for all
to authenticated
using (public.is_admin() or company_id = (select company_id from public.users where id = auth.uid() limit 1))
with check (company_id = (select company_id from public.users where id = auth.uid() limit 1));

-- Order items inherit from parent
create policy "order_items_company_access"
on public.order_items for select
to authenticated
using (
  exists (
    select 1 from public.orders o
    where o.id = order_items.order_id
      and o.company_id = (select company_id from public.users where id = auth.uid() limit 1)
  )
);

create policy "order_items_company_write"
on public.order_items for all
to authenticated
using (
  exists (
    select 1 from public.orders o
    where o.id = order_items.order_id
      and o.company_id = (select company_id from public.users where id = auth.uid() limit 1)
  )
)
with check (
  exists (
    select 1 from public.orders o
    where o.id = order_items.order_id
      and o.company_id = (select company_id from public.users where id = auth.uid() limit 1)
  )
);

-- Products: company scoped read/write
create policy "products_company_access"
on public.products for select
to authenticated
using (company_id = (select company_id from public.users where id = auth.uid() limit 1));

create policy "products_company_write"
on public.products for all
to authenticated
using (public.is_admin() or company_id = (select company_id from public.users where id = auth.uid() limit 1))
with check (company_id = (select company_id from public.users where id = auth.uid() limit 1));

-- Inventory adjustments
create policy "inventory_adj_company_access"
on public.inventory_adjustments for select
to authenticated
using (company_id = (select company_id from public.users where id = auth.uid() limit 1));

create policy "inventory_adj_company_write"
on public.inventory_adjustments for all
to authenticated
using (public.is_admin() or company_id = (select company_id from public.users where id = auth.uid() limit 1))
with check (company_id = (select company_id from public.users where id = auth.uid() limit 1));

-- Invoices
create policy "invoices_company_access"
on public.invoices for select
to authenticated
using (company_id = (select company_id from public.users where id = auth.uid() limit 1));

create policy "invoices_company_write"
on public.invoices for all
to authenticated
using (public.is_admin() or company_id = (select company_id from public.users where id = auth.uid() limit 1))
with check (company_id = (select company_id from public.users where id = auth.uid() limit 1));

-- Notifications: self only
create policy "notifications_self"
on public.notifications for select
to authenticated
using (user_id = auth.uid());

create policy "notifications_self_write"
on public.notifications for update
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

-- =====================================================
-- ADMIN BOOTSTRAP (idempotent)
-- =====================================================
do $$
declare
  v_email text := 'markode@gmail.com';
  v_user_id uuid;
  v_role_id uuid;
  v_company uuid;
begin
  select id into v_role_id from public.roles where lower(role_name) = 'admin' limit 1;
  if v_role_id is null then
    insert into public.roles(role_name, description)
    values ('Admin', 'System administrator')
    returning id into v_role_id;
  end if;

  select id into v_user_id from auth.users where lower(email) = lower(v_email) limit 1;
  if v_user_id is null then
    insert into auth.users (
      id, email, encrypted_password, email_confirmed_at, created_at, updated_at
    )
    values (
      gen_random_uuid(),
      v_email,
      crypt('123456', gen_salt('bf')),
      now(), now(), now()
    )
    returning id into v_user_id;
  end if;

  select id into v_company from public.companies limit 1;
  if v_company is null then
    insert into public.companies(name) values ('Default Company') returning id into v_company;
  end if;

  insert into public.users(id, email, name, is_active, company_id, role_id)
  values (v_user_id, v_email, 'Admin', true, v_company, v_role_id)
  on conflict (id) do update set
    email = excluded.email,
    name = coalesce(public.users.name, excluded.name),
    is_active = true,
    company_id = coalesce(public.users.company_id, excluded.company_id),
    role_id = excluded.role_id;

  insert into public.role_permissions (role_id, permission_code)
  select v_role_id, p.code from public.permissions p
  on conflict do nothing;

  insert into public.user_permissions (user_id, permission_code)
  select v_user_id, p.code from public.permissions p
  on conflict do nothing;
end;
$$;

-- =====================================================
-- FINAL: REFRESH API
-- =====================================================
notify pgrst, 'reload schema';
