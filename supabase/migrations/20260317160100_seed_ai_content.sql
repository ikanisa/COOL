-- ════════════════════════════════════════════════════════════════
-- Seed AI Content (draft + inactive by default)
-- Admin must approve + activate for users to see
-- ════════════════════════════════════════════════════════════════

INSERT INTO public.ai_content (title, subtitle, body, rationale, content_type, status, icon_emoji, cta_action, cta_label, sort_order, is_active)
VALUES
  (
    'Track Your MoMo Spending',
    'See where your money goes each month',
    'Sync your mobile money SMS messages to get automatic spending breakdowns, weekly trends, and financial insights.',
    'Understanding spending patterns is the first step to saving more',
    'recommendation',
    'draft',
    '📊',
    '/momo',
    'Open MoMo',
    10,
    false
  ),
  (
    'Start a Group Savings Circle',
    'Save together, grow together',
    'Create or join a community savings group. Pool funds with trusted friends and family for bigger goals.',
    'Group savings help build discipline and grow wealth faster',
    'recommendation',
    'draft',
    '🤝',
    '/groups',
    'View Groups',
    20,
    false
  ),
  (
    'Build Your Credit Score',
    'Your financial reputation matters',
    'A higher credit score unlocks better loan terms and financial opportunities. Start building yours today.',
    'Over 80% of users who check their score weekly improve it within 3 months',
    'tip',
    'draft',
    '📈',
    '/credit',
    'Check Score',
    30,
    false
  ),
  (
    'Earn Cool Tokens Daily',
    'Complete activities to earn rewards',
    'Engage with the app — join groups, schedule rides, check your statements — and earn Cool Tokens for every action.',
    'Active users earn 3x more tokens than passive browsers',
    'promo',
    'draft',
    '🪙',
    '/tokens',
    'View Tokens',
    40,
    false
  ),
  (
    'Schedule Your Next Ride',
    'Plan ahead, save time',
    'Post a trip as a passenger or driver to find ride-sharing partners on your regular routes.',
    'Pre-scheduled rides save an average of 45 minutes per week',
    'recommendation',
    'draft',
    '🚗',
    '/mobility/schedule',
    'Schedule',
    50,
    false
  ),
  (
    'Rayon Sport Fan Zone',
    'Show your support, earn rewards',
    'Attend matches, predict scores, and engage with fellow fans to climb the fan tiers and unlock exclusive perks.',
    'Gold tier fans unlock exclusive match-day experiences',
    'recommendation',
    'draft',
    '⚽',
    '/rayon',
    'Fan Zone',
    60,
    false
  )
ON CONFLICT DO NOTHING;
