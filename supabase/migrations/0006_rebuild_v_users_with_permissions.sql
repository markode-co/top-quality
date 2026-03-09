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

create view public.v_users_with_permissions
with (security_invoker = true)
as
select
  u.id as id,
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
