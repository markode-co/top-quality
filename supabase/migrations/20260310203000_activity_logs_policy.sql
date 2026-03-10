-- Strengthen activity_logs RLS for company scoping and explicit permission

drop policy if exists "admin_logs_access" on public.activity_logs;
drop policy if exists "activity_logs_admin_all" on public.activity_logs;
drop policy if exists "activity_logs_company_view" on public.activity_logs;

create policy "activity_logs_admin_all"
on public.activity_logs
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

create policy "activity_logs_company_view"
on public.activity_logs
for select
to authenticated
using (
  exists (
    select 1
    from public.users u
    where u.id = auth.uid()
      and u.is_active
      and coalesce(activity_logs.company_id, u.company_id) = u.company_id
      and (
        public.is_admin()
        or exists (
          select 1
          from public.role_permissions rp
          join public.permissions p
            on p.code = rp.permission_code
          where rp.role_id = u.role_id
            and p.code = 'activity_logs_view'
        )
        or exists (
          select 1
          from public.user_permissions up
          where up.user_id = u.id
            and up.permission_code = 'activity_logs_view'
        )
      )
  )
);

notify pgrst, 'reload schema';
