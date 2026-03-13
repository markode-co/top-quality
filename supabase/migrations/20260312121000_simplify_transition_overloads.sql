-- Remove legacy overloads that confuse PostgREST routing for status transitions
drop function if exists public.transition_order(text, text, uuid);
drop function if exists public.override_order_status(text, text, uuid);
-- Ensure canonical signatures keep execute grant
grant execute on function public.transition_order(uuid, text, text) to authenticated;
grant execute on function public.override_order_status(uuid, text, text) to authenticated;
