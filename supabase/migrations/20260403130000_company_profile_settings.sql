alter table public.companies
  add column if not exists official_email text,
  add column if not exists phone text,
  add column if not exists address text,
  add column if not exists inventory_alerts_enabled boolean not null default true,
  add column if not exists auto_approve_repeat_orders boolean not null default false,
  add column if not exists require_invoice_verification boolean not null default true;

do $$
begin
  if exists (
    select 1
    from pg_class
    where relname = 'companies'
  ) then
    if not exists (
      select 1
      from pg_policies
      where schemaname = 'public'
        and tablename = 'companies'
        and policyname = 'companies_current_update'
    ) then
      create policy companies_current_update
      on public.companies
      for update
      to authenticated
      using (id = public.current_company_id())
      with check (id = public.current_company_id());
    end if;
  end if;
end $$;
