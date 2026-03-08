drop policy if exists activity_logs_own_select on public.activity_logs;
drop policy if exists activity_logs_own_insert on public.activity_logs;

alter table public.activity_logs
add column if not exists actor_id uuid references public.users(id) on delete set null;

alter table public.activity_logs
add column if not exists user_id uuid references public.users(id) on delete set null;

alter table public.activity_logs
add column if not exists actor_name text;

alter table public.activity_logs
add column if not exists action text;

alter table public.activity_logs
add column if not exists entity_type text;

alter table public.activity_logs
add column if not exists entity_id text;

alter table public.activity_logs
add column if not exists metadata jsonb default '{}'::jsonb;

alter table public.activity_logs
add column if not exists created_at timestamptz default now();

do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'activity_logs'
      and column_name = 'actor_id'
  ) then
    execute $sql$
      update public.activity_logs
      set user_id = actor_id
      where user_id is null
        and actor_id is not null
    $sql$;
  end if;
end;
$$;

create index if not exists idx_activity_logs_actor_id
on public.activity_logs(actor_id);

create index if not exists idx_activity_logs_user_id
on public.activity_logs(user_id);

alter table public.activity_logs enable row level security;

create or replace function public.write_activity_log(
  p_actor_id uuid,
  p_action text,
  p_entity_type text,
  p_entity_id text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_name text;
begin
  select name into v_actor_name
  from public.users
  where id = p_actor_id;

  insert into public.activity_logs (
    actor_id,
    user_id,
    actor_name,
    action,
    entity_type,
    entity_id,
    metadata
  )
  values (
    p_actor_id,
    p_actor_id,
    coalesce(v_actor_name, 'Unknown User'),
    p_action,
    p_entity_type,
    p_entity_id,
    p_metadata
  );
end;
$$;

create policy activity_logs_own_select
on public.activity_logs
for select
to authenticated
using (user_id = (select auth.uid()));

create policy activity_logs_own_insert
on public.activity_logs
for insert
to authenticated
with check (user_id = (select auth.uid()));
