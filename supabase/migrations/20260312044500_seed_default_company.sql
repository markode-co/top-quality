-- Ensure a default company/branch and assign it to admin user(s)
insert into public.companies (id, name)
select gen_random_uuid(), 'Default Company'
where not exists (select 1 from public.companies limit 1);
-- Ensure a default branch for the first/only company
insert into public.branches (id, company_id, name)
select gen_random_uuid(), c.id, 'Main Branch'
from public.companies c
where not exists (select 1 from public.branches limit 1);
-- Assign company/branch to admin user if missing
with tgt as (
  select u.id,
         coalesce(u.company_id, (select id from public.companies limit 1)) as company_id,
         coalesce(u.branch_id, (select id from public.branches limit 1))   as branch_id
  from public.users u
  where u.email = 'markode@gmail.com'
)
update public.users u
set company_id = tgt.company_id,
    branch_id  = tgt.branch_id
from tgt
where u.id = tgt.id;
