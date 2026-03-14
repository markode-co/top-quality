-- Allow authorized users to view activity logs across all companies.
-- Admins already have full access; now grant to holders of activity_logs_view_all.

alter table public.activity_logs enable row level security;

drop policy if exists "activity_logs_company_view" on public.activity_logs;
drop policy if exists "activity_logs_admin_all" on public.activity_logs;

create policy "activity_logs_admin_all"
on public.activity_logs for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

create policy "activity_logs_view_all"
on public.activity_logs for select
to authenticated
using (public.has_permission('activity_logs_view_all'));

create policy "activity_logs_company_view"
on public.activity_logs for select
to authenticated
using (
  public.current_company_id() is not null
  and coalesce(activity_logs.company_id, public.current_company_id()) = public.current_company_id()
  and public.has_permission('activity_logs_view')
);

notify pgrst, 'reload schema';
