-- ══════════════════════════════════════════════════════════════════
-- GAMIFICATION RPCS & REWARDS MARKETPLACE
-- ══════════════════════════════════════════════════════════════════

-- 1) cool_achievements: track unlocked milestones
CREATE TABLE IF NOT EXISTS public.cool_achievements (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    achievement_id text NOT NULL, -- e.g. 'explorer', 'super_saver'
    badge_type  text DEFAULT 'blue' NOT NULL,
    emoji       text DEFAULT '🏆' NOT NULL,
    name        text NOT NULL,
    description text,
    feature_context text, -- e.g. 'mobility', 'groups'
    points_value int DEFAULT 0,
    is_earned   boolean DEFAULT false,
    earned_at   timestamptz,
    created_at  timestamptz DEFAULT now() NOT NULL,
    UNIQUE(user_id, achievement_id)
);
ALTER TABLE public.cool_achievements ENABLE ROW LEVEL SECURITY;
CREATE POLICY cool_achievements_select ON public.cool_achievements
    FOR SELECT USING (auth.uid() = user_id);
-- 2) cool_rewards: available items in the marketplace
CREATE TABLE IF NOT EXISTS public.cool_rewards (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    type        text NOT NULL, -- 'digitalGoods', 'partnerPerk', 'communityImpact'
    title       text NOT NULL,
    description text NOT NULL,
    token_cost  int NOT NULL,
    emoji       text DEFAULT '🎁' NOT NULL,
    partner_id  uuid,
    is_active   boolean DEFAULT true,
    expiry_date timestamptz,
    created_at  timestamptz DEFAULT now() NOT NULL
);
ALTER TABLE public.cool_rewards ENABLE ROW LEVEL SECURITY;
CREATE POLICY cool_rewards_select ON public.cool_rewards
    FOR SELECT USING (auth.role() = 'authenticated');
-- 3) cool_reward_redemptions: track who bought what
CREATE TABLE IF NOT EXISTS public.cool_reward_redemptions (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    reward_id   uuid REFERENCES public.cool_rewards(id) ON DELETE CASCADE NOT NULL,
    cost_at_redemption int NOT NULL,
    redeemed_at timestamptz DEFAULT now() NOT NULL
);
ALTER TABLE public.cool_reward_redemptions ENABLE ROW LEVEL SECURITY;
CREATE POLICY cool_reward_redemptions_select ON public.cool_reward_redemptions
    FOR SELECT USING (auth.uid() = user_id);
-- ─── RPC: award_cool_achievement ───────────────────────────────

CREATE OR REPLACE FUNCTION public.award_cool_achievement(
    p_user_id uuid,
    p_achievement_id text,
    p_points_value int DEFAULT 0
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Only service_role or the user themselves can trigger this (usually service role via triggers)
    -- But for simplicity in this proto, we allow the user or admin.
    
    UPDATE public.cool_achievements
    SET 
        is_earned = true,
        earned_at = now(),
        points_value = p_points_value
    WHERE user_id = p_user_id 
      AND achievement_id = p_achievement_id
      AND is_earned = false;

    IF FOUND AND p_points_value > 0 THEN
        PERFORM public.apply_cool_event_internal(
            p_user_id,
            'achievementUnlocked',
            p_points_value,
            p_achievement_id,
            jsonb_build_object('achievement_id', p_achievement_id),
            NULL,
            'achievement:' || p_user_id || ':' || p_achievement_id,
            NULL,
            NULL
        );
    END IF;
END;
$$;
-- ─── RPC: redeem_cool_reward ────────────────────────────────────

CREATE OR REPLACE FUNCTION public.redeem_cool_reward(
    p_user_id uuid,
    p_reward_id uuid
)
RETURNS public.cool_status
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_cost int;
    v_current_points int;
    v_status public.cool_status;
BEGIN
    -- 1. Get reward cost
    SELECT token_cost INTO v_cost
    FROM public.cool_rewards
    WHERE id = p_reward_id AND is_active = true;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Reward not found or inactive';
    END IF;

    -- 2. Get user points
    SELECT total_points INTO v_current_points
    FROM public.cool_status
    WHERE user_id = p_user_id;

    IF v_current_points < v_cost THEN
        RAISE EXCEPTION 'Insufficient points. Have %, need %', v_current_points, v_cost;
    END IF;

    -- 3. Record redemption
    INSERT INTO public.cool_reward_redemptions (user_id, reward_id, cost_at_redemption)
    VALUES (p_user_id, p_reward_id, v_cost);

    -- 4. Deduct points (as a negative event)
    SELECT * INTO v_status
    FROM public.apply_cool_event_internal(
        p_user_id,
        'rewardRedeemed',
        -v_cost,
        p_reward_id::text,
        jsonb_build_object('reward_id', p_reward_id),
        NULL,
        NULL, -- No dedupe needed for redemptions
        NULL,
        NULL
    );

    RETURN v_status;
END;
$$;
-- ─── Seed Initial Rewards ───────────────────────────────────────

INSERT INTO public.cool_rewards (type, title, description, token_cost, emoji)
VALUES 
('digitalGoods', 'Streak Freeze', 'Protect your streak for one day if you miss an activity.', 250, '❄️'),
('digitalGoods', 'Golden Profile Frame', 'Exclusive gold border for your profile picture.', 500, '👑'),
('partnerPerk', 'Zero-Fee Transfer', 'One mobile money transfer with 0 transaction fees.', 1000, '💸'),
('communityImpact', 'Initiative Boost', 'Triple the impact of your next community contribution.', 750, '🚀')
ON CONFLICT DO NOTHING;
