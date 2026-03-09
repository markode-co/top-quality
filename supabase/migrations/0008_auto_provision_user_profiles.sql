create or replace function public.default_role_id()
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_role_id uuid;
begin
  select r.id
  into v_role_id
  from public.roles r
  where public.resolve_role_name(r.id) = 'Order Entry User'
  order by r.id
  limit 1;

  if v_role_id is null then
    select r.id
    into v_role_id
    from public.roles r
    where public.resolve_role_name(r.id) = 'Admin'
    order by r.id
    limit 1;
  end if;

  if v_role_id is null then
    select r.id
    into v_role_id
    from public.roles r
    order by r.id
    limit 1;
  end if;

  return v_role_id;
end;
$$;

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role_id uuid;
  v_company_id uuid;
  v_branch_id uuid;
  v_email text;
  v_name text;
begin
  if exists (select 1 from public.users u where u.id = new.id) then
    return new;
  end if;

  select public.default_role_id()
  into v_role_id;

  select
    public.default_company_id(),
    public.default_branch_id()
  into
    v_company_id,
    v_branch_id;

  if v_role_id is null or v_company_id is null or v_branch_id is null then
    return new;
  end if;

  v_email := nullif(trim(coalesce(new.email, '')), '');
  v_name := coalesce(
    nullif(trim(coalesce(new.raw_user_meta_data ->> 'name', '')), ''),
    nullif(split_part(coalesce(v_email, ''), '@', 1), ''),
    'User'
  );

  insert into public.users (
    id,
    company_id,
    branch_id,
    name,
    email,
    role_id,
    is_active,
    last_active
  )
  values (
    new.id,
    v_company_id,
    v_branch_id,
    v_name,
    coalesce(v_email, new.id::text || '@local.invalid'),
    v_role_id,
    true,
    now()
  )
  on conflict (id) do nothing;

  return new;
exception
  when unique_violation then
    return new;
end;
$$;

drop trigger if exists trg_auth_user_created on auth.users;
create trigger trg_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_auth_user();

do $$
declare
  v_role_id uuid;
  v_company_id uuid;
  v_branch_id uuid;
begin
  select public.default_role_id()
  into v_role_id;

  select
    public.default_company_id(),
    public.default_branch_id()
  into
    v_company_id,
    v_branch_id;

  if v_role_id is null or v_company_id is null or v_branch_id is null then
    raise notice 'Skipping auth.users backfill because defaults are missing.';
    return;
  end if;

  insert into public.users (
    id,
    company_id,
    branch_id,
    name,
    email,
    role_id,
    is_active,
    last_active
  )
  select
    au.id,
    v_company_id,
    v_branch_id,
    coalesce(
      nullif(trim(coalesce(au.raw_user_meta_data ->> 'name', '')), ''),
      nullif(split_part(coalesce(au.email, ''), '@', 1), ''),
      'User'
    ) as name,
    coalesce(
      nullif(trim(coalesce(au.email, '')), ''),
      au.id::text || '@local.invalid'
    ) as email,
    v_role_id,
    true,
    now()
  from auth.users au
  where not exists (
    select 1
    from public.users u
    where u.id = au.id
  )
    and (
      au.email is null
      or not exists (
        select 1
        from public.users ux
        where lower(ux.email) = lower(au.email)
      )
    )
  on conflict (id) do nothing;
end;
$$;

grant execute on function public.default_role_id() to authenticated;
