-- Set default company_id on notifications to the current user's company.

begin;

alter table if exists public.notifications
  alter column company_id set default public.current_company_id();

commit;
