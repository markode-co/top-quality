-- Allow authenticated users to see only employees in their own company (unless admin).
-- Keeps admins’ full access via existing policies.

alter table public.users enable row level security;

drop policy if exists "users_company_access" on public.users;

create policy "users_company_access"
on public.users
for select
to authenticated
using (
  company_id = (select company_id from public.users where id = auth.uid() limit 1)
  and (
    public.is_admin()
    or exists (
      select 1 from public.role_permissions rp
      join public.users u on u.id = auth.uid() and u.role_id = rp.role_id
      where rp.permission_code = 'users_view'
    )
    or exists (
      select 1 from public.user_permissions up
      where up.user_id = auth.uid() and up.permission_code = 'users_view'
    )
  )
);

notify pgrst, 'reload schema';
