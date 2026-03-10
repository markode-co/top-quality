-- =====================================================
-- FORCE USERS SELF SELECT POLICY
-- =====================================================

do $$
begin
  if exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'users'
      and policyname = 'users_read_own_profile'
  ) then
    execute 'drop policy "users_read_own_profile" on public.users';
  end if;

  execute '
    create policy "users_read_own_profile"
    on public.users
    for select
    to authenticated
    using (auth.uid() = id)
  ';
end;
$$;

notify pgrst, 'reload schema';
