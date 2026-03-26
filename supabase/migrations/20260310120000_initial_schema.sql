-- ==========================================================================
-- Cool App — Initial Schema Migration
-- ==========================================================================
-- Tables: otp_codes, users, groups, group_members, group_contributions,
--         partners, fan_memberships, credit_scores
-- Extensions: postgis, pgcrypto
-- ==========================================================================

-- ── Extensions ───────────────────────────────────────────────────────────

create extension if not exists "postgis" with schema "extensions";
create extension if not exists "pgcrypto" with schema "extensions";
-- ── OTP codes (used by Edge Functions) ───────────────────────────────────

create table if not exists public.otp_codes (
  id          uuid primary key default gen_random_uuid(),
  phone       text not null,
  code        text not null,
  expires_at  timestamptz not null,
  attempts    int default 0,
  verified    boolean default false,
  created_at  timestamptz default now()
);
create index if not exists idx_otp_codes_phone on public.otp_codes (phone);
-- ── Users (app profiles) ─────────────────────────────────────────────────

create table if not exists public.users (
  id             uuid primary key references auth.users(id) on delete cascade,
  phone          text unique not null,
  full_name      text not null default '',
  country        text not null default 'RW',
  language_code  text not null default 'en',
  momo_number    text,
  avatar_url     text,
  created_at     timestamptz default now(),
  updated_at     timestamptz default now()
);
create index if not exists idx_users_phone on public.users (phone);
-- ── Groups ───────────────────────────────────────────────────────────────

create table if not exists public.groups (
  id                    uuid primary key default gen_random_uuid(),
  name                  text not null,
  description           text,
  country               text not null default 'RW',
  creator_id            uuid not null references public.users(id) on delete cascade,
  visibility            text not null default 'private' check (visibility in ('public', 'private')),
  contribution_amount   int not null default 0,
  cycle_days            int not null default 30,
  member_count          int not null default 0,
  created_at            timestamptz default now(),
  updated_at            timestamptz default now()
);
create index if not exists idx_groups_country on public.groups (country);
create index if not exists idx_groups_visibility on public.groups (visibility);
-- ── Group members ────────────────────────────────────────────────────────

create table if not exists public.group_members (
  id                    uuid primary key default gen_random_uuid(),
  group_id              uuid not null references public.groups(id) on delete cascade,
  user_id               uuid not null references public.users(id) on delete cascade,
  display_name          text,
  is_admin              boolean default false,
  is_anonymous          boolean default false,
  contribution_amount   int default 0,
  joined_at             timestamptz default now(),
  unique(group_id, user_id)
);
create index if not exists idx_group_members_group on public.group_members (group_id);
create index if not exists idx_group_members_user on public.group_members (user_id);
-- ── Group contributions ──────────────────────────────────────────────────

create table if not exists public.group_contributions (
  id          uuid primary key default gen_random_uuid(),
  group_id    uuid not null references public.groups(id) on delete cascade,
  user_id     uuid not null references public.users(id) on delete cascade,
  amount      int not null default 0,
  status      text not null default 'pending' check (status in ('pending', 'confirmed', 'failed')),
  created_at  timestamptz default now()
);
create index if not exists idx_contributions_group on public.group_contributions (group_id);
create index if not exists idx_contributions_user on public.group_contributions (user_id);
create index if not exists idx_contributions_status on public.group_contributions (status);
-- ── Partners ─────────────────────────────────────────────────────────────

create table if not exists public.partners (
  id            uuid primary key default gen_random_uuid(),
  name          text not null,
  category      text not null default 'football' check (category in ('football', 'bank', 'organization')),
  country       text not null default 'RW',
  logo_url      text,
  description   text,
  fan_count     int default 0,
  club_count    int default 0,
  game_count    int default 0,
  created_at    timestamptz default now()
);
-- ── Fan memberships ──────────────────────────────────────────────────────

