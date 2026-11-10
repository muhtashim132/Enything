-- =============================================================================
-- Migration: 20290000000190_100x_department_product_counts_and_carousel_parity.sql
-- Description:
-- 1. Creates public.get_nearby_department_product_counts RPC to return the true
--    aggregate count of active products per department across nearby stores.
--    Eliminates dashboard count badge vs category listing disparity.
-- 2. Grants execute permissions to authenticated and anon users.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_nearby_department_product_counts(
  p_shop_ids uuid[]
)
RETURNS TABLE(department text, total_count bigint)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT 
    CASE 
      WHEN lower(p.category) LIKE '%pharmac%' OR lower(p.category) LIKE '%medic%' OR lower(p.category) LIKE '%chemist%' THEN 'Pharmacy'
      WHEN lower(p.category) LIKE '%cosmetic%' OR lower(p.category) LIKE '%beauty%' OR lower(p.category) LIKE '%salon%' THEN 'Cosmetics'
      WHEN lower(p.category) LIKE '%food%' OR lower(p.category) LIKE '%restaurant%' OR lower(p.category) LIKE '%bakery%' OR lower(p.category) LIKE '%cafe%' OR lower(p.category) LIKE '%fast food%' OR lower(p.category) LIKE '%sweets%' OR lower(p.category) LIKE '%ice cream%' OR lower(p.category) LIKE '%beverage%' THEN 'Food'
      WHEN lower(p.category) LIKE '%grocer%' OR lower(p.category) LIKE '%supermarket%' OR lower(p.category) LIKE '%hypermarket%' OR lower(p.category) LIKE '%dairy%' OR lower(p.category) LIKE '%fruit%' OR lower(p.category) LIKE '%veg%' OR lower(p.category) LIKE '%grocery_lm%' OR lower(p.category) LIKE '%grocerylm%' THEN 'Grocery'
      WHEN lower(p.category) LIKE '%cloth%' OR lower(p.category) LIKE '%footwear%' OR lower(p.category) LIKE '%fashion%' OR lower(p.category) LIKE '%apparel%' OR lower(p.category) LIKE '%jewel%' THEN 'Clothing'
      WHEN lower(p.category) LIKE '%station%' OR lower(p.category) LIKE '%book%' OR lower(p.category) LIKE '%office%' THEN 'Stationery'
      ELSE 'Other'
    END as department,
    COUNT(*) as total_count
  FROM public.products p
  INNER JOIN public.shops s ON p.shop_id = s.id
  WHERE p.shop_id = ANY(p_shop_ids::uuid[])
    AND p.is_available = true
    AND p.is_deleted = false
    AND s.is_active = true
    AND COALESCE(s.is_manually_closed, false) = false
  GROUP BY 1;
$$;

GRANT EXECUTE ON FUNCTION public.get_nearby_department_product_counts(uuid[]) TO authenticated, anon;
