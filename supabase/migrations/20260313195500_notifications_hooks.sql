-- Helper to write notifications
create or replace function public.notify_user(
  p_user_id uuid,
  p_title text,
  p_message text,
  p_type text default 'workflow',
  p_reference_id text default null
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.notifications(user_id, title, message, type, reference_id)
  values (p_user_id, p_title, p_message, coalesce(p_type, 'workflow'), p_reference_id);
end;
$$;
grant execute on function public.notify_user(uuid,text,text,text,text) to authenticated;

-- Recreate create_order to emit notification
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
  v_order_no bigint;
begin
  select id, company_id, branch_id, name into v_user from public.users where id = auth.uid();
  if v_user.id is null then raise exception 'user_not_found'; end if;

  insert into public.orders(
    id, company_id, branch_id,
    customer_name, customer_phone, customer_address,
    order_notes, created_by, created_by_name
  )
  values (
    v_order_id, v_user.company_id, v_user.branch_id, p_customer_name, p_customer_phone,
    p_customer_address, p_order_notes, v_user.id, v_user.name
  )
  returning order_no into v_order_no;

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

  perform public.notify_user(
    v_user.id,
    'تم إنشاء طلب',
    coalesce('طلب رقم ' || v_order_no, 'طلب جديد'),
    'workflow',
    v_order_id::text
  );

  return v_order_id;
end;
$$;
grant execute on function public.create_order(text,text,jsonb,text,text) to authenticated;

-- Transition order status notification
create or replace function public.transition_order(
  p_order_id uuid,
  p_next_status text,
  p_note text default null
) returns void
language plpgsql security definer
set search_path = public
as $$
declare v_user record;
        v_order_no bigint;
begin
  select id, name into v_user from public.users where id = auth.uid();
  if v_user.id is null then raise exception 'user_not_found'; end if;

  update public.orders
  set status = p_next_status::public.order_status_enum,
      updated_at = now()
  where id = p_order_id
  returning order_no into v_order_no;

  insert into public.order_status_history(order_id, status, changed_by, changed_by_name, note)
  values (p_order_id, p_next_status::public.order_status_enum, v_user.id, v_user.name, p_note);

  perform public.notify_user(
    v_user.id,
    'تغيير حالة الطلب',
    format('طلب رقم %s أصبح %s', coalesce(v_order_no::text,'-'), p_next_status),
    'workflow',
    p_order_id::text
  );
end;
$$;
grant execute on function public.transition_order(uuid,text,text) to authenticated;

-- Override order status notification
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

-- Upsert product notification (fires on create or update)
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
  v_is_new boolean := p_product_id is null;
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

  perform public.notify_user(
    v_user.id,
    case when v_is_new then 'تم إضافة منتج' else 'تم تحديث منتج' end,
    p_name,
    'alert',
    v_id::text
  );

  return v_id;
end;
$$;
grant execute on function public.upsert_product(uuid,text,text,text,numeric,numeric,int,int) to authenticated;

-- Wrapper preserved
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
