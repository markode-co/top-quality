-- Refresh activity logs view to show real actor info and hide diagnostic noise

drop view if exists public.v_activity_logs;
create view public.v_activity_logs as
select
  l.id,
  case
    when l.actor_id = '00000000-0000-0000-0000-000000000000' then null
    else l.actor_id
  end as actor_id,
  coalesce(u.name, au.email, u.email, 'System') as actor_name,
  coalesce(u.email, au.email) as actor_email,
  l.action,
  l.entity_type,
  l.entity_id,
  l.metadata,
  l.company_id,
  l.created_at
from public.activity_logs l
left join public.users u on u.id = l.actor_id
left join auth.users au on au.id = l.actor_id
where l.action not like 'smoke_test%' -- remove diagnostic rows from runtime checker;
grant select on public.v_activity_logs to authenticated;
