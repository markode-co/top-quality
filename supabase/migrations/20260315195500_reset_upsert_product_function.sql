-- Reset and standardize the upsert_product function to remove references to deprecated columns.

BEGIN;

-- Drop any existing overloads to avoid calling stale versions that still touch products.stock.
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS func
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE p.proname = 'upsert_product'
      AND n.nspname = 'public'
  LOOP
    EXECUTE format('DROP FUNCTION IF EXISTS %s CASCADE', r.func);
  END LOOP;
END
$$;

CREATE OR REPLACE FUNCTION public.upsert_product(
  p_category text,
  p_min_stock integer,
  p_name text,
  p_purchase_price numeric,
  p_sale_price numeric,
  p_sku text,
  p_stock integer,
  p_product_id uuid DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_product_id uuid;
BEGIN
  IF p_product_id IS NULL THEN
    v_product_id := gen_random_uuid();
    INSERT INTO public.products (
      id,
      name,
      sku,
      category,
      purchase_price,
      sale_price,
      company_id
    )
    VALUES (
      v_product_id,
      p_name,
      p_sku,
      p_category,
      p_purchase_price,
      p_sale_price,
      public.current_company_id()
    );
  ELSE
    v_product_id := p_product_id;

    UPDATE public.products
    SET name = p_name,
        sku = p_sku,
        category = p_category,
        purchase_price = p_purchase_price,
        sale_price = p_sale_price
    WHERE id = v_product_id
      AND company_id = public.current_company_id();

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Product not found or not in your company';
    END IF;
  END IF;

  -- Keep stock in inventory (one row per product/company/branch). Use branch_id NULL as default bucket.
  UPDATE public.inventory
  SET stock = COALESCE(p_stock, 0),
      min_stock = COALESCE(p_min_stock, 0)
  WHERE product_id = v_product_id
    AND company_id = public.current_company_id()
    AND branch_id IS NULL;

  IF NOT FOUND THEN
    INSERT INTO public.inventory (
      product_id,
      stock,
      min_stock,
      company_id,
      branch_id
    )
    VALUES (
      v_product_id,
      COALESCE(p_stock, 0),
      COALESCE(p_min_stock, 0),
      public.current_company_id(),
      NULL
    );
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.upsert_product(text, integer, text, numeric, numeric, text, integer, uuid) TO authenticated;

COMMIT;