create table if not exists public.fan_memberships (
  id          uuid primary key default gen_random_uuid(),
  partner_id  uuid not null references public.partners(id) on delete cascade,
  user_id     uuid not null references public.users(id) on delete cascade,
  tier        text not null default 'bronze' check (tier in ('bronze', 'silver', 'gold')),
  joined_at   timestamptz default now(),
  unique(partner_id, user_id)
);
create index if not exists idx_fan_memberships_partner on public.fan_memberships (partner_id);
create index if not exists idx_fan_memberships_user on public.fan_memberships (user_id);
-- ── Credit scores ────────────────────────────────────────────────────────

create table if not exists public.credit_scores (
  id                    uuid primary key default gen_random_uuid(),
  user_id               uuid not null references public.users(id) on delete cascade,
  score                 int not null default 0,
  saving_consistency    int not null default 0,
  group_participation   int not null default 0,
  payment_history       int not null default 0,
  community_activity    int not null default 0,
  recorded_at           timestamptz default now()
);
create index if not exists idx_credit_scores_user on public.credit_scores (user_id);
-- ==========================================================================
-- RLS policies
-- ==========================================================================

-- ── Enable RLS on all tables ─────────────────────────────────────────────

alter table public.otp_codes          enable row level security;
alter table public.users              enable row level security;
alter table public.groups             enable row level security;
alter table public.group_members      enable row level security;
alter table public.group_contributions enable row level security;
alter table public.partners           enable row level security;
alter table public.fan_memberships    enable row level security;
alter table public.credit_scores      enable row level security;
-- ── OTP codes: service role only (Edge Functions use admin client) ────────
-- No public policies — only the service_role key can access otp_codes.

-- ── Users ────────────────────────────────────────────────────────────────

create policy "users_select_own"
  on public.users for select
  using (auth.uid() = id);
create policy "users_insert_own"
  on public.users for insert
  with check (auth.uid() = id);
create policy "users_update_own"
  on public.users for update
  using (auth.uid() = id)
  with check (auth.uid() = id);
-- ── Groups ───────────────────────────────────────────────────────────────

create policy "groups_select_public"
  on public.groups for select
  using (
    visibility = 'public'
    or creator_id = auth.uid()
    or exists (
      select 1 from public.group_members gm
      where gm.group_id = id and gm.user_id = auth.uid()
    )
  );
create policy "groups_insert"
  on public.groups for insert
  with check (auth.uid() = creator_id);
create policy "groups_update_creator"
  on public.groups for update
  using (auth.uid() = creator_id);
-- ── Group members ────────────────────────────────────────────────────────

create policy "group_members_select"
  on public.group_members for select
  using (
    user_id = auth.uid()
    or exists (
      select 1 from public.group_members gm2
      where gm2.group_id = group_id and gm2.user_id = auth.uid()
    )
  );
create policy "group_members_insert"
  on public.group_members for insert
  with check (user_id = auth.uid());
create policy "group_members_delete_own"
  on public.group_members for delete
  using (user_id = auth.uid());
-- ── Group contributions ──────────────────────────────────────────────────

create policy "contributions_select"
  on public.group_contributions for select
  using (
    exists (
      select 1 from public.group_members gm
      where gm.group_id = group_id and gm.user_id = auth.uid()
    )
  );
create policy "contributions_insert"
  on public.group_contributions for insert
  with check (auth.uid() = user_id);
-- ── Partners ─────────────────────────────────────────────────────────────

create policy "partners_select_all"
  on public.partners for select
  using (true);
-- ── Fan memberships ──────────────────────────────────────────────────────

create policy "fan_memberships_select"
  on public.fan_memberships for select
  using (user_id = auth.uid());
create policy "fan_memberships_insert"
  on public.fan_memberships for insert
  with check (auth.uid() = user_id);
create policy "fan_memberships_delete_own"
  on public.fan_memberships for delete
  using (auth.uid() = user_id);
-- ── Credit scores ────────────────────────────────────────────────────────

create policy "credit_scores_select_own"
  on public.credit_scores for select
  using (auth.uid() = user_id);
