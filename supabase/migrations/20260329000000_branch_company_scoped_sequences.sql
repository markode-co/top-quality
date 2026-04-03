-- Branch-aware numbering for orders and products
-- Ensures each branch and each company has its own independent sequence for order_no and product_no.

begin;

create table if not exists public.branch_counters (
  company_id uuid not null,
  branch_id uuid not null,
  next_order_no bigint not null default 1,
  next_product_no bigint not null default 1,
  updated_at timestamptz not null default now(),
  primary key (company_id, branch_id)
);

comment on table public.branch_counters is
  'Maintains per-company-per-branch counters for order_no and product_no sequences.';

create or replace function public.next_order_no(
  p_company_id uuid default null,
  p_branch_id uuid default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  cid uuid := coalesce(p_company_id, public.current_company_id());
  bid uuid := p_branch_id;
  v_next bigint;
begin
  if cid is null then
    raise exception 'company_required';
  end if;

  if bid is null then
    return public.next_order_no(cid);
  end if;

  insert into public.branch_counters (company_id, branch_id)
  values (cid, bid)
  on conflict (company_id, branch_id) do nothing;

  update public.branch_counters
  set next_order_no = next_order_no + 1,
      updated_at = now()
  where company_id = cid
    and branch_id = bid
  returning next_order_no - 1 into v_next;

  return v_next;
end;
$$;

grant execute on function public.next_order_no(uuid, uuid) to authenticated;

create or replace function public.next_product_no(
  p_company_id uuid default null,
  p_branch_id uuid default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  cid uuid := coalesce(p_company_id, public.current_company_id());
  bid uuid := p_branch_id;
  v_next bigint;
begin
  if cid is null then
    raise exception 'company_required';
  end if;

  if bid is null then
    return public.next_product_no(cid);
  end if;

  insert into public.branch_counters (company_id, branch_id)
  values (cid, bid)
  on conflict (company_id, branch_id) do nothing;

  update public.branch_counters
  set next_product_no = next_product_no + 1,
      updated_at = now()
  where company_id = cid
    and branch_id = bid
  returning next_product_no - 1 into v_next;

  return v_next;
end;
$$;

grant execute on function public.next_product_no(uuid, uuid) to authenticated;

-- Orders: adapt numbering to branch-aware sequences when branch_id exists.
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

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'orders'
      and column_name = 'branch_id'
  ) then
    with numbered as (
      select id,
             row_number() over (partition by company_id, branch_id order by id) as rn
      from public.orders
      where order_no is null
    )
    update public.orders o
    set order_no = n.rn
    from numbered n
    where o.id = n.id;

    execute 'drop index if exists orders_company_order_no_key';
    execute 'create unique index if not exists orders_company_order_no_key on public.orders (company_id, order_no) where branch_id is null';
    execute 'create unique index if not exists orders_company_branch_order_no_key on public.orders (company_id, branch_id, order_no) where branch_id is not null';

    execute $fn$
      create or replace function public.trg_set_order_no()
      returns trigger
      language plpgsql
      security definer
      set search_path = public
      as $$
      begin
        if new.order_no is null then
          if new.branch_id is null then
            new.order_no := public.next_order_no(coalesce(new.company_id, public.current_company_id()));
          else
            new.order_no := public.next_order_no(coalesce(new.company_id, public.current_company_id()), new.branch_id);
          end if;
        end if;
        return new;
      end;
      $$;
    $fn$;

    execute 'drop trigger if exists set_order_no on public.orders';
    execute 'create trigger set_order_no before insert on public.orders for each row execute function public.trg_set_order_no()';
  end if;
end;
$orders$;

-- Products: adapt numbering to branch-aware sequences when branch_id exists.
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

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'products'
      and column_name = 'branch_id'
  ) then
    with numbered as (
      select id,
             row_number() over (partition by company_id, branch_id order by id) as rn
      from public.products
      where product_no is null
    )
    update public.products p
    set product_no = n.rn
    from numbered n
    where p.id = n.id;

    execute 'drop index if exists products_company_product_no_key';
    execute 'create unique index if not exists products_company_product_no_key on public.products (company_id, product_no) where branch_id is null';
    execute 'create unique index if not exists products_company_branch_product_no_key on public.products (company_id, branch_id, product_no) where branch_id is not null';

    execute $fn$
      create or replace function public.trg_set_product_no()
      returns trigger
      language plpgsql
      security definer
      set search_path = public
      as $$
      begin
        if new.product_no is null then
          if new.branch_id is null then
            new.product_no := public.next_product_no(coalesce(new.company_id, public.current_company_id()));
          else
            new.product_no := public.next_product_no(coalesce(new.company_id, public.current_company_id()), new.branch_id);
          end if;
        end if;
        return new;
      end;
      $$;
    $fn$;

    execute 'drop trigger if exists set_product_no on public.products';
    execute 'create trigger set_product_no before insert on public.products for each row execute function public.trg_set_product_no()';
  end if;
end;
$products$;

-- Align branch counters with current row data.
do $counters$
begin
  if to_regclass('public.branch_counters') is null then
    return;
  end if;

  if to_regclass('public.orders') is not null
  and exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'orders'
      and column_name = 'branch_id'
  ) then
    insert into public.branch_counters (company_id, branch_id, next_order_no)
    select company_id,
           branch_id,
           coalesce(max(order_no) + 1, 1)
    from public.orders
    where branch_id is not null
    group by company_id, branch_id
    on conflict (company_id, branch_id) do update
    set next_order_no = greatest(excluded.next_order_no, public.branch_counters.next_order_no),
        updated_at = now();
  end if;

  if to_regclass('public.products') is not null
  and exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'products'
      and column_name = 'branch_id'
  ) then
    insert into public.branch_counters (company_id, branch_id, next_product_no)
    select company_id,
           branch_id,
           coalesce(max(product_no) + 1, 1)
    from public.products
    where branch_id is not null
    group by company_id, branch_id
    on conflict (company_id, branch_id) do update
    set next_product_no = greatest(excluded.next_product_no, public.branch_counters.next_product_no),
        updated_at = now();
  end if;
end;
$counters$;

notify pgrst, 'reload schema';

commit;
