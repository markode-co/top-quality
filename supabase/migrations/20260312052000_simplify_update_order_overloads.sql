-- Remove legacy overloads of update_order that can cause ambiguity
drop function if exists public.update_order(text, text, jsonb, uuid, text);
drop function if exists public.update_order(uuid, text, text, jsonb, text);

-- Ensure primary signature with address remains granted
grant execute on function public.update_order(
  uuid, text, text, jsonb, text, text
) to authenticated;
