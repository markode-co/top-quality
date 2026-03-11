-- Add customer_address to orders + wire into create/update functions

alter table public.orders
  add column if not exists customer_address text;

-- create_order: add p_customer_address
drop function if exists public.create_order(text,text,jsonb,text);

create or replace function public.create_order(
  p_customer_name text,
  p_customer_phone text,
  p_items jsonb,
  p_order_notes text default null,
  p_customer_address text default null
) returns text
language plpgsql security definer
set search_path = public
as $$
declare
  v_order_id text := replace(gen_random_uuid()::text, '-', '');
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

-- update_order: add p_customer_address
drop function if exists public.update_order(text,text,text,jsonb,text);

create or replace function public.update_order(
  p_order_id text,
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
begin
  select id, company_id, branch_id, name into v_user from public.users where id = auth.uid();
  if v_user.id is null then raise exception 'user_not_found'; end if;

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
  values (p_order_id, 'updated', v_user.id, v_user.name, p_order_notes);
end;
$$;

-- Refresh PostgREST cache
notify pgrst, 'reload schema';
