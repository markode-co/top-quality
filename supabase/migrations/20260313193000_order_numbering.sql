-- Sequential order numbering

-- 1) Add column
alter table public.orders
  add column if not exists order_no bigint;

-- 2) Backfill existing rows with deterministic sequence by created_at then id
with numbered as (
  select id, row_number() over (order by created_at, id) as rn
  from public.orders
)
update public.orders o
set order_no = n.rn
from numbered n
where o.id = n.id and o.order_no is null;

-- 3) Create sequence and default for new rows
create sequence if not exists public.orders_order_no_seq;
select setval('public.orders_order_no_seq',
              coalesce((select max(order_no) from public.orders), 0));

alter table public.orders
  alter column order_no set default nextval('public.orders_order_no_seq'),
  alter column order_no set not null;

-- 4) Uniqueness
create unique index if not exists idx_orders_order_no_unique
  on public.orders(order_no);

-- 5) Update view if any (v_orders not present); views selecting * will now include order_no.

-- 6) Ensure extension (already added elsewhere, harmless if exists)
create extension if not exists "pgcrypto";
