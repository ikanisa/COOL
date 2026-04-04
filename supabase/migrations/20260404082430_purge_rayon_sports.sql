-- Purge all Rayon Sports specific schemas, tables, and roles.

DROP TABLE IF EXISTS public.rs_tickets CASCADE;
DROP TABLE IF EXISTS public.rs_matches CASCADE;
DROP TABLE IF EXISTS public.rs_initiative_contributions CASCADE;
DROP TABLE IF EXISTS public.rs_initiatives CASCADE;
DROP TABLE IF EXISTS public.rs_shop_orders CASCADE;
DROP TABLE IF EXISTS public.rs_shop_products CASCADE;
DROP TABLE IF EXISTS public.rs_achievements CASCADE;
DROP TABLE IF EXISTS public.rs_fan_club_members CASCADE;
DROP TABLE IF EXISTS public.rs_fan_clubs CASCADE;
DROP TABLE IF EXISTS public.rs_fan_memberships CASCADE;
DROP TABLE IF EXISTS public.rs_membership_packages CASCADE;

-- Drop RPCs related to Rayon
DROP FUNCTION IF EXISTS public.get_rayon_member_registry(uuid);
DROP FUNCTION IF EXISTS public.record_momo_evidence(text, text, text, text, text, numeric, text, text, text, jsonb);

-- Anything else?
