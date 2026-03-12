create or replace function public.delete_product(p_product_id uuid)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  v_company uuid;
begin
  select company_id into v_company from public.users where id = auth.uid();
  if v_company is null then raise exception 'user_not_found'; end if;

  delete from public.products
  where id = p_product_id
    and company_id = v_company;
end;
$$;

grant execute on function public.delete_product(uuid) to authenticated;
