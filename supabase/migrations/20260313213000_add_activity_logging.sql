-- Add server-side activity logging for core business actions
-- This migration redefines the RPC functions to emit audit rows via write_activity_log
-- and ensures login activity is captured.

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

  perform public.write_activity_log(
    v_user.id,
    'create_order',
    'order',
    v_order_id,
    jsonb_build_object(
      'customer_name', p_customer_name,
      'items', coalesce(jsonb_array_length(p_items), 0)
    )
  );

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

  perform public.write_activity_log(
    v_user.id,
    'update_order',
    'order',
    p_order_id,
    jsonb_build_object(
      'previous_status', v_status,
      'note', p_order_notes
    )
  );
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
declare
  v_user record;
begin
  select id, name into v_user from public.users where id = auth.uid();
  if v_user.id is null then raise exception 'user_not_found'; end if;

  delete from public.orders where id = p_order_id;

  perform public.write_activity_log(
    v_user.id,
    'delete_order',
    'order',
    p_order_id,
    jsonb_build_object('note', 'order deleted')
  );
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
declare
  v_user record;
  v_prev_status public.order_status_enum;
begin
  select id, name into v_user from public.users where id = auth.uid();
  if v_user.id is null then raise exception 'user_not_found'; end if;

  select status into v_prev_status from public.orders where id = p_order_id;

  update public.orders
  set status = p_next_status::public.order_status_enum,
      updated_at = now()
  where id = p_order_id;

  insert into public.order_status_history(order_id, status, changed_by, changed_by_name, note)
  values (p_order_id, p_next_status::public.order_status_enum, v_user.id, v_user.name, p_note);

  perform public.write_activity_log(
    v_user.id,
    'transition_order',
    'order',
    p_order_id,
    jsonb_build_object(
      'from', v_prev_status,
      'to', p_next_status,
      'note', p_note
    )
  );
end;
$$;
grant execute on function public.transition_order(uuid,text,text) to authenticated;

-- Override order status (separate action for audit trail)
create or replace function public.override_order_status(
  p_order_id uuid,
  p_next_status text,
  p_note text default null
) returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_user record;
  v_prev_status public.order_status_enum;
begin
  select id, name into v_user from public.users where id = auth.uid();
  if v_user.id is null then raise exception 'user_not_found'; end if;

  select status into v_prev_status from public.orders where id = p_order_id;

  update public.orders
  set status = p_next_status::public.order_status_enum,
      updated_at = now()
  where id = p_order_id;

  insert into public.order_status_history(order_id, status, changed_by, changed_by_name, note)
  values (p_order_id, p_next_status::public.order_status_enum, v_user.id, v_user.name, p_note);

  perform public.write_activity_log(
    v_user.id,
    'override_order_status',
    'order',
    p_order_id,
    jsonb_build_object(
      'from', v_prev_status,
      'to', p_next_status,
      'note', p_note
    )
  );
end;
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

  perform public.write_activity_log(
    v_user.id,
    'upsert_product',
    'product',
    v_id,
    jsonb_build_object('sku', p_sku, 'name', p_name)
  );

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

-- Delete product
create or replace function public.delete_product(p_product_id uuid)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_user record;
begin
  select id, name into v_user from public.users where id = auth.uid();
  if v_user.id is null then raise exception 'user_not_found'; end if;

  delete from public.products where id = p_product_id;

  perform public.write_activity_log(
    v_user.id,
    'delete_product',
    'product',
    p_product_id,
    jsonb_build_object('note', 'product deleted')
  );
end;
$$;
grant execute on function public.delete_product(uuid) to authenticated;

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

  perform public.write_activity_log(
    v_user.id,
    'adjust_inventory',
    'inventory',
    p_product_id,
    jsonb_build_object('delta', p_quantity_delta, 'reason', p_reason)
  );
end;
$$;
grant execute on function public.adjust_inventory(uuid, integer, text) to authenticated;

-- Record user login (add audit log)
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

  perform public.write_activity_log(
    p_user_id,
    'login',
    'user',
    p_user_id,
    jsonb_build_object('event', 'login')
  );

  return json_build_object('status', 'ok');
end;
$$;
grant execute on function public.record_user_login(uuid) to authenticated;
