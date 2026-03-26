-- ============================================================================
-- Cool App — Enforce Database Integrity for Frontend Safe Defaults
-- ============================================================================

-- 1. Enforce users table
-- Default is already '', ensure it can never be strictly null going forward.
ALTER TABLE public.users ALTER COLUMN full_name SET NOT NULL;
ALTER TABLE public.users ALTER COLUMN full_name SET DEFAULT '';
-- 2. Rayon Sports Fan Clubs
-- Name and region should never be null
ALTER TABLE public.rs_fan_clubs ALTER COLUMN name SET NOT NULL;
ALTER TABLE public.rs_fan_clubs ALTER COLUMN region SET DEFAULT 'Kigali';
ALTER TABLE public.rs_fan_clubs ALTER COLUMN region SET NOT NULL;
-- 3. Rayon Sports Shop Products
-- Name and category should never be null
ALTER TABLE public.rs_shop_products ALTER COLUMN name SET NOT NULL;
ALTER TABLE public.rs_shop_products ALTER COLUMN category SET NOT NULL;
-- 4. Rayon Sports Initiatives 
-- Title and category
ALTER TABLE public.rs_initiatives ALTER COLUMN title SET NOT NULL;
ALTER TABLE public.rs_initiatives ALTER COLUMN category SET NOT NULL;
