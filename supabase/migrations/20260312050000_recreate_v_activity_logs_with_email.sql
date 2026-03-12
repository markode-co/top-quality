drop view if exists public.v_activity_logs;

create view public.v_activity_logs as
select
  l.id,
  l.actor_id,
  coalesce(u.name, u.email, 'Unknown') as actor_name,
  u.email as actor_email,
  l.action,
  l.entity_type,
  l.entity_id,
  l.metadata,
  l.company_id,
  l.created_at
from public.activity_logs l
left join public.users u on u.id = l.actor_id;

grant select on public.v_activity_logs to authenticated;

-- Optional: clean old diagnostic rows
delete from public.activity_logs where action like 'diagnostics%';
