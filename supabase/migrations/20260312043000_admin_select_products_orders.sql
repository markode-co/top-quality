-- Allow admins to read products/orders regardless of company_id
drop policy if exists "products_company_access" on public.products;
create policy "products_company_access"
on public.products for select
to authenticated
using (
  public.is_admin()
  or company_id = (select company_id from public.users where id = auth.uid() limit 1)
);
drop policy if exists "orders_company_access" on public.orders;
create policy "orders_company_access"
on public.orders for select
to authenticated
using (
  public.is_admin()
  or company_id = (select company_id from public.users where id = auth.uid() limit 1)
);
