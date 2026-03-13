-- Fix update_order status logging to use the order's current status (enum-safe)
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
  select id, company_id, branch_id, name
  into v_user
  from public.users
  where id = auth.uid();

  if v_user.id is null then
    raise exception 'user_not_found';
  end if;

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
