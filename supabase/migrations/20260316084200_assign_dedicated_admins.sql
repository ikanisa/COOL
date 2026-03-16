-- ════════════════════════════════════════════════════════════════
-- Assign dedicated admin roles by phone number + create SACCO bank
-- ════════════════════════════════════════════════════════════════
-- +250788308095 → Rayon Sport admin
-- +250788673782 → Equity Bank admin
-- +250788824683 → Urwego Finance admin
-- +250785000316 → SACCO admin (new bank partner)
-- ════════════════════════════════════════════════════════════════

-- 1) Create SACCO bank partner
INSERT INTO public.partners (name, slug, category, is_active, description)
VALUES (
  'SACCO',
  'sacco',
  'bank',
  true,
  'Savings and Credit Cooperative Organization'
)
ON CONFLICT (slug) DO NOTHING;

-- 2) Pre-create auth users for the 4 phone numbers (if they don't exist yet)
--    They can later sign in via OTP which will reuse these records.
INSERT INTO auth.users (
  instance_id, id, aud, role, phone, phone_confirmed_at,
  raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at, confirmation_token, is_sso_user
)
VALUES
  -- Rayon Sport admin
  ('00000000-0000-0000-0000-000000000000', gen_random_uuid(), 'authenticated', 'authenticated',
   '+250788308095', now(),
   '{"provider":"phone","providers":["phone"]}'::jsonb,
   '{"full_name":"Rayon Sport Admin"}'::jsonb,
   now(), now(), '', false),
  -- Equity Bank admin
  ('00000000-0000-0000-0000-000000000000', gen_random_uuid(), 'authenticated', 'authenticated',
   '+250788673782', now(),
   '{"provider":"phone","providers":["phone"]}'::jsonb,
   '{"full_name":"Equity Bank Admin"}'::jsonb,
   now(), now(), '', false),
  -- Urwego Finance admin
  ('00000000-0000-0000-0000-000000000000', gen_random_uuid(), 'authenticated', 'authenticated',
   '+250788824683', now(),
   '{"provider":"phone","providers":["phone"]}'::jsonb,
   '{"full_name":"Urwego Finance Admin"}'::jsonb,
   now(), now(), '', false),
  -- SACCO admin
  ('00000000-0000-0000-0000-000000000000', gen_random_uuid(), 'authenticated', 'authenticated',
   '+250785000316', now(),
   '{"provider":"phone","providers":["phone"]}'::jsonb,
   '{"full_name":"SACCO Admin"}'::jsonb,
   now(), now(), '', false)
ON CONFLICT (phone) DO NOTHING;

-- 3) Ensure public.users entries exist for these auth users
INSERT INTO public.users (id, phone, full_name, is_admin, is_mock, created_at)
SELECT au.id, au.phone, au.raw_user_meta_data->>'full_name', false, false, now()
FROM auth.users au
WHERE au.phone IN ('+250788308095', '+250788673782', '+250788824683', '+250785000316')
ON CONFLICT (id) DO NOTHING;

-- 4) Assign admin roles
DO $$
DECLARE
  v_rayon_id  uuid;
  v_equity_id uuid;
  v_urwego_id uuid;
  v_sacco_id  uuid;
  v_user_id   uuid;
BEGIN
  SELECT id INTO v_rayon_id  FROM public.partners WHERE slug = 'rayon-sports' LIMIT 1;
  SELECT id INTO v_equity_id FROM public.partners WHERE slug = 'equity'       LIMIT 1;
  SELECT id INTO v_urwego_id FROM public.partners WHERE slug = 'urwego'       LIMIT 1;
  SELECT id INTO v_sacco_id  FROM public.partners WHERE slug = 'sacco'        LIMIT 1;

  -- Rayon Sport: +250788308095
  SELECT id INTO v_user_id FROM auth.users WHERE phone = '+250788308095';
  IF v_user_id IS NOT NULL AND v_rayon_id IS NOT NULL THEN
    INSERT INTO public.admin_role_assignments (user_id, role, partner_scope_id, notes)
    VALUES (v_user_id, 'rayon_sport', v_rayon_id, 'Dedicated Rayon Sport admin')
    ON CONFLICT (user_id, role, partner_scope_id) DO UPDATE SET is_active = true, revoked_at = NULL;
  END IF;

  -- Equity Bank: +250788673782
  SELECT id INTO v_user_id FROM auth.users WHERE phone = '+250788673782';
  IF v_user_id IS NOT NULL AND v_equity_id IS NOT NULL THEN
    INSERT INTO public.admin_role_assignments (user_id, role, partner_scope_id, notes)
    VALUES (v_user_id, 'bank', v_equity_id, 'Dedicated Equity Bank admin')
    ON CONFLICT (user_id, role, partner_scope_id) DO UPDATE SET is_active = true, revoked_at = NULL;
  END IF;

  -- Urwego Finance: +250788824683
  SELECT id INTO v_user_id FROM auth.users WHERE phone = '+250788824683';
  IF v_user_id IS NOT NULL AND v_urwego_id IS NOT NULL THEN
    INSERT INTO public.admin_role_assignments (user_id, role, partner_scope_id, notes)
    VALUES (v_user_id, 'bank', v_urwego_id, 'Dedicated Urwego Finance admin')
    ON CONFLICT (user_id, role, partner_scope_id) DO UPDATE SET is_active = true, revoked_at = NULL;
  END IF;

  -- SACCO: +250785000316
  SELECT id INTO v_user_id FROM auth.users WHERE phone = '+250785000316';
  IF v_user_id IS NOT NULL AND v_sacco_id IS NOT NULL THEN
    INSERT INTO public.admin_role_assignments (user_id, role, partner_scope_id, notes)
    VALUES (v_user_id, 'bank', v_sacco_id, 'Dedicated SACCO admin')
    ON CONFLICT (user_id, role, partner_scope_id) DO UPDATE SET is_active = true, revoked_at = NULL;
  END IF;
END;
$$;
