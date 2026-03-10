-- Add company_id to activity logs and propagate existing rows

alter table public.activity_logs
  add column if not exists company_id uuid;

-- Backfill from actor profile when possible
update public.activity_logs log
set company_id = coalesce(
  log.company_id,
  (
    select company_id
    from public.users u
    where u.id = log.actor_id
    limit 1
  )
)
where company_id is null;

create index if not exists idx_activity_logs_company on public.activity_logs(company_id);

-- Replace write_activity_log to auto-populate company_id
create or replace function public.write_activity_log(
  p_actor_id uuid,
  p_action text,
  p_entity_type text,
  p_entity_id uuid,
  p_metadata jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company_id uuid;
begin
  select company_id into v_company_id
  from public.users
  where id = p_actor_id
  limit 1;

  insert into activity_logs(
    actor_id,
    action,
    entity_type,
    entity_id,
    metadata,
    company_id
  )
  values(
    p_actor_id,
    p_action,
    p_entity_type,
    p_entity_id,
    p_metadata,
    v_company_id
  );
end;
$$;

grant execute on function public.write_activity_log(uuid,text,text,uuid,jsonb) to authenticated;
