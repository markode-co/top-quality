-- Remove legacy overload that confuses PostgREST (PGRST203 ambiguity)
drop function if exists public.upsert_product(
  p_category text,
  p_min_stock int,
  p_name text,
  p_product_id uuid,
  p_purchase_price numeric,
  p_sale_price numeric,
  p_sku text,
  p_stock int
);
