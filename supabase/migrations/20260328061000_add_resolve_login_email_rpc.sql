-- Resolve login identifier (username/email-local-part/email) into an email
-- so clients can authenticate with either username or email.
create or replace function public.resolve_login_email(
  p_identifier text
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_identifier text := nullif(btrim(p_identifier), '');
  v_email text;
  v_count integer;
begin
  if v_identifier is null then
    return null;
  end if;

  -- Already an email.
  if position('@' in v_identifier) > 0 then
    return v_identifier;
  end if;

  -- 1) Explicit username match (case-insensitive).
  select btrim(u.email)
  into v_email
  from public.users u
  where lower(coalesce(u.username, '')) = lower(v_identifier)
    and u.email is not null
    and btrim(u.email) <> ''
  order by coalesce(u.is_active, false) desc, u.updated_at desc nulls last
  limit 1;

  if v_email is not null and position('@' in v_email) > 0 then
    return v_email;
  end if;

  -- 2) Fallback to unique email local-part match (before @).
  select count(*)::integer
  into v_count
  from public.users u
  where lower(split_part(coalesce(u.email, ''), '@', 1)) = lower(v_identifier)
    and position('@' in coalesce(u.email, '')) > 1;

  if v_count = 1 then
    select btrim(u.email)
    into v_email
    from public.users u
    where lower(split_part(coalesce(u.email, ''), '@', 1)) = lower(v_identifier)
      and position('@' in coalesce(u.email, '')) > 1
    limit 1;

    if v_email is not null and position('@' in v_email) > 0 then
      return v_email;
    end if;
  end if;

  return null;
end;
$$;

revoke all on function public.resolve_login_email(text) from public;
grant execute on function public.resolve_login_email(text) to anon;
grant execute on function public.resolve_login_email(text) to authenticated;

notify pgrst, 'reload schema';
