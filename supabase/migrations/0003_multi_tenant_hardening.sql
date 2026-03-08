create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table if not exists public.companies (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null unique,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.branches (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  name text not null,
  code text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (company_id, name),
  unique (company_id, code)
);

drop trigger if exists trg_companies_updated_at on public.companies;
create trigger trg_companies_updated_at
before update on public.companies
for each row execute procedure public.touch_updated_at();

drop trigger if exists trg_branches_updated_at on public.branches;
create trigger trg_branches_updated_at
before update on public.branches
for each row execute procedure public.touch_updated_at();

insert into public.companies (name, slug)
values ('Default Company', 'default-company')
on conflict (slug) do nothing;

insert into public.branches (company_id, name, code)
select c.id, 'Main Branch', 'main'
from public.companies c
where c.slug = 'default-company'
on conflict (company_id, code) do nothing;

create or replace function public.default_company_id()
returns uuid
language sql
stable
set search_path = public
as $$
  select id
  from public.companies
  order by created_at, id
  limit 1
$$;

create or replace function public.default_branch_id()
returns uuid
language sql
stable
set search_path = public
as $$
  select id
  from public.branches
  order by created_at, id
  limit 1
$$;

alter table public.users
add column if not exists company_id uuid references public.companies(id),
add column if not exists branch_id uuid references public.branches(id);

alter table public.products
add column if not exists company_id uuid references public.companies(id);

alter table public.inventory
add column if not exists company_id uuid references public.companies(id),
add column if not exists branch_id uuid references public.branches(id);

alter table public.inventory_transactions
add column if not exists company_id uuid references public.companies(id),
add column if not exists branch_id uuid references public.branches(id);

alter table public.orders
add column if not exists company_id uuid references public.companies(id),
add column if not exists branch_id uuid references public.branches(id);

alter table public.returns
add column if not exists company_id uuid references public.companies(id),
add column if not exists branch_id uuid references public.branches(id);

alter table public.notifications
add column if not exists company_id uuid references public.companies(id);

alter table public.activity_logs
add column if not exists company_id uuid references public.companies(id);

do $$
declare
  v_company_id uuid;
  v_branch_id uuid;
begin
  select id into v_company_id
  from public.companies
  where slug = 'default-company';

  select b.id into v_branch_id
  from public.branches b
  where b.company_id = v_company_id
    and b.code = 'main';

  update public.users
  set
    company_id = coalesce(company_id, v_company_id),
    branch_id = coalesce(branch_id, v_branch_id)
  where company_id is null
     or branch_id is null;

  update public.products
  set company_id = coalesce(company_id, v_company_id)
  where company_id is null;

  update public.inventory i
  set
    company_id = coalesce(i.company_id, p.company_id, v_company_id),
    branch_id = coalesce(i.branch_id, v_branch_id)
  from public.products p
  where p.id = i.product_id
    and (i.company_id is null or i.branch_id is null);

  update public.inventory_transactions it
  set
    company_id = coalesce(
      it.company_id,
      (select u.company_id from public.users u where u.id = it.created_by),
      (select p.company_id from public.products p where p.id = it.product_id),
      v_company_id
    ),
    branch_id = coalesce(
      it.branch_id,
      (select u.branch_id from public.users u where u.id = it.created_by),
      v_branch_id
    )
  where it.company_id is null
     or it.branch_id is null;

  update public.orders o
  set
    company_id = coalesce(o.company_id, u.company_id, v_company_id),
    branch_id = coalesce(o.branch_id, u.branch_id, v_branch_id)
  from public.users u
  where u.id = o.created_by
    and (o.company_id is null or o.branch_id is null);

  update public.returns r
  set
    company_id = coalesce(
      r.company_id,
      (select o.company_id from public.orders o where o.id = r.order_id),
      (select u.company_id from public.users u where u.id = r.created_by),
      v_company_id
    ),
    branch_id = coalesce(
      r.branch_id,
      (select o.branch_id from public.orders o where o.id = r.order_id),
      (select u.branch_id from public.users u where u.id = r.created_by),
      v_branch_id
    )
  where r.company_id is null
     or r.branch_id is null;

  update public.notifications n
  set company_id = coalesce(n.company_id, u.company_id, v_company_id)
  from public.users u
  where u.id = n.user_id
    and n.company_id is null;

  update public.activity_logs a
  set company_id = coalesce(
    a.company_id,
    (select u.company_id from public.users u where u.id = a.user_id),
    (select au.company_id from public.users au where au.id = a.actor_id),
    v_company_id
  )
  where a.company_id is null;

  update public.activity_logs
  set company_id = coalesce(company_id, v_company_id)
  where company_id is null;
end;
$$;

alter table public.users
alter column company_id set not null,
alter column branch_id set not null;

alter table public.products
alter column company_id set not null;

alter table public.inventory
alter column company_id set not null,
alter column branch_id set not null;

alter table public.inventory_transactions
alter column company_id set not null,
alter column branch_id set not null;

alter table public.orders
alter column company_id set not null,
alter column branch_id set not null;

alter table public.returns
alter column company_id set not null,
alter column branch_id set not null;

alter table public.notifications
alter column company_id set not null;

alter table public.activity_logs
alter column company_id set not null;

create or replace function public.apply_company_default()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company_id uuid;
begin
  if auth.uid() is not null then
    select company_id
    into v_company_id
    from public.users
    where id = auth.uid();
  end if;

  new.company_id := coalesce(new.company_id, v_company_id, public.default_company_id());
  return new;
end;
$$;

create or replace function public.apply_company_branch_default()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company_id uuid;
  v_branch_id uuid;
begin
  if auth.uid() is not null then
    select company_id, branch_id
    into v_company_id, v_branch_id
    from public.users
    where id = auth.uid();
  end if;

  new.company_id := coalesce(new.company_id, v_company_id, public.default_company_id());
  new.branch_id := coalesce(new.branch_id, v_branch_id, public.default_branch_id());
  return new;
end;
$$;

drop trigger if exists trg_users_tenant_defaults on public.users;
create trigger trg_users_tenant_defaults
before insert on public.users
for each row execute function public.apply_company_branch_default();

drop trigger if exists trg_products_tenant_defaults on public.products;
create trigger trg_products_tenant_defaults
before insert on public.products
for each row execute function public.apply_company_default();

drop trigger if exists trg_inventory_tenant_defaults on public.inventory;
create trigger trg_inventory_tenant_defaults
before insert on public.inventory
for each row execute function public.apply_company_branch_default();

drop trigger if exists trg_inventory_transactions_tenant_defaults on public.inventory_transactions;
create trigger trg_inventory_transactions_tenant_defaults
before insert on public.inventory_transactions
for each row execute function public.apply_company_branch_default();

drop trigger if exists trg_orders_tenant_defaults on public.orders;
create trigger trg_orders_tenant_defaults
before insert on public.orders
for each row execute function public.apply_company_branch_default();

drop trigger if exists trg_returns_tenant_defaults on public.returns;
create trigger trg_returns_tenant_defaults
before insert on public.returns
for each row execute function public.apply_company_branch_default();

drop trigger if exists trg_notifications_tenant_defaults on public.notifications;
create trigger trg_notifications_tenant_defaults
before insert on public.notifications
for each row execute function public.apply_company_default();

drop trigger if exists trg_activity_logs_tenant_defaults on public.activity_logs;
create trigger trg_activity_logs_tenant_defaults
before insert on public.activity_logs
for each row execute function public.apply_company_default();

create index if not exists idx_users_company_branch_active
on public.users(company_id, branch_id, is_active);

create index if not exists idx_products_company_name
on public.products(company_id, name);

create index if not exists idx_products_company_sku
on public.products(company_id, sku);

create index if not exists idx_inventory_company_branch_stock
on public.inventory(company_id, branch_id, stock, min_stock);

create index if not exists idx_inventory_transactions_company_branch_created
on public.inventory_transactions(company_id, branch_id, created_at desc);

create index if not exists idx_inventory_transactions_product_created
on public.inventory_transactions(product_id, created_at desc);

create index if not exists idx_orders_company_branch_date
on public.orders(company_id, branch_id, order_date desc);

create index if not exists idx_orders_company_status_date
on public.orders(company_id, status, order_date desc);

create index if not exists idx_order_items_order_product
on public.order_items(order_id, product_id);

create index if not exists idx_order_status_history_order_changed
on public.order_status_history(order_id, changed_at desc);

create index if not exists idx_order_status_history_changed_by
on public.order_status_history(changed_by, changed_at desc);

create index if not exists idx_returns_company_branch_created
on public.returns(company_id, branch_id, created_at desc);

create index if not exists idx_return_items_return_id
on public.return_items(return_id);

create index if not exists idx_notifications_company_user_created
on public.notifications(company_id, user_id, created_at desc);

create index if not exists idx_notifications_unread
on public.notifications(user_id, read, created_at desc);

create index if not exists idx_activity_logs_company_created
on public.activity_logs(company_id, created_at desc);

create index if not exists idx_role_permissions_permission_code
on public.role_permissions(permission_code);

create or replace function public.current_company_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select company_id
  from public.users
  where id = auth.uid()
$$;

create or replace function public.current_branch_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select branch_id
  from public.users
  where id = auth.uid()
$$;

create or replace function public.tenant_match(p_company_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.current_company_id() is not null
    and p_company_id = public.current_company_id()
$$;

create or replace function public.branch_match(p_branch_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_admin()
    or p_branch_id is null
    or (
      public.current_branch_id() is not null
      and p_branch_id = public.current_branch_id()
    )
$$;

create or replace function public.current_role_name()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select r.role_name
  from public.users u
  join public.roles r on r.id = u.role_id
  where u.id = auth.uid()
$$;

create or replace function public.current_user_is_active()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(u.is_active, false)
  from public.users u
  where u.id = auth.uid()
$$;

create or replace function public.current_user_permissions()
returns table(permission_code text)
language sql
stable
security definer
set search_path = public
as $$
  with direct_permissions as (
    select up.permission_code
    from public.user_permissions up
    where up.user_id = auth.uid()
  ),
  role_permissions as (
    select rp.permission_code
    from public.users u
    join public.role_permissions rp on rp.role_id = u.role_id
    where u.id = auth.uid()
  )
  select distinct permission_code
  from (
    select permission_code from direct_permissions
    union all
    select permission_code from role_permissions
  ) permissions
$$;

create or replace function public.has_permission(permission_code text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.current_user_is_active()
    and (
      public.current_role_name() = 'Admin'
      or exists (
        select 1
        from public.current_user_permissions() p
        where p.permission_code = $1
      )
    )
$$;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.current_role_name() = 'Admin'
$$;

drop view if exists public.profiles cascade;

create view public.profiles
with (security_invoker = true)
as
select
  u.id,
  u.company_id,
  u.branch_id,
  u.name,
  u.email,
  u.username,
  u.role_id,
  u.is_active,
  u.created_at,
  u.updated_at,
  u.last_active
from public.users u;

drop view if exists public.user_roles cascade;

create view public.user_roles
with (security_invoker = true)
as
select
  u.id as user_id,
  u.company_id,
  u.branch_id,
  u.role_id,
  r.role_name,
  u.is_active,
  u.created_at,
  u.updated_at
from public.users u
join public.roles r on r.id = u.role_id;

drop view if exists public.audit_logs cascade;

create view public.audit_logs
with (security_invoker = true)
as
select
  a.id,
  a.company_id,
  a.actor_id,
  a.user_id,
  a.actor_name,
  a.action,
  a.entity_type,
  a.entity_id,
  a.metadata,
  a.created_at
from public.activity_logs a;

drop view if exists public.v_users_with_permissions cascade;

create view public.v_users_with_permissions
with (security_invoker = true)
as
with effective_permissions as (
  select
    u.id as user_id,
    rp.permission_code
  from public.users u
  join public.role_permissions rp on rp.role_id = u.role_id
  union
  select
    up.user_id,
    up.permission_code
  from public.user_permissions up
)
select
  u.id,
  u.company_id,
  u.branch_id,
  u.name,
  u.email,
  u.username,
  u.role_id,
  r.role_name,
  u.is_active,
  u.created_at,
  u.updated_at,
  u.last_active,
  coalesce(
    array_agg(distinct ep.permission_code)
      filter (where ep.permission_code is not null),
    '{}'
  ) as permissions
from public.users u
join public.roles r on r.id = u.role_id
left join effective_permissions ep on ep.user_id = u.id
group by
  u.id,
  u.company_id,
  u.branch_id,
  u.name,
  u.email,
  u.username,
  u.role_id,
  r.role_name,
  u.is_active,
  u.created_at,
  u.updated_at,
  u.last_active;

drop view if exists public.v_products cascade;

create view public.v_products
with (security_invoker = true)
as
select
  p.id,
  p.company_id,
  i.branch_id,
  p.name,
  p.sku,
  p.category,
  p.purchase_price,
  p.sale_price,
  p.is_active,
  coalesce(i.stock, 0) as stock,
  coalesce(i.min_stock, 0) as min_stock
from public.products p
left join public.inventory i
  on i.product_id = p.id
 and i.company_id = p.company_id
where p.is_active = true;

drop view if exists public.v_order_summaries cascade;

create view public.v_order_summaries
with (security_invoker = true)
as
select
  o.id,
  o.company_id,
  o.branch_id,
  o.customer_name,
  o.customer_phone,
  o.order_date,
  o.order_notes,
  o.status,
  o.total_cost,
  o.total_revenue,
  o.profit,
  o.created_by,
  o.created_by_name,
  o.created_at,
  o.updated_at,
  count(oi.id) as line_count,
  coalesce(sum(oi.quantity), 0) as total_quantity
from public.orders o
left join public.order_items oi on oi.order_id = o.id
group by
  o.id,
  o.company_id,
  o.branch_id,
  o.customer_name,
  o.customer_phone,
  o.order_date,
  o.order_notes,
  o.status,
  o.total_cost,
  o.total_revenue,
  o.profit,
  o.created_by,
  o.created_by_name,
  o.created_at,
  o.updated_at;

comment on view public.v_order_summaries is
'Summary view for order lists, dashboard tiles, and server-side reporting.';

comment on column public.inventory.branch_id is
'Phase 1 tenant hardening column. The current inventory primary key remains product-scoped and should be normalized to a branch-scoped key for true multi-branch stock balances.';

create or replace function public.write_activity_log(
  p_actor_id uuid,
  p_action text,
  p_entity_type text,
  p_entity_id text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_name text;
  v_company_id uuid;
begin
  select name, company_id
  into v_actor_name, v_company_id
  from public.users
  where id = p_actor_id;

  insert into public.activity_logs (
    company_id,
    actor_id,
    user_id,
    actor_name,
    action,
    entity_type,
    entity_id,
    metadata
  )
  values (
    coalesce(v_company_id, public.default_company_id()),
    p_actor_id,
    p_actor_id,
    coalesce(v_actor_name, 'Unknown User'),
    p_action,
    p_entity_type,
    p_entity_id,
    p_metadata
  );
end;
$$;

create or replace function public.notify_roles(
  p_role_names text[],
  p_title text,
  p_message text,
  p_reference_id text default null,
  p_type text default 'workflow'
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company_id uuid := coalesce(public.current_company_id(), public.default_company_id());
begin
  insert into public.notifications (company_id, user_id, title, message, type, reference_id)
  select
    coalesce(u.company_id, v_company_id),
    u.id,
    p_title,
    p_message,
    p_type,
    p_reference_id
  from public.users u
  join public.roles r on r.id = u.role_id
  where r.role_name = any(p_role_names)
    and u.is_active = true
    and u.company_id = v_company_id
    and u.id <> auth.uid();
end;
$$;

drop policy if exists "roles readable by authenticated users" on public.roles;
drop policy if exists "permissions readable by authenticated users" on public.permissions;
drop policy if exists "role permissions readable by authenticated users" on public.role_permissions;
drop policy if exists "companies visible to tenant users" on public.companies;
drop policy if exists "branches visible to tenant users" on public.branches;
drop policy if exists "users visible to self or permissioned staff" on public.users;
drop policy if exists "user permissions visible to self or permissioned staff" on public.user_permissions;
drop policy if exists "products visible to authorized staff" on public.products;
drop policy if exists "inventory visible to authorized staff" on public.inventory;
drop policy if exists "inventory transactions visible to inventory staff" on public.inventory_transactions;
drop policy if exists "orders visible to order staff" on public.orders;
drop policy if exists "order items visible to order staff" on public.order_items;
drop policy if exists "order history visible to order staff" on public.order_status_history;
drop policy if exists "returns visible to order staff" on public.returns;
drop policy if exists "return items visible to order staff" on public.return_items;
drop policy if exists "notifications visible to owners" on public.notifications;
drop policy if exists "notifications update by owner" on public.notifications;
drop policy if exists "activity logs visible to admins and audit staff" on public.activity_logs;
drop policy if exists activity_logs_own_select on public.activity_logs;
drop policy if exists activity_logs_own_insert on public.activity_logs;

alter table public.companies enable row level security;
alter table public.branches enable row level security;

create policy "companies visible to tenant users"
on public.companies
for select
to authenticated
using (
  public.current_user_is_active()
  and id = public.current_company_id()
);

create policy "branches visible to tenant users"
on public.branches
for select
to authenticated
using (
  public.current_user_is_active()
  and company_id = public.current_company_id()
  and (
    id = public.current_branch_id()
    or public.is_admin()
  )
);

create policy "roles readable by authenticated users"
on public.roles
for select
to authenticated
using (public.current_user_is_active());

create policy "permissions readable by authenticated users"
on public.permissions
for select
to authenticated
using (public.current_user_is_active());

create policy "role permissions readable by authenticated users"
on public.role_permissions
for select
to authenticated
using (public.current_user_is_active());

create policy "users visible to self or permissioned staff"
on public.users
for select
to authenticated
using (
  public.current_user_is_active()
  and public.tenant_match(company_id)
  and (
    id = auth.uid()
    or public.has_permission('users_view')
    or public.is_admin()
  )
);

create policy "user permissions visible to self or permissioned staff"
on public.user_permissions
for select
to authenticated
using (
  public.current_user_is_active()
  and exists (
    select 1
    from public.users u
    where u.id = user_permissions.user_id
      and public.tenant_match(u.company_id)
      and (
        u.id = auth.uid()
        or public.has_permission('users_view')
        or public.is_admin()
      )
  )
);

create policy "products visible to authorized staff"
on public.products
for select
to authenticated
using (
  public.current_user_is_active()
  and public.tenant_match(company_id)
  and is_active = true
  and (
    public.has_permission('products_view')
    or public.has_permission('inventory_view')
    or public.has_permission('orders_create')
    or public.has_permission('orders_view')
    or public.is_admin()
  )
);

create policy "inventory visible to authorized staff"
on public.inventory
for select
to authenticated
using (
  public.current_user_is_active()
  and public.tenant_match(company_id)
  and public.branch_match(branch_id)
  and (
    public.has_permission('inventory_view')
    or public.has_permission('products_view')
    or public.has_permission('orders_create')
    or public.has_permission('orders_view')
    or public.is_admin()
  )
);

create policy "inventory transactions visible to inventory staff"
on public.inventory_transactions
for select
to authenticated
using (
  public.current_user_is_active()
  and public.tenant_match(company_id)
  and public.branch_match(branch_id)
  and (
    public.has_permission('inventory_view')
    or public.is_admin()
  )
);

create policy "orders visible to order staff"
on public.orders
for select
to authenticated
using (
  public.current_user_is_active()
  and public.tenant_match(company_id)
  and public.branch_match(branch_id)
  and (
    public.has_permission('orders_view')
    or public.has_permission('orders_create')
    or public.has_permission('orders_approve')
    or public.has_permission('orders_ship')
    or public.has_permission('dashboard_view')
    or public.is_admin()
  )
);

create policy "order items visible to order staff"
on public.order_items
for select
to authenticated
using (
  exists (
    select 1
    from public.orders o
    where o.id = order_items.order_id
      and public.tenant_match(o.company_id)
      and public.branch_match(o.branch_id)
      and (
        public.has_permission('orders_view')
        or public.has_permission('orders_create')
        or public.has_permission('orders_approve')
        or public.has_permission('orders_ship')
        or public.has_permission('dashboard_view')
        or public.is_admin()
      )
  )
);

create policy "order history visible to order staff"
on public.order_status_history
for select
to authenticated
using (
  exists (
    select 1
    from public.orders o
    where o.id = order_status_history.order_id
      and public.tenant_match(o.company_id)
      and public.branch_match(o.branch_id)
      and (
        public.has_permission('orders_view')
        or public.has_permission('orders_create')
        or public.has_permission('orders_approve')
        or public.has_permission('orders_ship')
        or public.has_permission('dashboard_view')
        or public.is_admin()
      )
  )
);

create policy "returns visible to order staff"
on public.returns
for select
to authenticated
using (
  public.current_user_is_active()
  and public.tenant_match(company_id)
  and public.branch_match(branch_id)
  and (
    public.has_permission('orders_view')
    or public.has_permission('orders_ship')
    or public.is_admin()
  )
);

create policy "return items visible to order staff"
on public.return_items
for select
to authenticated
using (
  exists (
    select 1
    from public.returns r
    where r.id = return_items.return_id
      and public.tenant_match(r.company_id)
      and public.branch_match(r.branch_id)
      and (
        public.has_permission('orders_view')
        or public.has_permission('orders_ship')
        or public.is_admin()
      )
  )
);

create policy "notifications visible to owners"
on public.notifications
for select
to authenticated
using (
  public.current_user_is_active()
  and public.tenant_match(company_id)
  and (
    user_id = auth.uid()
    or public.is_admin()
  )
);

create policy "notifications update by owner"
on public.notifications
for update
to authenticated
using (
  public.current_user_is_active()
  and public.tenant_match(company_id)
  and user_id = auth.uid()
)
with check (
  public.tenant_match(company_id)
  and user_id = auth.uid()
);

create policy "activity logs visible to admins and audit staff"
on public.activity_logs
for select
to authenticated
using (
  public.current_user_is_active()
  and public.tenant_match(company_id)
  and (
    user_id = auth.uid()
    or public.has_permission('activity_logs_view')
    or public.is_admin()
  )
);

grant execute on function public.default_company_id() to authenticated;
grant execute on function public.default_branch_id() to authenticated;
grant execute on function public.current_company_id() to authenticated;
grant execute on function public.current_branch_id() to authenticated;
grant execute on function public.current_role_name() to authenticated;
grant execute on function public.current_user_is_active() to authenticated;
grant execute on function public.current_user_permissions() to authenticated;
grant execute on function public.has_permission(text) to authenticated;
grant execute on function public.is_admin() to authenticated;
