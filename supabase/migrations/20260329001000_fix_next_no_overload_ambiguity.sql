-- Fix overloaded sequence helper ambiguity.
-- The 2-arg branch-aware helpers must NOT have default args, otherwise calls
-- like next_product_no(uuid) become ambiguous with the legacy 1-arg overload.

begin;

drop function if exists public.next_order_no(uuid, uuid);
create or replace function public.next_order_no(
  p_company_id uuid,
  p_branch_id uuid
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  cid uuid := coalesce(p_company_id, public.current_company_id());
  bid uuid := p_branch_id;
  v_next bigint;
begin
  if cid is null then
    raise exception 'company_required';
  end if;

  if bid is null then
    return public.next_order_no(cid);
  end if;

  insert into public.branch_counters (company_id, branch_id)
  values (cid, bid)
  on conflict (company_id, branch_id) do nothing;

  update public.branch_counters
  set next_order_no = next_order_no + 1,
      updated_at = now()
  where company_id = cid
    and branch_id = bid
  returning next_order_no - 1 into v_next;

  return v_next;
end;
$$;

grant execute on function public.next_order_no(uuid, uuid) to authenticated;

drop function if exists public.next_product_no(uuid, uuid);
create or replace function public.next_product_no(
  p_company_id uuid,
  p_branch_id uuid
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  cid uuid := coalesce(p_company_id, public.current_company_id());
  bid uuid := p_branch_id;
  v_next bigint;
begin
  if cid is null then
    raise exception 'company_required';
  end if;

  if bid is null then
    return public.next_product_no(cid);
  end if;

  insert into public.branch_counters (company_id, branch_id)
  values (cid, bid)
  on conflict (company_id, branch_id) do nothing;

  update public.branch_counters
  set next_product_no = next_product_no + 1,
      updated_at = now()
  where company_id = cid
    and branch_id = bid
  returning next_product_no - 1 into v_next;

  return v_next;
end;
$$;

grant execute on function public.next_product_no(uuid, uuid) to authenticated;

create or replace function public.trg_set_order_no()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.order_no is null then
    if new.branch_id is null then
      new.order_no := public.next_order_no(coalesce(new.company_id, public.current_company_id()));
    else
      new.order_no := public.next_order_no(
        coalesce(new.company_id, public.current_company_id()),
        new.branch_id
      );
    end if;
  end if;
  return new;
end;
$$;

create or replace function public.trg_set_product_no()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.product_no is null then
    if new.branch_id is null then
      new.product_no := public.next_product_no(coalesce(new.company_id, public.current_company_id()));
    else
      new.product_no := public.next_product_no(
        coalesce(new.company_id, public.current_company_id()),
        new.branch_id
      );
    end if;
  end if;
  return new;
end;
$$;

notify pgrst, 'reload schema';

commit;
