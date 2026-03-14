-- Allow company-level log viewing with either activity_logs_view or activity_logs_company_view.

alter table public.activity_logs enable row level security;

drop policy if exists "activity_logs_company_view" on public.activity_logs;

create policy "activity_logs_company_view"
on public.activity_logs for select
to authenticated
using (
  public.current_company_id() is not null
  and coalesce(activity_logs.company_id, public.current_company_id()) = public.current_company_id()
  and (
    public.has_permission('activity_logs_view')
    or public.has_permission('activity_logs_company_view')
  )
);

notify pgrst, 'reload schema';
