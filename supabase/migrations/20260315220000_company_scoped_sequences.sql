-- Company-scoped numbering for orders and products
-- Ensures each company has its own independent sequence for order_no and product_no.

begin;

-- ---------------------------------------------------------------------------
-- Shared counter table and helpers
-- ---------------------------------------------------------------------------
create table if not exists public.company_counters (
  company_id uuid primary key,
  next_order_no bigint not null default 1,
  next_product_no bigint not null default 1,
  updated_at timestamptz not null default now()
);

comment on table public.company_counters is
  'Maintains per-company counters for order_no and product_no sequences.';

create or replace function public.next_order_no(p_company_id uuid default null)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  cid uuid := coalesce(p_company_id, public.current_company_id());
  v_next bigint;
begin
  if cid is null then
    raise exception 'company_required';
  end if;

  insert into public.company_counters (company_id)
  values (cid)
  on conflict (company_id) do nothing;

  update public.company_counters
  set next_order_no = next_order_no + 1,
      updated_at = now()
  where company_id = cid
  returning next_order_no - 1 into v_next;

  return v_next;
end;
$$;

create or replace function public.next_product_no(p_company_id uuid default null)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  cid uuid := coalesce(p_company_id, public.current_company_id());
  v_next bigint;
begin
  if cid is null then
    raise exception 'company_required';
  end if;

  insert into public.company_counters (company_id)
  values (cid)
  on conflict (company_id) do nothing;

  update public.company_counters
  set next_product_no = next_product_no + 1,
      updated_at = now()
  where company_id = cid
  returning next_product_no - 1 into v_next;

  return v_next;
end;
$$;

grant execute on function public.next_order_no(uuid) to authenticated;
grant execute on function public.next_product_no(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Orders: add company-scoped order_no, backfill, and trigger
-- ---------------------------------------------------------------------------
do $orders$
begin
  if to_regclass('public.orders') is null then
    return;
  end if;

  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'orders'
      and column_name = 'order_no'
  ) then
    execute 'alter table public.orders add column order_no bigint';
  end if;

  -- Backfill missing order_no values per company (deterministic order by id)
  with numbered as (
    select id, row_number() over (partition by company_id order by id) as rn
    from public.orders
    where order_no is null
  )
  update public.orders o
  set order_no = n.rn
  from numbered n
  where o.id = n.id;

  -- Unique within a company
  if not exists (
    select 1 from pg_indexes
    where schemaname = 'public'
      and indexname = 'orders_company_order_no_key'
  ) then
    execute 'create unique index orders_company_order_no_key on public.orders (company_id, order_no)';
  end if;

  -- Trigger to set order_no on insert
  execute $fn$
    create or replace function public.trg_set_order_no()
    returns trigger
    language plpgsql
    security definer
    set search_path = public
    as $$
    begin
      if new.order_no is null then
        new.order_no := public.next_order_no(coalesce(new.company_id, public.current_company_id()));
      end if;
      return new;
    end;
    $$;
  $fn$;

  if exists (
    select 1
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'orders'
      and t.tgname = 'set_order_no'
  ) then
    execute 'drop trigger set_order_no on public.orders';
  end if;

  execute 'create trigger set_order_no before insert on public.orders for each row execute function public.trg_set_order_no()';
end;
$orders$;

-- ---------------------------------------------------------------------------
-- Products: add company-scoped product_no, backfill, and trigger
-- ---------------------------------------------------------------------------
do $products$
begin
  if to_regclass('public.products') is null then
    return;
  end if;

  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'products'
      and column_name = 'product_no'
  ) then
    execute 'alter table public.products add column product_no bigint';
  end if;

  with numbered as (
    select id, row_number() over (partition by company_id order by id) as rn
    from public.products
    where product_no is null
  )
  update public.products p
  set product_no = n.rn
  from numbered n
  where p.id = n.id;

  if not exists (
    select 1 from pg_indexes
    where schemaname = 'public'
      and indexname = 'products_company_product_no_key'
  ) then
    execute 'create unique index products_company_product_no_key on public.products (company_id, product_no)';
  end if;

  execute $fn$
    create or replace function public.trg_set_product_no()
    returns trigger
    language plpgsql
    security definer
    set search_path = public
    as $$
    begin
      if new.product_no is null then
        new.product_no := public.next_product_no(coalesce(new.company_id, public.current_company_id()));
      end if;
      return new;
    end;
    $$;
  $fn$;

  if exists (
    select 1
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'products'
      and t.tgname = 'set_product_no'
  ) then
    execute 'drop trigger set_product_no on public.products';
  end if;

  execute 'create trigger set_product_no before insert on public.products for each row execute function public.trg_set_product_no()';
end;
$products$;

-- ---------------------------------------------------------------------------
-- Align counters with current data
-- ---------------------------------------------------------------------------
do $counters$
begin
  if to_regclass('public.company_counters') is null then
    return;
  end if;

  if to_regclass('public.orders') is not null then
    insert into public.company_counters (company_id, next_order_no)
    select company_id, coalesce(max(order_no) + 1, 1)
    from public.orders
    group by company_id
    on conflict (company_id) do update
    set next_order_no = greatest(excluded.next_order_no, public.company_counters.next_order_no),
        updated_at = now();
  end if;

  if to_regclass('public.products') is not null then
    insert into public.company_counters (company_id, next_product_no)
    select company_id, coalesce(max(product_no) + 1, 1)
    from public.products
    group by company_id
    on conflict (company_id) do update
    set next_product_no = greatest(excluded.next_product_no, public.company_counters.next_product_no),
        updated_at = now();
  end if;
end;
$counters$;

notify pgrst, 'reload schema';

commit;
