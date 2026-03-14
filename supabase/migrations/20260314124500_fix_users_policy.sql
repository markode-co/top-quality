-- Fix infinite recursion on users RLS by avoiding subqueries to the same table.
-- Uses security-definer helpers current_company_id() and has_permission(text).

alter table public.users enable row level security;

drop policy if exists "users_company_access" on public.users;

create policy "users_company_access"
on public.users
for select
to authenticated
using (
  company_id = public.current_company_id()
  and (public.is_admin() or public.has_permission('users_view'))
);

-- keep existing admin-all policy for full control (already present in baseline)
notify pgrst, 'reload schema';
