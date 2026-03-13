-- Fan-out notifications to all active users in the same company, and
-- make v_activity_logs independent from public.users to avoid 403/42501 issues.

-- ---------------------------
-- Notifications
-- ---------------------------

alter table if exists public.notifications
  add column if not exists company_id uuid references public.companies(id) on delete set null;

create index if not exists idx_notifications_company on public.notifications(company_id);

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
declare
  v_company_id uuid;
begin
  select company_id into v_company_id from public.users where id = p_user_id;

  insert into public.notifications(user_id, company_id, title, message, type, reference_id)
  values (
    p_user_id,
    v_company_id,
    p_title,
    p_message,
    coalesce(p_type, 'workflow'),
    p_reference_id
  );
end;
$$;
grant execute on function public.notify_user(uuid,text,text,text,text) to authenticated;

create or replace function public.notify_company_users(
  p_company_id uuid,
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
  insert into public.notifications(user_id, company_id, title, message, type, reference_id)
  select
    u.id,
    p_company_id,
    p_title,
    p_message,
    coalesce(p_type, 'workflow'),
    p_reference_id
  from public.users u
  where u.company_id = p_company_id
    and u.is_active = true;
end;
$$;
grant execute on function public.notify_company_users(uuid,text,text,text,text) to authenticated;

-- ---------------------------
-- Activity log writer: include actor identity in metadata
-- ---------------------------

create or replace function public.current_company_id()
returns uuid
language plpgsql
security definer
stable
set search_path = public
as $$
declare cid uuid;
begin
  select company_id into cid from public.users where id = auth.uid();
  return cid;
end;
$$;
grant execute on function public.current_company_id() to authenticated;

create or replace function public.has_permission(p_code text)
returns boolean
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_role_id uuid;
begin
  if v_uid is null then
    return false;
  end if;

  if public.is_admin() then
    return true;
  end if;

  select role_id into v_role_id from public.users where id = v_uid;

  if exists (
    select 1 from public.user_permissions up
    where up.user_id = v_uid and up.permission_code = p_code
  ) then
    return true;
  end if;

  if v_role_id is not null and exists (
    select 1 from public.role_permissions rp
    where rp.role_id = v_role_id and rp.permission_code = p_code
  ) then
    return true;
  end if;

  return false;
end;
$$;
grant execute on function public.has_permission(text) to authenticated;

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
declare
  v_company uuid;
  v_actor_name text;
  v_actor_email text;
  v_meta jsonb := coalesce(p_metadata, '{}'::jsonb);
begin
  select company_id, name, email
  into v_company, v_actor_name, v_actor_email
  from public.users
  where id = p_actor_id
  limit 1;

  -- Denormalize actor identity into the JSON metadata so views/clients don't need to join users/auth.users.
  v_meta := v_meta
    || jsonb_build_object(
      'actor_name', v_actor_name,
      'actor_email', v_actor_email
    );

  insert into public.activity_logs(actor_id, action, entity_type, entity_id, metadata, company_id)
  values (p_actor_id, p_action, p_entity_type, p_entity_id, jsonb_strip_nulls(v_meta), v_company);
end;
$$;
grant execute on function public.write_activity_log(uuid,text,text,uuid,jsonb) to authenticated;

-- Avoid referencing public.users directly in RLS policies (can cause 403/42501 and recursion).
drop policy if exists "activity_logs_company_view" on public.activity_logs;
create policy "activity_logs_company_view"
on public.activity_logs for select
to authenticated
using (
  auth.uid() is not null
  and (
    public.is_admin()
    or (
      (activity_logs.company_id is null or activity_logs.company_id = public.current_company_id())
      and public.has_permission('activity_logs_view')
    )
  )
);

-- ---------------------------
-- Activity logs view (no joins to users/auth.users)
-- ---------------------------

drop view if exists public.v_activity_logs;

create view public.v_activity_logs as
select
  l.id,
  case
    when l.actor_id = '00000000-0000-0000-0000-000000000000' then null
    else l.actor_id
  end as actor_id,
  coalesce(
    l.metadata->>'actor_name',
    l.metadata->>'actor_email',
    l.actor_id::text,
    'System'
  ) as actor_name,
  nullif(l.metadata->>'actor_email', '') as actor_email,
  l.action,
  l.entity_type,
  l.entity_id,
  l.metadata,
  l.company_id,
  l.created_at
from public.activity_logs l
where l.action not like 'smoke_test%';

grant select on public.v_activity_logs to authenticated;

-- ---------------------------
-- Redefine core RPCs to emit notifications to everyone + write activity logs
-- ---------------------------

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
    v_order_id, v_user.company_id, v_user.branch_id,
    p_customer_name, p_customer_phone, p_customer_address,
    p_order_notes, v_user.id, v_user.name
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

  perform public.notify_company_users(
    v_user.company_id,
    'تم إنشاء طلب',
    format('تم إنشاء الطلب رقم %s بواسطة %s', coalesce(v_order_no::text, '-'), v_user.name),
    'workflow',
    v_order_id::text
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
  v_order_no bigint;
begin
  select id, company_id, branch_id, name into v_user from public.users where id = auth.uid();
  if v_user.id is null then raise exception 'user_not_found'; end if;

  select order_no, status into v_order_no, v_status from public.orders where id = p_order_id;
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

  perform public.write_activity_log(
    v_user.id,
    'update_order',
    'order',
    p_order_id,
    jsonb_build_object(
      'customer_name', p_customer_name,
      'items', coalesce(jsonb_array_length(p_items), 0),
      'previous_status', v_status,
      'note', p_order_notes
    )
  );

  perform public.notify_company_users(
    v_user.company_id,
    'تم تعديل طلب',
    format('تم تعديل الطلب رقم %s بواسطة %s', coalesce(v_order_no::text, '-'), v_user.name),
    'workflow',
    p_order_id::text
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
  v_order_no bigint;
begin
  select id, company_id, name into v_user from public.users where id = auth.uid();
  if v_user.id is null then raise exception 'user_not_found'; end if;

  select order_no into v_order_no from public.orders where id = p_order_id;

  delete from public.orders where id = p_order_id;

  perform public.write_activity_log(
    v_user.id,
    'delete_order',
    'order',
    p_order_id,
    jsonb_build_object('note', 'order deleted')
  );

  perform public.notify_company_users(
    v_user.company_id,
    'تم حذف طلب',
    format('تم حذف الطلب رقم %s بواسطة %s', coalesce(v_order_no::text, '-'), v_user.name),
    'workflow',
    p_order_id::text
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
  v_order_no bigint;
  v_next_label text;
begin
  select id, company_id, name into v_user from public.users where id = auth.uid();
  if v_user.id is null then raise exception 'user_not_found'; end if;

  select order_no, status into v_order_no, v_prev_status from public.orders where id = p_order_id;

  v_next_label := case lower(p_next_status)
    when 'entered' then 'إدخال'
    when 'checked' then 'مراجعة'
    when 'approved' then 'اعتماد'
    when 'shipped' then 'شحن'
    when 'completed' then 'مكتمل'
    when 'returned' then 'مرتجع'
    else p_next_status
  end;

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

  perform public.notify_company_users(
    v_user.company_id,
    'تغيير حالة الطلب',
    format('الطلب رقم %s أصبح %s (بواسطة %s)', coalesce(v_order_no::text, '-'), v_next_label, v_user.name),
    'workflow',
    p_order_id::text
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
  v_order_no bigint;
  v_next_label text;
begin
  select id, company_id, name into v_user from public.users where id = auth.uid();
  if v_user.id is null then raise exception 'user_not_found'; end if;

  select order_no, status into v_order_no, v_prev_status from public.orders where id = p_order_id;

  v_next_label := case lower(p_next_status)
    when 'entered' then 'إدخال'
    when 'checked' then 'مراجعة'
    when 'approved' then 'اعتماد'
    when 'shipped' then 'شحن'
    when 'completed' then 'مكتمل'
    when 'returned' then 'مرتجع'
    else p_next_status
  end;

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

  perform public.notify_company_users(
    v_user.company_id,
    'تجاوز حالة الطلب',
    format('تم تجاوز حالة الطلب رقم %s إلى %s (بواسطة %s)', coalesce(v_order_no::text, '-'), v_next_label, v_user.name),
    'workflow',
    p_order_id::text
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
  v_is_new boolean := p_product_id is null;
begin
  select id, company_id, branch_id, name into v_user from public.users where id = auth.uid();
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

  perform public.notify_company_users(
    v_user.company_id,
    case when v_is_new then 'تم إضافة منتج' else 'تم تحديث منتج' end,
    format('%s (بواسطة %s)', p_name, v_user.name),
    'alert',
    v_id::text
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
  v_name text;
  v_sku text;
begin
  select id, company_id, name into v_user from public.users where id = auth.uid();
  if v_user.id is null then raise exception 'user_not_found'; end if;

  select name, sku into v_name, v_sku from public.products where id = p_product_id;

  delete from public.products where id = p_product_id;

  perform public.write_activity_log(
    v_user.id,
    'delete_product',
    'product',
    p_product_id,
    jsonb_build_object('sku', v_sku, 'name', v_name)
  );

  perform public.notify_company_users(
    v_user.company_id,
    'تم حذف منتج',
    format('%s (بواسطة %s)', coalesce(v_name, p_product_id::text), v_user.name),
    'alert',
    p_product_id::text
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
  v_name text;
  v_sku text;
begin
  select id, company_id, name into v_user from public.users where id = auth.uid();
  if v_user.id is null then raise exception 'user_not_found'; end if;

  select name, sku into v_name, v_sku from public.products where id = p_product_id;

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
    jsonb_build_object('delta', p_quantity_delta, 'reason', p_reason, 'sku', v_sku, 'name', v_name)
  );

  perform public.notify_company_users(
    v_user.company_id,
    'تعديل المخزون',
    format('%s (%s) %s (بواسطة %s)', coalesce(v_name, p_product_id::text), coalesce(v_sku, '-'), p_quantity_delta::text, v_user.name),
    'alert',
    p_product_id::text
  );
end;
$$;
grant execute on function public.adjust_inventory(uuid, integer, text) to authenticated;

-- Ensure PostgREST picks up updated definitions.
notify pgrst, 'reload schema';
