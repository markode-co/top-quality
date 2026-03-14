-- Tighten and simplify RLS to ensure logs and users are visible only per company, without recursion.

alter table public.activity_logs enable row level security;
alter table public.users enable row level security;

-- Activity logs: company scoped view + admin
drop policy if exists "activity_logs_company_view" on public.activity_logs;
drop policy if exists "activity_logs_admin_all" on public.activity_logs;

create policy "activity_logs_admin_all"
on public.activity_logs for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

create policy "activity_logs_company_view"
on public.activity_logs for select
to authenticated
using (
  public.current_company_id() is not null
  and coalesce(activity_logs.company_id, public.current_company_id()) = public.current_company_id()
  and public.has_permission('activity_logs_view')
);

-- Users: company scoped view (no self-join recursion)
drop policy if exists "users_company_access" on public.users;

create policy "users_company_access"
on public.users for select
to authenticated
using (
  public.current_company_id() is not null
  and users.company_id = public.current_company_id()
  and (public.is_admin() or public.has_permission('users_view'))
);

notify pgrst, 'reload schema';
