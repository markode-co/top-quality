create or replace function public.resolve_role_name(p_role_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_role_name text;
begin
  if p_role_id is null then
    return null;
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'roles'
      and column_name = 'role_name'
  ) then
    execute 'select role_name from public.roles where id = $1'
      into v_role_name
      using p_role_id;
  elsif exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'roles'
      and column_name = 'name'
  ) then
    execute 'select name from public.roles where id = $1'
      into v_role_name
      using p_role_id;
  elsif exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'roles'
      and column_name = 'title'
  ) then
    execute 'select title from public.roles where id = $1'
      into v_role_name
      using p_role_id;
  elsif exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'roles'
      and column_name = 'label'
  ) then
    execute 'select label from public.roles where id = $1'
      into v_role_name
      using p_role_id;
  end if;

  return v_role_name;
end;
$$;

create or replace function public.resolve_permission_code(p_permission_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_permission_code text;
  v_permission_column text;
begin
  if p_permission_id is null then
    return null;
  end if;

  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'permissions'
      and column_name = 'id'
  ) then
    return null;
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'permissions'
      and column_name = 'code'
  ) then
    v_permission_column := 'code';
  elsif exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'permissions'
      and column_name = 'permission_code'
  ) then
    v_permission_column := 'permission_code';
  elsif exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'permissions'
      and column_name = 'name'
  ) then
    v_permission_column := 'name';
  else
    return null;
  end if;

  execute format(
    'select %1$I from public.permissions where id = $1',
    v_permission_column
  )
    into v_permission_code
    using p_permission_id;

  return v_permission_code;
end;
$$;

create or replace function public.user_effective_permissions(
  p_user_id uuid,
  p_role_id uuid default null
)
returns text[]
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_role_id uuid := p_role_id;
  v_permission_column text;
  v_direct_permissions text[] := '{}'::text[];
  v_role_permissions text[] := '{}'::text[];
begin
  if p_user_id is null then
    return '{}'::text[];
  end if;

  if v_role_id is null then
    select role_id into v_role_id
    from public.users
    where id = p_user_id;
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'permissions'
      and column_name = 'code'
  ) then
    v_permission_column := 'code';
  elsif exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'permissions'
      and column_name = 'permission_code'
  ) then
    v_permission_column := 'permission_code';
  elsif exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'permissions'
      and column_name = 'name'
  ) then
    v_permission_column := 'name';
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'user_permissions'
      and column_name = 'permission_code'
  ) then
    execute $sql$
      select coalesce(
        array_agg(distinct up.permission_code order by up.permission_code),
        '{}'::text[]
      )
      from public.user_permissions up
      where up.user_id = $1
    $sql$
      into v_direct_permissions
      using p_user_id;
  elsif v_permission_column is not null
    and exists (
      select 1
      from information_schema.columns
      where table_schema = 'public'
        and table_name = 'user_permissions'
        and column_name = 'permission_id'
    )
    and exists (
      select 1
      from information_schema.columns
      where table_schema = 'public'
        and table_name = 'permissions'
        and column_name = 'id'
    )
  then
    execute format(
      'select coalesce(
         array_agg(distinct p.%1$I order by p.%1$I),
         ''{}''::text[]
       )
       from public.user_permissions up
       join public.permissions p on p.id = up.permission_id
       where up.user_id = $1',
      v_permission_column
    )
      into v_direct_permissions
      using p_user_id;
  end if;

  if v_role_id is not null then
    if exists (
      select 1
      from information_schema.columns
      where table_schema = 'public'
        and table_name = 'role_permissions'
        and column_name = 'permission_code'
    ) then
      execute $sql$
        select coalesce(
          array_agg(distinct rp.permission_code order by rp.permission_code),
          '{}'::text[]
        )
        from public.role_permissions rp
        where rp.role_id = $1
      $sql$
        into v_role_permissions
        using v_role_id;
    elsif v_permission_column is not null
      and exists (
        select 1
        from information_schema.columns
        where table_schema = 'public'
          and table_name = 'role_permissions'
          and column_name = 'permission_id'
      )
      and exists (
        select 1
        from information_schema.columns
        where table_schema = 'public'
          and table_name = 'permissions'
          and column_name = 'id'
      )
    then
      execute format(
        'select coalesce(
           array_agg(distinct p.%1$I order by p.%1$I),
           ''{}''::text[]
         )
         from public.role_permissions rp
         join public.permissions p on p.id = rp.permission_id
         where rp.role_id = $1',
        v_permission_column
      )
        into v_role_permissions
        using v_role_id;
    end if;
  end if;

  return coalesce(
    (
      select array_agg(distinct permission_code order by permission_code)
      from unnest(coalesce(v_direct_permissions, '{}'::text[]) || coalesce(v_role_permissions, '{}'::text[]))
        as permission_code
      where permission_code is not null
        and permission_code <> ''
    ),
    '{}'::text[]
  );
end;
$$;

do $$
declare
  v_relkind "char";
