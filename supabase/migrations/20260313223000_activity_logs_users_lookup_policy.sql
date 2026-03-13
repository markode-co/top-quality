-- Allow readers with activity_logs_view to resolve actor info in v_activity_logs

-- Policy: permit selecting users from the same company when the caller has activity_logs_view
drop policy if exists "users_activity_logs_lookup" on public.users;
create policy "users_activity_logs_lookup"
on public.users for select
to authenticated
using (
  auth.uid() is not null
  and company_id = (select company_id from public.users where id = auth.uid() limit 1)
  and (
    public.is_admin()
    or exists (
      select 1 from public.role_permissions rp
      where rp.role_id = public.users.role_id
        and rp.permission_code = 'activity_logs_view'
    )
    or exists (
      select 1 from public.user_permissions up
      where up.user_id = auth.uid()
        and up.permission_code = 'activity_logs_view'
    )
  )
);

-- Ensure permission code exists (idempotent)
insert into public.permissions (code, description)
values ('activity_logs_view', 'Read activity logs')
on conflict do nothing;

-- Grant select on view (idempotent)
grant select on public.v_activity_logs to authenticated;
