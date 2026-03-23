-- ============================================================
-- Seed quest_definitions + special_products, drop legacy fan_memberships
-- ============================================================

-- 1. Quest definitions for gamification engine
INSERT INTO quest_definitions (slug, title, description, event_type, target_count, reward_points, is_active) VALUES
('first_momo_sync', 'First Sync', 'Sync your first MoMo SMS to start building your financial profile', 'momo_sms_synced', 1, 50, true),
('sync_10_sms', 'MoMo Master', 'Sync 10 MoMo SMS messages', 'momo_sms_synced', 10, 100, true),
('first_group_contribution', 'Team Player', 'Make your first group savings contribution', 'group_contribution_confirmed', 1, 75, true),
('save_100k', 'Savings Champion', 'Contribute a total of 100,000 RWF to groups', 'group_contribution_confirmed', 100000, 200, true),
('join_fan_club', 'Super Fan', 'Join a Rayon Sports fan club', 'fan_club_joined', 1, 30, true),
('refer_3_friends', 'Social Star', 'Refer 3 friends to COOL', 'referral_activated', 3, 150, true),
('complete_kyc', 'Verified User', 'Complete your KYC verification', 'kyc_verified', 1, 100, true),
('buy_first_ticket', 'Match Day', 'Buy your first match ticket', 'ticket_purchased', 1, 40, true),
('create_group', 'Group Leader', 'Create your first savings group', 'group_created', 1, 60, true),
('streak_7_days', 'Week Warrior', 'Maintain a 7-day activity streak', 'streak_reached', 7, 120, true)
ON CONFLICT (slug) DO NOTHING;
-- 2. Special products for product shelf
INSERT INTO special_products (slug, title, subtitle, description, amount, icon_name, color_hex, momo_recipient, momo_recipient_type, target_audience, sort_order) VALUES
('emergency_fund', 'Emergency Fund', 'Save for the unexpected', 'Build a safety net for emergencies. Quick-access savings you can count on when life surprises you.', 5000, 'shield', '#E53E3E', '*182*8*1#', 'code', 'Everyone', 1),
('school_fees', 'School Fees Saver', 'Plan ahead for education', 'Set aside money regularly for school fees. Start small, finish strong.', 10000, 'school', '#3182CE', '*182*8*1#', 'code', 'Parents', 2),
('business_boost', 'Business Boost', 'Grow your hustle', 'Save toward a business investment or expansion. Every franc counts toward your dream.', 25000, 'trending_up', '#38A169', '*182*8*1#', 'code', 'Entrepreneurs', 3),
('health_cover', 'Health Cover', 'Protect your health', 'Medical savings for MUTUELLE or private health cover. Be prepared, not worried.', 3000, 'health_and_safety', '#805AD5', '*182*8*1#', 'code', 'Everyone', 4)
ON CONFLICT (slug) DO NOTHING;
-- 3. Drop legacy fan_memberships table (replaced by rs_fan_memberships)
-- Wrapped in DO block because table may already be dropped
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'fan_memberships') THEN
    DROP POLICY IF EXISTS "fan_memberships_public_read" ON public.fan_memberships;
    DROP POLICY IF EXISTS "fan_memberships_insert_authenticated" ON public.fan_memberships;
    DROP POLICY IF EXISTS "fan_memberships_update_own" ON public.fan_memberships;
    DROP POLICY IF EXISTS "fan_memberships_delete_own" ON public.fan_memberships;
    DROP POLICY IF EXISTS "fan_memberships_select_public" ON public.fan_memberships;
    DROP TABLE public.fan_memberships;
  END IF;
END $$;
DROP INDEX IF EXISTS public.idx_fan_memberships_partner_id;
DROP INDEX IF EXISTS public.idx_fan_memberships_user_id;
