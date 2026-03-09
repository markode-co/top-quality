create or replace function public.record_user_login()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_exists boolean;
begin
  perform public.require_active_user();

  update public.users
  set last_active = now()
  where id = auth.uid();

  select exists (
    select 1
    from public.users
    where id = auth.uid()
  )
  into v_user_exists;

  if not v_user_exists then
    return;
  end if;

  begin
    perform public.write_activity_log(
      auth.uid(),
      'user_login',
      'auth',
      auth.uid()::text,
      '{}'::jsonb
    );
  exception
    when unique_violation or exclusion_violation then
      null;
  end;
end;
$$;
