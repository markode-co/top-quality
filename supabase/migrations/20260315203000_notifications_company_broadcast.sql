-- Allow company-wide notifications (user_id NULL) to be visible to all users in the same company.

begin;

-- Drop existing policies if they exist, then recreate with company-wide visibility
drop policy if exists notifications_company_select on public.notifications;
drop policy if exists notifications_company_update on public.notifications;
drop policy if exists notifications_own_select on public.notifications;
drop policy if exists notifications_own_update on public.notifications;

create policy notifications_company_select
on public.notifications
for select
to authenticated
using (
  company_id = public.current_company_id()
  and (user_id = auth.uid() or user_id is null)
);

create policy notifications_company_update
on public.notifications
for update
to authenticated
using (
  company_id = public.current_company_id()
  and (user_id = auth.uid() or user_id is null)
)
with check (
  company_id = public.current_company_id()
  and (user_id = auth.uid() or user_id is null)
);

-- Ensure new notifications inherit the current company when not provided explicitly.
alter table public.notifications
  alter column company_id set default public.current_company_id();

commit;
