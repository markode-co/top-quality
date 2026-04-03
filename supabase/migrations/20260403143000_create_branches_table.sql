create table if not exists public.branches (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  name text not null,
  phone text,
  email text,
  address text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists branches_company_name_key
  on public.branches (company_id, name);

create index if not exists branches_company_id_idx
  on public.branches (company_id);

grant select, insert, update on public.branches to authenticated;

alter table public.branches enable row level security;

drop policy if exists branches_company_select on public.branches;
create policy branches_company_select
on public.branches
for select
to authenticated
using (company_id = public.current_company_id());

drop policy if exists branches_company_insert on public.branches;
create policy branches_company_insert
on public.branches
for insert
to authenticated
with check (company_id = public.current_company_id());

drop policy if exists branches_company_update on public.branches;
create policy branches_company_update
on public.branches
for update
to authenticated
using (company_id = public.current_company_id())
with check (company_id = public.current_company_id());
