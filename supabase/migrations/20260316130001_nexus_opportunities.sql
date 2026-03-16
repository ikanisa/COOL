-- Create Nexus Opportunities table for personalized AI recommendations
create table if not exists public.nexus_opportunities (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  subtitle text not null,
  rationale text not null,
  type text not null, -- AI_MATCH, EFFICIENCY, SECURITY, PROMOTION
  icon_emoji text not null default '✨',
  cta_action text not null, -- Route
  country text,
  sort_order int not null default 0,
  is_active boolean not null default true,
  is_mock boolean not null default false,
  mock_batch text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Enable RLS
alter table public.nexus_opportunities enable row level security;

-- Public read access
create policy "Nexus opportunities are viewable by everyone"
  on public.nexus_opportunities for select
  to authenticated
  using (is_active = true);

-- Admin write access
create policy "Admins can manage nexus opportunities"
  on public.nexus_opportunities for all
  to authenticated
  using (public.is_admin_user());

-- Seed initial opportunities (Migrated from hardcoded UI)
insert into public.nexus_opportunities (
  title, subtitle, rationale, type, icon_emoji, cta_action, sort_order, is_mock, mock_batch
) values 
(
  'Urwego Agri-Loan', 
  'Qualified for up to 500k RWF', 
  'Because your discipline score is 88%', 
  'AI_MATCH', 
  'agriculture_rounded', -- We'll use this as fallback or map it
  '/credit/readiness', 
  100, 
  true, 
  'initial_nexus_seed'
),
(
  'Moto Subscription', 
  'Save 3k next week', 
  'Frequent mobility spend detected', 
  'EFFICIENCY', 
  'moped_rounded', 
  '/mobility', 
  90, 
  true, 
  'initial_nexus_seed'
);
