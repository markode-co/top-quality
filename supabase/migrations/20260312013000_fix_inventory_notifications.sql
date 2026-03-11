-- Fix inventory view column naming and add company_id to notifications for REST compatibility

-- Ensure notifications has company_id (nullable) for multi-tenant scoping
alter table if exists public.notifications
  add column if not exists company_id uuid references public.companies(id) on delete set null;

create index if not exists idx_notifications_company on public.notifications(company_id);

-- Recreate inventory view with expected product_id column
drop view if exists public.inventory;
create view public.inventory as
select
  p.id as product_id,
  p.company_id,
  p.branch_id,
  p.name,
  p.sku,
  p.category,
  p.current_stock as stock,
  p.min_stock_level as min_stock,
  p.purchase_price,
  p.sale_price,
  p.is_active,
  p.created_at,
  p.updated_at
from public.products p;

-- Keep v_products aligned (already uses products.* but refresh to ensure schema cache)
create or replace view public.v_products as
select
  p.*,
  p.current_stock as stock,
  p.min_stock_level as min_stock
from public.products p;

notify pgrst, 'reload schema';