begin
  select c.relkind
  into v_relkind
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname = 'user_roles';

  if v_relkind = 'v' then
    execute 'drop view public.user_roles cascade';
  elsif v_relkind = 'm' then
    execute 'drop materialized view public.user_roles cascade';
  elsif v_relkind in ('r', 'p') then
    execute 'drop table public.user_roles cascade';
  elsif v_relkind = 'f' then
    execute 'drop foreign table public.user_roles cascade';
  end if;
end;
$$;

do $$
declare
  v_relkind "char";
begin
  select c.relkind
  into v_relkind
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname = 'v_users_with_permissions';

  if v_relkind = 'v' then
    execute 'drop view public.v_users_with_permissions cascade';
  elsif v_relkind = 'm' then
    execute 'drop materialized view public.v_users_with_permissions cascade';
  elsif v_relkind in ('r', 'p') then
    execute 'drop table public.v_users_with_permissions cascade';
  elsif v_relkind = 'f' then
    execute 'drop foreign table public.v_users_with_permissions cascade';
  end if;
end;
$$;

create or replace function public.current_role_name()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select public.resolve_role_name(u.role_id)
  from public.users u
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
  select unnest(public.user_effective_permissions(auth.uid(), null))
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

create view public.user_roles
with (security_invoker = true)
as
select
  u.id as user_id,
  u.company_id,
  u.branch_id,
  u.role_id,
  public.resolve_role_name(u.role_id) as role_name,
  u.is_active,
  u.created_at,
  u.updated_at
from public.users u;

create view public.v_users_with_permissions
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
  public.resolve_role_name(u.role_id) as role_name,
  u.is_active,
  u.created_at,
  u.updated_at,
  u.last_active,
  public.user_effective_permissions(u.id, u.role_id) as permissions
from public.users u;

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
  where public.resolve_role_name(u.role_id) = any(p_role_names)
    and u.is_active = true
    and u.company_id = v_company_id
    and u.id <> auth.uid();
end;
$$;

create or replace function public.create_order(
  p_customer_name text,
  p_customer_phone text,
  p_order_notes text,
  p_items jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order_id uuid := gen_random_uuid();
  v_actor_name text;
  v_item jsonb;
  v_product record;
  v_quantity integer;
  v_total_cost numeric(14,2) := 0;
  v_total_revenue numeric(14,2) := 0;
  v_total_profit numeric(14,2) := 0;
begin
  perform public.require_active_user();

  if not public.has_permission('orders_create') then
    raise exception 'Missing permission orders_create';
  end if;

  select u.name
  into v_actor_name
  from public.users u
  where u.id = auth.uid();

  if v_actor_name is null then
    raise exception 'Authenticated user profile was not found';
  end if;

  insert into public.orders (
    id,
    customer_name,
    customer_phone,
    order_notes,
    status,
    created_by,
    created_by_name
  )
  values (
    v_order_id,
    p_customer_name,
    p_customer_phone,
    nullif(p_order_notes, ''),
    'entered',
    auth.uid(),
    v_actor_name
  );

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_quantity := (v_item ->> 'quantity')::integer;
    if v_quantity <= 0 then
      raise exception 'Order quantity must be greater than zero';
    end if;

    select
      p.id,
      p.name,
      p.purchase_price,
      p.sale_price
    into v_product
    from public.products p
    where p.id = (v_item ->> 'product_id')::uuid
      and p.is_active = true;

    if v_product.id is null then
      raise exception 'Invalid product in order payload';
    end if;

    insert into public.order_items (
      order_id,
      product_id,
      product_name,
      quantity,
      purchase_price,
      sale_price,
      profit
    )
    values (
      v_order_id,
      v_product.id,
      v_product.name,
      v_quantity,
      v_product.purchase_price,
      v_product.sale_price,
      (v_product.sale_price - v_product.purchase_price) * v_quantity
    );

    v_total_cost := v_total_cost + (v_product.purchase_price * v_quantity);
    v_total_revenue := v_total_revenue + (v_product.sale_price * v_quantity);
    v_total_profit := v_total_profit + ((v_product.sale_price - v_product.purchase_price) * v_quantity);
  end loop;

  update public.orders
  set
    total_cost = v_total_cost,
    total_revenue = v_total_revenue,
    profit = v_total_profit
  where id = v_order_id;

  insert into public.order_status_history (
    order_id,
    status,
    changed_by,
    changed_by_name,
    note
  )
  values (
    v_order_id,
    'entered',
    auth.uid(),
    v_actor_name,
    'Order created'
  );

  perform public.notify_roles(
    array['Order Reviewer', 'Admin'],
    'Order entered',
    'A new order is awaiting review.',
    v_order_id::text,
    'workflow'
  );

  perform public.write_activity_log(
    auth.uid(),
    'order_created',
    'order',
    v_order_id::text,
    jsonb_build_object('status', 'entered')
  );

  return v_order_id;
end;
$$;

grant execute on function public.resolve_role_name(uuid) to authenticated;
grant execute on function public.resolve_permission_code(uuid) to authenticated;
grant execute on function public.user_effective_permissions(uuid, uuid) to authenticated;
grant execute on function public.current_role_name() to authenticated;
grant execute on function public.current_user_is_active() to authenticated;
grant execute on function public.current_user_permissions() to authenticated;
grant execute on function public.has_permission(text) to authenticated;
grant execute on function public.is_admin() to authenticated;
