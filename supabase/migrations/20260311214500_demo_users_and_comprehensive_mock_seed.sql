begin;
-- ============================================================================
-- Comprehensive demo users and app mock seed
-- ----------------------------------------------------------------------------
-- Seeds four realistic WhatsApp-based demo users and coherent data across the
-- app contract. All seeded rows are internally marked with is_mock/mock_batch
-- so admins can identify and remove them later, while the customer UI remains
-- clean.
-- ============================================================================

do $$
declare
  seeded_table text;
  seeded_tables constant text[] := array[
    'users',
    'groups',
    'group_members',
    'group_contributions',
    'driver_profiles',
    'driver_subscriptions',
    'mobility_trips',
    'credit_scores',
    'momo_sms_raw',
    'momo_sms_parsed',
    'momo_ledger_entries',
    'momo_reconciliations',
    'cool_seasons',
    'cool_status',
    'cool_events',
    'cool_missions',
    'cool_mission_progress',
    'season_definitions',
    'season_memberships',
    'rs_fan_memberships',
    'rs_fan_club_members',
    'rs_achievements',
    'rs_matches',
    'rs_shop_products',
    'rs_shop_orders',
    'rs_initiative_contributions',
    'rs_tickets'
  ];
begin
  foreach seeded_table in array seeded_tables loop
    execute format(
      'alter table public.%I add column if not exists is_mock boolean not null default false',
      seeded_table
    );
    execute format(
      'alter table public.%I add column if not exists mock_batch text',
      seeded_table
    );
    execute format(
      'comment on column public.%I.is_mock is %L',
      seeded_table,
      'Internal-only marker for removable demo seed rows. Not intended for customer-facing UI.'
    );
    execute format(
      'comment on column public.%I.mock_batch is %L',
      seeded_table,
      'Internal batch key used to identify and bulk remove demo seed rows.'
    );
  end loop;
end $$;
drop policy if exists users_select_admin on public.users;
create policy users_select_admin
  on public.users for select
  to authenticated
  using (public.is_admin_user());
create temp table demo_runtime (
  mock_batch text primary key,
  active_cool_season_id uuid not null,
  savings_mission_id uuid not null,
  matchday_mission_id uuid not null,
  upcoming_mission_id uuid not null,
  season_definition_id uuid not null,
  rayon_partner_id uuid,
  club_kigali_id uuid,
  club_diaspora_id uuid,
  club_huye_id uuid,
  initiative_fan_kit_id uuid,
  initiative_academy_id uuid
) on commit drop;
insert into demo_runtime (
  mock_batch,
  active_cool_season_id,
  savings_mission_id,
  matchday_mission_id,
  upcoming_mission_id,
  season_definition_id,
  rayon_partner_id,
  club_kigali_id,
  club_diaspora_id,
  club_huye_id,
  initiative_fan_kit_id,
  initiative_academy_id
)
select
  'app_demo_seed_20260311',
  coalesce(
    (
      select id
      from public.cool_seasons
      where is_active = true
        and starts_at <= now()
        and ends_at >= now()
      order by starts_at desc
      limit 1
    ),
    '50330a95-8a2b-451d-990b-c1336d1f5011'::uuid
  ),
  coalesce(
    (
      select id
      from public.cool_missions
      where mission_type = 'savings_sprint'
      order by starts_at desc
      limit 1
    ),
    '7caeb7ef-c56b-4bf5-a255-6c326616c021'::uuid
  ),
  coalesce(
    (
      select id
      from public.cool_missions
      where mission_type = 'matchday_month'
      order by starts_at desc
      limit 1
    ),
    'f9c0d0a2-feb6-4ecb-bd6c-c776ef65fd22'::uuid
  ),
  'ab3e26a6-306e-431b-b0cd-3530be61bb23'::uuid,
  'df723f8b-6df3-4cb5-a3bf-6303df7e4a24'::uuid,
  (
    select id
    from public.partners
    where slug = 'rayon-sports'
    limit 1
  ),
  (
    select id
    from public.rs_fan_clubs
    where name = 'Gikundiro Kigali Ultra'
    limit 1
  ),
  (
    select id
    from public.rs_fan_clubs
    where name = 'Gikundiro Diaspora'
    limit 1
  ),
  (
    select id
    from public.rs_fan_clubs
    where name = 'Huye Blue Army'
    limit 1
  ),
  (
    select id
    from public.rs_initiatives
    where title = 'Fan Kit Subsidy Program'
    limit 1
  ),
  (
    select id
    from public.rs_initiatives
    where title = 'Academy Equipment Drive'
    limit 1
  );
do $$
begin
  if exists (
    select 1
    from demo_runtime
    where rayon_partner_id is null
       or club_kigali_id is null
       or club_diaspora_id is null
       or club_huye_id is null
       or initiative_fan_kit_id is null
       or initiative_academy_id is null
  ) then
    raise exception
      'Rayon Sports base seed is missing. Expected rayon-sports partner, clubs, and initiatives before applying the demo user seed.';
  end if;
end $$;
insert into public.cool_seasons (
  id,
  title,
  theme,
  emoji,
  starts_at,
  ends_at,
  is_active,
  rewards_description,
  is_mock,
  mock_batch
)
select
  active_cool_season_id,
  'Rise Season',
  'supporter',
  '🏅',
  timestamptz '2026-03-01 00:00:00+00',
  timestamptz '2026-06-01 00:00:00+00',
  true,
  'Earn points across savings, mobility, and Rayon Sports to climb the leaderboard.',
  true,
  mock_batch
from demo_runtime
where not exists (
  select 1
  from public.cool_seasons existing
  where existing.id = demo_runtime.active_cool_season_id
);
insert into public.cool_missions (
  id,
  season_id,
  title,
  description,
  mission_type,
  target_value,
  scope_type,
  scope_id,
  emoji,
  starts_at,
  ends_at,
  reward_points,
  reward_description,
  is_active,
  is_mock,
  mock_batch
)
select
  savings_mission_id,
  active_cool_season_id,
  'Community Builders',
  'Keep savings circles active and consistent this month.',
  'savings_sprint',
  50,
  'global',
  null,
  '💰',
  timestamptz '2026-03-01 00:00:00+00',
  timestamptz '2026-03-31 23:59:59+00',
  120,
  'Bonus points for members who stay active in savings circles.',
  true,
  true,
  mock_batch
from demo_runtime
where not exists (
  select 1
  from public.cool_missions existing
  where existing.id = demo_runtime.savings_mission_id
);
insert into public.cool_missions (
  id,
  season_id,
  title,
  description,
  mission_type,
  target_value,
  scope_type,
  scope_id,
  emoji,
  starts_at,
  ends_at,
  reward_points,
  reward_description,
  is_active,
  is_mock,
  mock_batch
)
select
  matchday_mission_id,
  active_cool_season_id,
  'Matchday Heroes',
  'Attend Rayon Sports fixtures and keep the chapter active.',
  'matchday_month',
  3,
  'global',
  null,
  '⚽',
  timestamptz '2026-03-01 00:00:00+00',
  timestamptz '2026-03-31 23:59:59+00',
  150,
  'Bonus points for supporters who show up on matchday.',
  true,
  true,
  mock_batch
from demo_runtime
where not exists (
  select 1
  from public.cool_missions existing
  where existing.id = demo_runtime.matchday_mission_id
);
insert into public.cool_missions (
  id,
  season_id,
  title,
  description,
  mission_type,
  target_value,
  scope_type,
  scope_id,
  emoji,
  starts_at,
  ends_at,
  reward_points,
  reward_description,
  is_active,
  is_mock,
  mock_batch
)
select
  upcoming_mission_id,
  active_cool_season_id,
  'Club Impact Relay',
  'A short supporter sprint for chapters preparing for the next home fixture.',
  'supporter_season',
  3,
  'chapter',
  club_kigali_id::text,
  '🤝',
  timestamptz '2026-03-18 00:00:00+00',
  timestamptz '2026-04-08 23:59:59+00',
  180,
  'Earn extra season points by supporting chapter activities together.',
  true,
  true,
  mock_batch
from demo_runtime
on conflict (id) do update
set
  season_id = excluded.season_id,
  title = excluded.title,
  description = excluded.description,
  mission_type = excluded.mission_type,
  target_value = excluded.target_value,
  scope_type = excluded.scope_type,
  scope_id = excluded.scope_id,
  emoji = excluded.emoji,
  starts_at = excluded.starts_at,
  ends_at = excluded.ends_at,
  reward_points = excluded.reward_points,
  reward_description = excluded.reward_description,
  is_active = excluded.is_active,
  is_mock = excluded.is_mock,
  mock_batch = excluded.mock_batch;
insert into public.season_definitions (
  id,
  slug,
  title,
  description,
  starts_at,
  ends_at,
  is_active,
  is_mock,
  mock_batch
)
select
  season_definition_id,
  'rise-season-2026',
  'Rise Season 2026',
  'Cross-app season tracking for the March to June demo cycle.',
  timestamptz '2026-03-01 00:00:00+00',
  timestamptz '2026-06-01 00:00:00+00',
  true,
  true,
  mock_batch
from demo_runtime
on conflict (slug) do update
set
  title = excluded.title,
  description = excluded.description,
  starts_at = excluded.starts_at,
  ends_at = excluded.ends_at,
  is_active = excluded.is_active,
  is_mock = excluded.is_mock,
  mock_batch = excluded.mock_batch,
  updated_at = now();
create temp table demo_user_seed (
  phone_e164 text primary key,
  phone_digits text not null,
  default_user_id uuid not null,
  user_id uuid,
  full_name text not null,
  country text not null,
  language_code text not null,
  momo_provider text not null,
  momo_number text not null,
  momo_code text,
  vehicle_type text,
  is_driver boolean not null,
  is_admin boolean not null,
  rayon_chapter text not null,
  rayon_points integer not null,
  rayon_tier text not null,
  membership_number text not null,
  joined_at timestamptz not null
) on commit drop;
insert into demo_user_seed (
  phone_e164,
  phone_digits,
  default_user_id,
  full_name,
  country,
  language_code,
  momo_provider,
  momo_number,
  momo_code,
  vehicle_type,
  is_driver,
  is_admin,
  rayon_chapter,
  rayon_points,
  rayon_tier,
  membership_number,
  joined_at
)
values
  (
    '+250788767816',
    '250788767816',
    '295cb4fe-8cd5-41ed-b01a-2f5a21b7a86e'::uuid,
    'Aline Mukamana',
    'RW',
    'en',
    'momo_rw',
    '+250788767816',
    '788816',
    'cab',
    true,
    true,
    'Kigali Central',
    1640,
    'silver',
    'RS-1968-KGL-816A',
    timestamptz '2026-02-14 09:30:00+00'
  ),
  (
    '+25075588248',
    '25075588248',
    '8dd330e3-3a5d-42ef-9ef2-0c8a55d55b01'::uuid,
    'Jean Claude Niyonsaba',
    'RW',
    'en',
    'momo_rw',
    '+25075588248',
    '558248',
    'moto',
    true,
    false,
    'Musanze Rayon Fans',
    920,
    'blue',
    'RS-1968-MUS-248J',
    timestamptz '2026-02-18 08:10:00+00'
  ),
  (
    '+25088817592',
    '25088817592',
    'b2a245df-527c-4cb8-b165-1afcb7db5f02'::uuid,
    'Diane Uwase',
    'RW',
    'rw',
    'momo_rw',
    '+25088817592',
    '817592',
    null,
    false,
    false,
    'Huye Blue Army',
    560,
    'blue',
    'RS-1968-HUY-592D',
    timestamptz '2026-02-22 14:45:00+00'
  ),
  (
    '+35677186193',
    '35677186193',
    'cf7caa5a-9d53-406a-8a1a-13f848fd4103'::uuid,
    'Matteo Borg',
    'MT',
    'en',
    'momo_mt',
    '+35677186193',
    '186193',
    null,
    false,
    false,
    'Europe Supporters',
    2140,
    'gold',
    'RS-1968-EU-193M',
    timestamptz '2026-02-25 16:00:00+00'
  );
update demo_user_seed seed
set user_id = auth_user.id
from auth.users auth_user
where auth_user.phone = seed.phone_digits
   or coalesce(auth_user.raw_user_meta_data ->> 'phone', '') = seed.phone_e164;
update demo_user_seed
set user_id = default_user_id
where user_id is null;
insert into auth.users (
  id,
  aud,
  role,
  encrypted_password,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at,
  phone,
  phone_confirmed_at,
  is_sso_user,
  is_anonymous
)
select
  seed.user_id,
  'authenticated',
  'authenticated',
  crypt(gen_random_uuid()::text, gen_salt('bf')),
  jsonb_build_object(
    'provider', 'phone',
    'providers', jsonb_build_array('phone'),
    'is_mock', true,
    'mock_batch', runtime.mock_batch
  ),
  jsonb_build_object(
    'phone', seed.phone_e164,
    'full_name', seed.full_name,
    'country', seed.country,
    'language_code', seed.language_code,
    'is_driver', seed.is_driver,
    'vehicle_type', seed.vehicle_type,
    'auth_strategy', 'custom_whatsapp_otp',
    'is_mock', true,
    'mock_batch', runtime.mock_batch
  ),
  seed.joined_at,
  now(),
  seed.phone_digits,
  now(),
  false,
  false
from demo_user_seed seed
cross join demo_runtime runtime
where not exists (
  select 1
  from auth.users existing
  where existing.id = seed.user_id
);
update auth.users auth_user
set
  aud = 'authenticated',
  role = 'authenticated',
  phone = seed.phone_digits,
  raw_app_meta_data = coalesce(auth_user.raw_app_meta_data, '{}'::jsonb) || jsonb_build_object(
    'provider', 'phone',
    'providers', jsonb_build_array('phone'),
    'is_mock', true,
    'mock_batch', runtime.mock_batch
  ),
  raw_user_meta_data = coalesce(auth_user.raw_user_meta_data, '{}'::jsonb) || jsonb_build_object(
    'phone', seed.phone_e164,
    'full_name', seed.full_name,
    'country', seed.country,
    'language_code', seed.language_code,
    'is_driver', seed.is_driver,
    'vehicle_type', seed.vehicle_type,
    'auth_strategy', 'custom_whatsapp_otp',
    'is_mock', true,
    'mock_batch', runtime.mock_batch
  ),
  phone_confirmed_at = coalesce(auth_user.phone_confirmed_at, now()),
  updated_at = now(),
  deleted_at = null
from demo_user_seed seed
cross join demo_runtime runtime
where auth_user.id = seed.user_id;
insert into auth.identities (
  id,
  user_id,
  identity_data,
  provider,
  provider_id,
  created_at,
  updated_at
)
select
  gen_random_uuid(),
  seed.user_id,
  jsonb_build_object(
    'sub', seed.user_id::text,
    'phone', seed.phone_digits,
    'email_verified', false,
    'phone_verified', true
  ),
  'phone',
  seed.user_id::text,
  seed.joined_at,
  now()
from demo_user_seed seed
on conflict (provider_id, provider) do update
set
  user_id = excluded.user_id,
  identity_data = excluded.identity_data,
  updated_at = excluded.updated_at;
insert into public.users (
  id,
  phone,
  full_name,
  country,
  language_code,
  momo_number,
  momo_provider,
  is_driver,
  vehicle_type,
  momo_code,
  is_admin,
  is_mock,
  mock_batch,
  created_at,
  updated_at
)
select
  seed.user_id,
  seed.phone_e164,
  seed.full_name,
  seed.country,
  seed.language_code,
  seed.momo_number,
  seed.momo_provider,
  seed.is_driver,
  seed.vehicle_type,
  seed.momo_code,
  seed.is_admin,
  true,
  runtime.mock_batch,
  seed.joined_at,
  now()
from demo_user_seed seed
cross join demo_runtime runtime
on conflict (id) do update
set
  phone = excluded.phone,
  full_name = excluded.full_name,
  country = excluded.country,
  language_code = excluded.language_code,
  momo_number = excluded.momo_number,
  momo_provider = excluded.momo_provider,
  is_driver = excluded.is_driver,
  vehicle_type = excluded.vehicle_type,
  momo_code = excluded.momo_code,
  is_admin = excluded.is_admin,
  is_mock = excluded.is_mock,
  mock_batch = excluded.mock_batch,
  updated_at = excluded.updated_at;
create temp table demo_group_seed (
  id uuid primary key,
  creator_phone text not null,
  name text not null,
  type text not null,
  visibility text not null,
  target_amount integer not null,
  monthly_contribution integer not null,
  description text,
  bank_partner text,
  momo_number text,
  receiving_momo_code text,
  route_type text,
  frequency text,
  country text not null,
  invite_code text not null,
  institution_id text,
  created_at timestamptz not null
) on commit drop;
insert into demo_group_seed (
  id,
  creator_phone,
  name,
  type,
  visibility,
  target_amount,
  monthly_contribution,
  description,
  bank_partner,
  momo_number,
  receiving_momo_code,
  route_type,
  frequency,
  country,
  invite_code,
  institution_id,
  created_at
)
values
  (
    '779d0cbe-3d60-4f09-bc2f-f7f0ea1f8701'::uuid,
    '+25075588248',
    'Kigali Market Circle',
    'saving',
    'public',
    300000,
    15000,
    'Weekly savings circle for market vendors balancing stock, school fees, and emergency cash flow.',
    'Urwego Finance',
    '+25075588248',
    '+25075588248',
    'phone_number',
    'weekly',
    'RW',
    'KGLM2026',
    'URWEGO-KGL-01',
    timestamptz '2026-02-20 09:00:00+00'
  ),
  (
    '63d5a62d-21d4-4662-b8cb-ae85e8f69402'::uuid,
    '+250788767816',
    'Diaspora Builders Pool',
    'community',
    'private',
    500000,
    30000,
    'Private support pool for travel, matchday plans, and family projects across Kigali and Malta.',
    'Urwego Finance',
    '+250788767816',
    '+250788767816',
    'phone_number',
    'monthly',
    'RW',
    'DBPL2026',
    'URWEGO-DIAS-02',
    timestamptz '2026-02-24 11:15:00+00'
  );
insert into public.groups (
  id,
  creator_id,
  name,
  type,
  visibility,
  amount,
  target_amount,
  country,
  monthly_contribution,
  description,
  bank_partner,
  momo_number,
  receiving_momo_code,
  receiving_momo_route_type,
  frequency,
  invite_code,
  institution_id,
  is_mock,
  mock_batch,
  created_at,
  updated_at
)
select
  group_seed.id,
  user_seed.user_id,
  group_seed.name,
  group_seed.type,
  group_seed.visibility,
  0,
  group_seed.target_amount,
  group_seed.country,
  group_seed.monthly_contribution,
  group_seed.description,
  group_seed.bank_partner,
  group_seed.momo_number,
  group_seed.receiving_momo_code,
  group_seed.route_type,
  group_seed.frequency,
  group_seed.invite_code,
  group_seed.institution_id,
  true,
  runtime.mock_batch,
  group_seed.created_at,
  now()
from demo_group_seed group_seed
join demo_user_seed user_seed on user_seed.phone_e164 = group_seed.creator_phone
cross join demo_runtime runtime
on conflict (id) do update
set
  creator_id = excluded.creator_id,
  name = excluded.name,
  type = excluded.type,
  visibility = excluded.visibility,
  target_amount = excluded.target_amount,
  country = excluded.country,
  monthly_contribution = excluded.monthly_contribution,
  description = excluded.description,
  bank_partner = excluded.bank_partner,
  momo_number = excluded.momo_number,
  receiving_momo_code = excluded.receiving_momo_code,
  receiving_momo_route_type = excluded.receiving_momo_route_type,
  frequency = excluded.frequency,
  invite_code = excluded.invite_code,
  institution_id = excluded.institution_id,
  is_mock = excluded.is_mock,
  mock_batch = excluded.mock_batch,
  updated_at = excluded.updated_at;
create temp table demo_group_member_seed (
  group_id uuid not null,
  phone_e164 text not null,
  display_name text not null,
  is_admin boolean not null,
  is_anonymous boolean not null,
  contribution_amount integer not null,
  joined_at timestamptz not null
) on commit drop;
insert into demo_group_member_seed values
  ('779d0cbe-3d60-4f09-bc2f-f7f0ea1f8701'::uuid, '+25075588248', 'Jean Claude Niyonsaba', true, false, 20000, timestamptz '2026-02-20 09:00:00+00'),
  ('779d0cbe-3d60-4f09-bc2f-f7f0ea1f8701'::uuid, '+250788767816', 'Aline Mukamana', false, false, 30000, timestamptz '2026-02-21 10:00:00+00'),
  ('779d0cbe-3d60-4f09-bc2f-f7f0ea1f8701'::uuid, '+25088817592', 'Diane Uwase', false, false, 15000, timestamptz '2026-02-22 08:30:00+00'),
  ('63d5a62d-21d4-4662-b8cb-ae85e8f69402'::uuid, '+250788767816', 'Aline Mukamana', true, false, 60000, timestamptz '2026-02-24 11:15:00+00'),
  ('63d5a62d-21d4-4662-b8cb-ae85e8f69402'::uuid, '+35677186193', 'Matteo Borg', false, false, 45000, timestamptz '2026-02-25 16:30:00+00');
insert into public.group_members (
  group_id,
  user_id,
  display_name,
  is_admin,
  is_anonymous,
  contribution_amount,
  joined_at,
  is_mock,
  mock_batch
)
select
  member_seed.group_id,
  user_seed.user_id,
  member_seed.display_name,
  member_seed.is_admin,
  member_seed.is_anonymous,
  member_seed.contribution_amount,
  member_seed.joined_at,
  true,
  runtime.mock_batch
from demo_group_member_seed member_seed
join demo_user_seed user_seed on user_seed.phone_e164 = member_seed.phone_e164
cross join demo_runtime runtime
on conflict (group_id, user_id) do update
set
  display_name = excluded.display_name,
  is_admin = excluded.is_admin,
  is_anonymous = excluded.is_anonymous,
  contribution_amount = excluded.contribution_amount,
  joined_at = excluded.joined_at,
  is_mock = excluded.is_mock,
  mock_batch = excluded.mock_batch;
create temp table demo_group_contribution_seed (
  id uuid primary key,
  group_id uuid not null,
  phone_e164 text not null,
  amount integer not null,
  status text not null,
  created_at timestamptz not null,
  momo_reference text not null
) on commit drop;
insert into demo_group_contribution_seed values
  ('b49c1411-b152-40a5-b6ca-0e87970f9301'::uuid, '779d0cbe-3d60-4f09-bc2f-f7f0ea1f8701'::uuid, '+25075588248', 20000, 'confirmed', timestamptz '2026-03-02 07:55:00+00', 'GC-KMC-20260302-01'),
  ('dc62629f-7482-4d26-a0ca-397e6047ad02'::uuid, '779d0cbe-3d60-4f09-bc2f-f7f0ea1f8701'::uuid, '+250788767816', 15000, 'confirmed', timestamptz '2026-03-05 09:05:00+00', 'GC-KMC-20260305-01'),
  ('9d5f4876-6ed1-4d1d-9da5-4d57a0c13b03'::uuid, '779d0cbe-3d60-4f09-bc2f-f7f0ea1f8701'::uuid, '+25088817592', 15000, 'confirmed', timestamptz '2026-03-06 12:20:00+00', 'GC-KMC-20260306-01'),
  ('7d57d2a9-c482-4d88-a32f-a3e80e5cf304'::uuid, '779d0cbe-3d60-4f09-bc2f-f7f0ea1f8701'::uuid, '+250788767816', 15000, 'confirmed', timestamptz '2026-03-09 06:50:00+00', 'GC-KMC-20260309-01'),
  ('4da51f5f-bdf0-40fe-af53-27fe80f6a305'::uuid, '63d5a62d-21d4-4662-b8cb-ae85e8f69402'::uuid, '+250788767816', 30000, 'confirmed', timestamptz '2026-03-03 10:40:00+00', 'GC-DBP-20260303-01'),
  ('7fd95c32-5d78-4958-bf65-f5587f441f06'::uuid, '63d5a62d-21d4-4662-b8cb-ae85e8f69402'::uuid, '+35677186193', 45000, 'confirmed', timestamptz '2026-03-07 18:15:00+00', 'GC-DBP-20260307-01'),
  ('07b9e6ae-d542-49ed-a8a6-f5444e8a2c07'::uuid, '63d5a62d-21d4-4662-b8cb-ae85e8f69402'::uuid, '+250788767816', 30000, 'confirmed', timestamptz '2026-03-10 08:45:00+00', 'GC-DBP-20260310-01');
insert into public.group_contributions (
  id,
  group_id,
  user_id,
  amount,
  status,
  created_at,
  momo_reference,
  is_mock,
  mock_batch
)
select
  contribution_seed.id,
  contribution_seed.group_id,
  user_seed.user_id,
  contribution_seed.amount,
  contribution_seed.status,
  contribution_seed.created_at,
  contribution_seed.momo_reference,
  true,
  runtime.mock_batch
from demo_group_contribution_seed contribution_seed
join demo_user_seed user_seed on user_seed.phone_e164 = contribution_seed.phone_e164
cross join demo_runtime runtime
on conflict (id) do update
set
  group_id = excluded.group_id,
  user_id = excluded.user_id,
  amount = excluded.amount,
  status = excluded.status,
  created_at = excluded.created_at,
  momo_reference = excluded.momo_reference,
  is_mock = excluded.is_mock,
  mock_batch = excluded.mock_batch;
update public.groups group_row
set
  amount = coalesce(summary.confirmed_total, 0),
  updated_at = now()
from (
  select
    group_id,
    sum(amount)::integer as confirmed_total
  from public.group_contributions
  where is_mock = true
    and mock_batch = (select mock_batch from demo_runtime)
    and status = 'confirmed'
  group by group_id
) summary
where group_row.id = summary.group_id;
create temp table demo_driver_profile_seed (
  phone_e164 text primary key,
  vehicle_type text not null,
  plate_number text not null,
  base_location text not null,
  vehicle_status text not null,
  is_online boolean not null,
  rating double precision not null,
  trips_done integer not null,
  trips_used_this_month integer not null,
  latitude double precision not null,
  longitude double precision not null,
  vehicle_emoji text not null,
  created_at timestamptz not null
) on commit drop;
insert into demo_driver_profile_seed values
  ('+250788767816', 'cab', 'RAB 214K', 'Kimironko', 'verified', false, 4.8, 19, 6, -1.9462, 30.1260, '🚗', timestamptz '2026-02-26 07:20:00+00'),
  ('+25075588248', 'moto', 'RAD 118M', 'Nyabugogo', 'verified', true, 4.9, 47, 9, -1.9457, 30.0560, '🛺', timestamptz '2026-02-24 06:40:00+00');
insert into public.driver_profiles (
  user_id,
  vehicle_type,
  plate_number,
  base_location,
  vehicle_status,
  is_online,
  rating,
  trips_done,
  trips_used_this_month,
  latitude,
  longitude,
  location,
  vehicle_emoji,
  is_mock,
  mock_batch,
  created_at,
  updated_at
)
select
  user_seed.user_id,
  profile_seed.vehicle_type,
  profile_seed.plate_number,
  profile_seed.base_location,
  profile_seed.vehicle_status,
  profile_seed.is_online,
  profile_seed.rating,
  profile_seed.trips_done,
  profile_seed.trips_used_this_month,
  profile_seed.latitude,
  profile_seed.longitude,
  st_setsrid(st_makepoint(profile_seed.longitude, profile_seed.latitude), 4326)::geography,
  profile_seed.vehicle_emoji,
  true,
  runtime.mock_batch,
  profile_seed.created_at,
  now()
from demo_driver_profile_seed profile_seed
join demo_user_seed user_seed on user_seed.phone_e164 = profile_seed.phone_e164
cross join demo_runtime runtime
on conflict (user_id) do update
set
  vehicle_type = excluded.vehicle_type,
  plate_number = excluded.plate_number,
  base_location = excluded.base_location,
  vehicle_status = excluded.vehicle_status,
  is_online = excluded.is_online,
  rating = excluded.rating,
  trips_done = excluded.trips_done,
  trips_used_this_month = excluded.trips_used_this_month,
  latitude = excluded.latitude,
  longitude = excluded.longitude,
  location = excluded.location,
  vehicle_emoji = excluded.vehicle_emoji,
  is_mock = excluded.is_mock,
  mock_batch = excluded.mock_batch,
  updated_at = excluded.updated_at;
create temp table demo_subscription_seed (
  id uuid primary key,
  phone_e164 text not null,
  plan text not null,
  amount integer not null,
  status text not null,
  started_at timestamptz not null,
  expires_at timestamptz not null,
  plan_id text not null,
  plan_name text not null,
  amount_rwf integer not null,
  momo_reference text not null
) on commit drop;
insert into demo_subscription_seed values
  ('16f5909e-a5a0-4eaf-bfcf-676a113e8401'::uuid, '+250788767816', 'cab_other', 25000, 'active', timestamptz '2026-03-01 07:00:00+00', timestamptz '2026-03-31 23:59:59+00', 'cab_other', 'Cab Monthly Unlimited', 25000, 'DRV-SUB-ALINE-202603'),
  ('8b8b40c7-5287-4d45-94bb-e23ecf1ea402'::uuid, '+25075588248', 'moto_taxi', 15000, 'active', timestamptz '2026-03-01 07:00:00+00', timestamptz '2026-03-31 23:59:59+00', 'moto_taxi', 'Moto Taxi Monthly Unlimited', 15000, 'DRV-SUB-JC-202603');
insert into public.driver_subscriptions (
  id,
  driver_id,
  plan,
  amount,
  status,
  started_at,
  expires_at,
  created_at,
  plan_id,
  plan_name,
  amount_rwf,
  momo_reference,
  updated_at,
  is_mock,
  mock_batch
)
select
  subscription_seed.id,
  user_seed.user_id,
  subscription_seed.plan,
  subscription_seed.amount,
  subscription_seed.status,
  subscription_seed.started_at,
  subscription_seed.expires_at,
  subscription_seed.started_at,
  subscription_seed.plan_id,
  subscription_seed.plan_name,
  subscription_seed.amount_rwf,
  subscription_seed.momo_reference,
  now(),
  true,
  runtime.mock_batch
from demo_subscription_seed subscription_seed
join demo_user_seed user_seed on user_seed.phone_e164 = subscription_seed.phone_e164
cross join demo_runtime runtime
on conflict (id) do update
set
  driver_id = excluded.driver_id,
  plan = excluded.plan,
  amount = excluded.amount,
  status = excluded.status,
  started_at = excluded.started_at,
  expires_at = excluded.expires_at,
  plan_id = excluded.plan_id,
  plan_name = excluded.plan_name,
  amount_rwf = excluded.amount_rwf,
  momo_reference = excluded.momo_reference,
  updated_at = excluded.updated_at,
  is_mock = excluded.is_mock,
  mock_batch = excluded.mock_batch;
create temp table demo_trip_seed (
  id uuid primary key,
  phone_e164 text not null,
  driver_phone_e164 text,
  from_location text not null,
  to_location text not null,
  departure_at timestamptz not null,
  return_at timestamptz,
  vehicle_type text not null,
  vehicle_emoji text not null,
  seats integer not null,
  trip_type text not null,
  status text not null,
  role text not null,
  contact_phone text not null,
  contact_name text not null,
  whatsapp_number text not null,
  from_lat double precision not null,
  from_lng double precision not null,
  to_lat double precision not null,
  to_lng double precision not null,
  repeat_days text[],
  price_note text,
  is_driver_return_trip boolean not null,
  created_at timestamptz not null
) on commit drop;
insert into demo_trip_seed values
  (
    '7f6a47d7-b60d-4d48-84e2-c75e2f3bc501'::uuid,
    '+250788767816',
    '+25075588248',
    'Remera Taxi Park',
    'Kigali Heights',
    timestamptz '2026-03-12 06:30:00+00',
    null,
    'cab',
    '🚗',
    1,
    'passenger',
    'open',
    'PASSENGER',
    '+250788767816',
    'Aline Mukamana',
    '+250788767816',
    -1.9444,
    30.1139,
    -1.9516,
    30.0924,
    null,
    'Shared fare from Remera after school drop-off.',
    false,
    timestamptz '2026-03-11 05:50:00+00'
  ),
  (
    '6b3626c7-b4cd-4a4c-9495-a6ee4c907702'::uuid,
    '+250788767816',
    null,
    'Kimironko',
    'Kacyiru',
    timestamptz '2026-03-13 07:15:00+00',
    null,
    'cab',
    '🚗',
    2,
    'passenger',
    'open',
    'PASSENGER',
    '+250788767816',
    'Aline Mukamana',
    '+250788767816',
    -1.9396,
    30.1418,
    -1.9440,
    30.0932,
    array['Mon', 'Wed', 'Fri']::text[],
    'Regular morning commute before client meetings.',
    false,
    timestamptz '2026-03-11 06:10:00+00'
  ),
  (
    '6df503b1-2cfd-4300-9426-8a3fa53b3303'::uuid,
    '+25075588248',
    '+25075588248',
    'Nyabugogo Bus Park',
    'Kigali Convention Centre',
    timestamptz '2026-03-11 16:45:00+00',
    timestamptz '2026-03-11 18:30:00+00',
    'moto',
    '🛺',
    1,
    'driver_return',
    'open',
    'DRIVER',
    '+25075588248',
    'Jean Claude Niyonsaba',
    '+25075588248',
    -1.9455,
    30.0564,
    -1.9540,
    30.0965,
    null,
    'Available after a drop near downtown Kigali.',
    true,
    timestamptz '2026-03-11 06:25:00+00'
  ),
  (
    '097f8eb7-cd53-4d8d-ad30-cf7fb86fa504'::uuid,
    '+25088817592',
    null,
    'Huye Bus Park',
    'Kigali CBD',
    timestamptz '2026-03-14 09:00:00+00',
    null,
    'cab',
    '🚗',
    1,
    'passenger',
    'open',
    'PASSENGER',
    '+25088817592',
    'Diane Uwase',
    '+25088817592',
    -2.5966,
    29.7396,
    -1.9441,
    30.0619,
    null,
    'Weekend trip to Kigali for supplier visits.',
    false,
    timestamptz '2026-03-11 06:40:00+00'
  );
insert into public.mobility_trips (
  id,
  user_id,
  from_location,
  to_location,
  departure_at,
  return_at,
  vehicle_type,
  vehicle_emoji,
  seats,
  trip_type,
  status,
  role,
  contact_phone,
  contact_name,
  whatsapp_number,
  from_lat,
  from_lng,
  to_lat,
  to_lng,
  travel_time,
  repeat_days,
  price_note,
  is_driver_return_trip,
  driver_id,
  origin_geo,
  created_at,
  updated_at,
  is_mock,
  mock_batch
)
select
  trip_seed.id,
  user_seed.user_id,
  trip_seed.from_location,
  trip_seed.to_location,
  trip_seed.departure_at,
  trip_seed.return_at,
  trip_seed.vehicle_type,
  trip_seed.vehicle_emoji,
  trip_seed.seats,
  trip_seed.trip_type,
  trip_seed.status,
  trip_seed.role,
  trip_seed.contact_phone,
  trip_seed.contact_name,
  trip_seed.whatsapp_number,
  trip_seed.from_lat,
  trip_seed.from_lng,
  trip_seed.to_lat,
  trip_seed.to_lng,
  trip_seed.departure_at,
  trip_seed.repeat_days,
  trip_seed.price_note,
  trip_seed.is_driver_return_trip,
  driver_seed.user_id,
  st_setsrid(st_makepoint(trip_seed.from_lng, trip_seed.from_lat), 4326)::geography,
  trip_seed.created_at,
  now(),
  true,
  runtime.mock_batch
from demo_trip_seed trip_seed
join demo_user_seed user_seed on user_seed.phone_e164 = trip_seed.phone_e164
left join demo_user_seed driver_seed on driver_seed.phone_e164 = trip_seed.driver_phone_e164
cross join demo_runtime runtime
on conflict (id) do update
set
  user_id = excluded.user_id,
  from_location = excluded.from_location,
  to_location = excluded.to_location,
  departure_at = excluded.departure_at,
  return_at = excluded.return_at,
  vehicle_type = excluded.vehicle_type,
  vehicle_emoji = excluded.vehicle_emoji,
  seats = excluded.seats,
  trip_type = excluded.trip_type,
  status = excluded.status,
  role = excluded.role,
  contact_phone = excluded.contact_phone,
  contact_name = excluded.contact_name,
  whatsapp_number = excluded.whatsapp_number,
  from_lat = excluded.from_lat,
  from_lng = excluded.from_lng,
  to_lat = excluded.to_lat,
  to_lng = excluded.to_lng,
  travel_time = excluded.travel_time,
  repeat_days = excluded.repeat_days,
  price_note = excluded.price_note,
  is_driver_return_trip = excluded.is_driver_return_trip,
  driver_id = excluded.driver_id,
  origin_geo = excluded.origin_geo,
  updated_at = excluded.updated_at,
  is_mock = excluded.is_mock,
  mock_batch = excluded.mock_batch;
create temp table demo_credit_score_seed (
  id uuid primary key,
  phone_e164 text not null,
  score integer not null,
  saving_consistency integer not null,
  group_participation integer not null,
  payment_history integer not null,
  community_activity integer not null,
  recorded_at timestamptz not null
) on commit drop;
insert into demo_credit_score_seed values
  ('44110119-5c17-45eb-82cf-a953d993cc01'::uuid, '+250788767816', 612, 58, 60, 65, 56, timestamptz '2025-10-31 12:00:00+00'),
  ('1d1f66cf-8744-4c4a-8717-2ca05c3f4202'::uuid, '+250788767816', 648, 62, 64, 68, 61, timestamptz '2025-11-30 12:00:00+00'),
  ('376f0d7a-f9e3-4051-a89f-a4208ea4ef03'::uuid, '+250788767816', 681, 67, 70, 72, 65, timestamptz '2025-12-31 12:00:00+00'),
  ('3ac85a63-60b2-4ddb-a69b-8309d83a2304'::uuid, '+250788767816', 709, 71, 74, 75, 70, timestamptz '2026-01-31 12:00:00+00'),
  ('6389ff67-e5d7-4121-b215-71df16b78d05'::uuid, '+250788767816', 731, 76, 78, 80, 73, timestamptz '2026-02-28 12:00:00+00'),
  ('94ab61a1-5e3d-4bdf-af8c-4a0854688e06'::uuid, '+250788767816', 742, 78, 80, 83, 76, timestamptz '2026-03-10 12:00:00+00'),
  ('cc1a395f-1dd6-4e88-9252-43ec8549cd07'::uuid, '+25075588248', 655, 60, 66, 71, 62, timestamptz '2026-03-10 12:00:00+00'),
  ('0fd7384d-c0af-4b3c-a6fb-8f0a8d662808'::uuid, '+25088817592', 601, 57, 59, 63, 58, timestamptz '2026-03-10 12:00:00+00'),
  ('07dc6f0d-4f65-4fb1-bcf6-1fe4fbcb3309'::uuid, '+35677186193', 688, 66, 62, 74, 69, timestamptz '2026-03-10 12:00:00+00');
insert into public.credit_scores (
  id,
  user_id,
  score,
  saving_consistency,
  group_participation,
  payment_history,
  community_activity,
  recorded_at,
  is_mock,
  mock_batch
)
select
  score_seed.id,
  user_seed.user_id,
  score_seed.score,
  score_seed.saving_consistency,
  score_seed.group_participation,
  score_seed.payment_history,
  score_seed.community_activity,
  score_seed.recorded_at,
  true,
  runtime.mock_batch
from demo_credit_score_seed score_seed
join demo_user_seed user_seed on user_seed.phone_e164 = score_seed.phone_e164
cross join demo_runtime runtime
on conflict (id) do update
set
  user_id = excluded.user_id,
  score = excluded.score,
  saving_consistency = excluded.saving_consistency,
  group_participation = excluded.group_participation,
  payment_history = excluded.payment_history,
  community_activity = excluded.community_activity,
  recorded_at = excluded.recorded_at,
  is_mock = excluded.is_mock,
  mock_batch = excluded.mock_batch;
create temp table demo_momo_seed (
  raw_id uuid primary key,
  parsed_id uuid not null,
  ledger_id uuid not null,
  reconciliation_id uuid not null,
  phone_e164 text not null,
  device_message_key text not null,
  sender text not null,
  sms_body text not null,
  provider text not null,
  country text not null,
  sms_received_at timestamptz not null,
  detected_tx_type text,
  detected_amount integer not null,
  detected_tx_id text not null,
  ingestion_source text not null,
  tx_direction text not null,
  tx_type text,
  tx_datetime timestamptz not null,
  payer_name text,
  payer_number_last3 text,
  payer_number_full text,
  payee_name text,
  payee_number_or_code text,
  merchant_code text,
  fee_amount integer,
  balance_after integer,
  narrative text,
  target_table text,
  target_record_id uuid,
  entry_type text not null,
  ledger_scope text not null,
  description text,
  match_type text not null,
  confidence numeric not null,
  notes text
) on commit drop;
insert into demo_momo_seed values
  (
    '8e733d26-2678-42bf-95b5-2b611e1db701'::uuid,
    '5aadad87-15dc-43d1-8fd8-e522fb4fa701'::uuid,
    'ac6c3734-f19e-4014-a8ea-d7e4f367e701'::uuid,
    '1ea69618-b232-4cfe-a8dc-5fdc6c062701'::uuid,
    '+250788767816',
    'aline-demo-sms-01',
    'MOMO',
    'TxId: 982311. Payment of 15000 RWF to Kigali Market Circle was completed.',
    'mtn_rw',
    'RW',
    timestamptz '2026-03-09 06:52:00+00',
    'merchant_payment',
    15000,
    '982311',
    'demo_seed',
    'debit',
    'merchant_payment',
    timestamptz '2026-03-09 06:50:00+00',
    'Aline Mukamana',
    '816',
    '250788767816',
    'Kigali Market Circle',
    '25075588248',
    null,
    0,
    412000,
    'Weekly savings contribution.',
    'group_contributions',
    '7d57d2a9-c482-4d88-a32f-a3e80e5cf304'::uuid,
    'debit',
    'groups',
    'Confirmed group contribution payment.',
    'reference',
    0.99,
    'Matched on MoMo reference and amount.'
  ),
  (
    '91a1a3cc-cf88-4d9d-a7b0-4ef733d47702'::uuid,
    'fa5c44ea-e9d8-4cb8-b17f-cbba7e814702'::uuid,
    'ef47f2d4-8d00-44d1-a96a-7c0b3b885702'::uuid,
    '2bcbb4a0-33d6-4851-8eb9-b91c1c0f2f02'::uuid,
    '+250788767816',
    'aline-demo-sms-02',
    'MOMO',
    'TxId: 982355. Payment of 25000 RWF to Cool Mobility Subscription was completed.',
    'mtn_rw',
    'RW',
    timestamptz '2026-03-03 07:04:00+00',
    'subscription',
    25000,
    '982355',
    'demo_seed',
    'debit',
    'bill_payment',
    timestamptz '2026-03-03 07:00:00+00',
    'Aline Mukamana',
    '816',
    '250788767816',
    'Cool Mobility',
    'CAB-UNLIMITED',
    null,
    0,
    427000,
    'Cab monthly subscription.',
    'driver_subscriptions',
    '16f5909e-a5a0-4eaf-bfcf-676a113e8401'::uuid,
    'debit',
    'mobility',
    'Subscription charge for driver plan.',
    'reference',
    0.99,
    'Matched on driver subscription reference.'
  ),
  (
    '2eae0c2e-824f-470d-b74f-e35d2b877703'::uuid,
    '6b5675f0-39e7-4a31-b91b-32d3f5877703'::uuid,
    'd829c570-5252-4c3b-95d8-6b2de703e703'::uuid,
    '28d7af92-17c7-49d3-a98d-4434f28b7f03'::uuid,
    '+250788767816',
    'aline-demo-sms-03',
    'MOMO',
    'TxId: 982401. Payment of 12000 RWF to Fan Kit Subsidy Program was completed.',
    'mtn_rw',
    'RW',
    timestamptz '2026-03-06 17:13:00+00',
    'initiative_support',
    12000,
    '982401',
    'demo_seed',
    'debit',
    'merchant_payment',
    timestamptz '2026-03-06 17:10:00+00',
    'Aline Mukamana',
    '816',
    '250788767816',
    'Rayon Sports FC',
    'RS-SUPPORT-ALINE-01',
    null,
    0,
    415000,
    'Rayon fan initiative support.',
    'rs_initiative_contributions',
    '2ae5d2c7-f4ea-4458-b93c-73208cdc7301'::uuid,
    'debit',
    'rayon_support',
    'Confirmed initiative contribution.',
    'reference',
    0.99,
    'Matched on initiative contribution reference.'
  ),
  (
    '14d53408-0671-4358-a95e-0f3d2d887704'::uuid,
    'd9c0578f-96cb-49e3-ac3e-3c080442c704'::uuid,
    '8df851c1-4122-4f94-9d25-d8eca310c704'::uuid,
    'b60e2fc5-cbdd-4d62-a1d1-bad33f438f04'::uuid,
    '+250788767816',
    'aline-demo-sms-04',
    'MOMO',
    'TxId: 982456. Payment of 18000 RWF to Rayon Sports ticket office was completed.',
    'mtn_rw',
    'RW',
    timestamptz '2026-03-10 08:34:00+00',
    'ticket_purchase',
    18000,
    '982456',
    'demo_seed',
    'debit',
    'merchant_payment',
    timestamptz '2026-03-10 08:30:00+00',
    'Aline Mukamana',
    '816',
    '250788767816',
    'Rayon Sports FC',
    'RS-TICKET-ALINE-01',
    null,
    0,
    397000,
    'Match ticket purchase.',
    'rs_tickets',
    '3e5046e7-1ffd-44ee-9550-627fb5f17701'::uuid,
    'debit',
    'rayon_ticket',
    'Confirmed ticket purchase.',
    'reference',
    0.99,
    'Matched on ticket payment reference.'
  ),
  (
    '0ad57c97-d2e0-42f6-8ad5-431b77037705'::uuid,
    '6a89b544-ae43-46a9-a6f8-01bfca937705'::uuid,
    '15afe68a-13de-48c5-a6f3-ad104386c705'::uuid,
    'a9941f9f-0411-4c00-af3d-067f4fbba905'::uuid,
    '+250788767816',
    'aline-demo-sms-05',
    'MOMO',
    'TxId: 982503. Payment of 65000 RWF to Rayon Shop was completed.',
    'mtn_rw',
    'RW',
    timestamptz '2026-03-10 15:29:00+00',
    'shop_purchase',
    65000,
    '982503',
    'demo_seed',
    'debit',
    'merchant_payment',
    timestamptz '2026-03-10 15:25:00+00',
    'Aline Mukamana',
    '816',
    '250788767816',
    'Rayon Shop',
    'RS-SHOP-ALINE-01',
    null,
    0,
    332000,
    'Shop order for kit and scarf.',
    'rs_shop_orders',
    '7b74fa3c-4fd2-42dd-82eb-8822f86ec601'::uuid,
    'debit',
    'rayon_shop',
    'Confirmed shop order payment.',
    'reference',
    0.99,
    'Matched on shop order reference.'
  );
insert into public.momo_sms_raw (
  id,
  user_id,
  device_message_key,
  sender,
  sms_body,
  provider,
  country,
  sms_received_at,
  detected_tx_type,
  detected_amount,
  detected_tx_id,
  ingestion_source,
  parse_status,
  created_at,
  updated_at,
  is_mock,
  mock_batch
)
select
  momo_seed.raw_id,
  user_seed.user_id,
  momo_seed.device_message_key,
  momo_seed.sender,
  momo_seed.sms_body,
  momo_seed.provider,
  momo_seed.country,
  momo_seed.sms_received_at,
  momo_seed.detected_tx_type,
  momo_seed.detected_amount,
  momo_seed.detected_tx_id,
  momo_seed.ingestion_source,
  'parsed',
  momo_seed.sms_received_at,
  now(),
  true,
  runtime.mock_batch
from demo_momo_seed momo_seed
join demo_user_seed user_seed on user_seed.phone_e164 = momo_seed.phone_e164
cross join demo_runtime runtime
on conflict (user_id, device_message_key) do update
set
  sender = excluded.sender,
  sms_body = excluded.sms_body,
  provider = excluded.provider,
  country = excluded.country,
  sms_received_at = excluded.sms_received_at,
  detected_tx_type = excluded.detected_tx_type,
  detected_amount = excluded.detected_amount,
  detected_tx_id = excluded.detected_tx_id,
  ingestion_source = excluded.ingestion_source,
  parse_status = excluded.parse_status,
  updated_at = excluded.updated_at,
  is_mock = excluded.is_mock,
  mock_batch = excluded.mock_batch;
insert into public.momo_sms_parsed (
  id,
  raw_sms_id,
  user_id,
  parser_provider,
  parser_model,
  parse_status,
  confidence,
  tx_direction,
  tx_type,
  momo_tx_id,
  amount,
  currency,
  tx_date,
  tx_time,
  tx_datetime,
  payer_name,
  payer_number_last3,
  payer_number_full,
  payee_name,
  payee_number_or_code,
  merchant_code,
  fee_amount,
  balance_after,
  narrative,
  structured_data,
  created_at,
  updated_at,
  is_mock,
  mock_batch
)
select
  momo_seed.parsed_id,
  momo_seed.raw_id,
  user_seed.user_id,
  'demo_seed',
  'manual-v1',
  'parsed',
  momo_seed.confidence,
  momo_seed.tx_direction,
  momo_seed.tx_type,
  momo_seed.detected_tx_id,
  momo_seed.detected_amount,
  'RWF',
  momo_seed.tx_datetime::date,
  momo_seed.tx_datetime::time,
  momo_seed.tx_datetime,
  momo_seed.payer_name,
  momo_seed.payer_number_last3,
  momo_seed.payer_number_full,
  momo_seed.payee_name,
  momo_seed.payee_number_or_code,
  momo_seed.merchant_code,
  momo_seed.fee_amount,
  momo_seed.balance_after,
  momo_seed.narrative,
  jsonb_build_object(
    'seed', true,
    'target_table', momo_seed.target_table,
    'target_record_id', momo_seed.target_record_id
  ),
  momo_seed.sms_received_at,
  now(),
  true,
  runtime.mock_batch
from demo_momo_seed momo_seed
join demo_user_seed user_seed on user_seed.phone_e164 = momo_seed.phone_e164
cross join demo_runtime runtime
on conflict (raw_sms_id) do update
set
  user_id = excluded.user_id,
  parser_provider = excluded.parser_provider,
  parser_model = excluded.parser_model,
  parse_status = excluded.parse_status,
  confidence = excluded.confidence,
  tx_direction = excluded.tx_direction,
  tx_type = excluded.tx_type,
  momo_tx_id = excluded.momo_tx_id,
  amount = excluded.amount,
  currency = excluded.currency,
  tx_date = excluded.tx_date,
  tx_time = excluded.tx_time,
  tx_datetime = excluded.tx_datetime,
  payer_name = excluded.payer_name,
  payer_number_last3 = excluded.payer_number_last3,
  payer_number_full = excluded.payer_number_full,
  payee_name = excluded.payee_name,
  payee_number_or_code = excluded.payee_number_or_code,
  merchant_code = excluded.merchant_code,
  fee_amount = excluded.fee_amount,
  balance_after = excluded.balance_after,
  narrative = excluded.narrative,
  structured_data = excluded.structured_data,
  updated_at = excluded.updated_at,
  is_mock = excluded.is_mock,
  mock_batch = excluded.mock_batch;
insert into public.momo_ledger_entries (
  id,
  parsed_sms_id,
  user_id,
  entry_type,
  ledger_scope,
  ledger_status,
  amount,
  currency,
  tx_datetime,
  external_reference,
  target_table,
  target_record_id,
  description,
  metadata,
  created_at,
  updated_at,
  is_mock,
  mock_batch
)
select
  momo_seed.ledger_id,
  momo_seed.parsed_id,
  user_seed.user_id,
  momo_seed.entry_type,
  momo_seed.ledger_scope,
  'posted',
  momo_seed.detected_amount,
  'RWF',
  momo_seed.tx_datetime,
  momo_seed.detected_tx_id,
  momo_seed.target_table,
  momo_seed.target_record_id,
  momo_seed.description,
  jsonb_build_object('seed', true, 'momo_reference', momo_seed.detected_tx_id),
  momo_seed.sms_received_at,
  now(),
  true,
  runtime.mock_batch
from demo_momo_seed momo_seed
join demo_user_seed user_seed on user_seed.phone_e164 = momo_seed.phone_e164
cross join demo_runtime runtime
on conflict (parsed_sms_id) do update
set
  user_id = excluded.user_id,
  entry_type = excluded.entry_type,
  ledger_scope = excluded.ledger_scope,
  ledger_status = excluded.ledger_status,
  amount = excluded.amount,
  currency = excluded.currency,
  tx_datetime = excluded.tx_datetime,
  external_reference = excluded.external_reference,
  target_table = excluded.target_table,
  target_record_id = excluded.target_record_id,
  description = excluded.description,
  metadata = excluded.metadata,
  updated_at = excluded.updated_at,
  is_mock = excluded.is_mock,
  mock_batch = excluded.mock_batch;
insert into public.momo_reconciliations (
  id,
  parsed_sms_id,
  user_id,
  target_table,
  target_record_id,
  match_type,
  match_status,
  confidence,
  notes,
  metadata,
  reconciled_at,
  created_at,
  updated_at,
  is_mock,
  mock_batch
)
select
  momo_seed.reconciliation_id,
  momo_seed.parsed_id,
  user_seed.user_id,
  momo_seed.target_table,
  momo_seed.target_record_id,
  momo_seed.match_type,
  'matched',
  momo_seed.confidence,
  momo_seed.notes,
  jsonb_build_object('seed', true),
  momo_seed.tx_datetime,
  momo_seed.sms_received_at,
  now(),
  true,
  runtime.mock_batch
from demo_momo_seed momo_seed
join demo_user_seed user_seed on user_seed.phone_e164 = momo_seed.phone_e164
cross join demo_runtime runtime
on conflict (parsed_sms_id) do update
set
  user_id = excluded.user_id,
  target_table = excluded.target_table,
  target_record_id = excluded.target_record_id,
  match_type = excluded.match_type,
  match_status = excluded.match_status,
  confidence = excluded.confidence,
  notes = excluded.notes,
  metadata = excluded.metadata,
  reconciled_at = excluded.reconciled_at,
  updated_at = excluded.updated_at,
  is_mock = excluded.is_mock,
  mock_batch = excluded.mock_batch;
create temp table demo_status_seed (
  phone_e164 text primary key,
  total_points integer not null,
  tier text not null,
  current_streak integer not null,
  longest_streak integer not null,
  streak_grace_remaining integer not null,
  season_points integer not null,
  rank_hint integer not null
) on commit drop;
insert into demo_status_seed values
  ('+250788767816', 1185, 'silver', 6, 9, 1, 175, 2),
  ('+25075588248', 640, 'blue', 4, 6, 1, 92, 3),
  ('+25088817592', 420, 'blue', 2, 4, 1, 58, 4),
  ('+35677186193', 1380, 'silver', 5, 7, 1, 210, 1);
insert into public.cool_status (
  user_id,
  total_points,
  tier,
  current_streak,
  longest_streak,
  streak_grace_remaining,
  season_points,
  active_season_id,
  updated_at,
  created_at,
  is_mock,
  mock_batch
)
select
  user_seed.user_id,
  status_seed.total_points,
  status_seed.tier,
  status_seed.current_streak,
  status_seed.longest_streak,
  status_seed.streak_grace_remaining,
  status_seed.season_points,
  runtime.active_cool_season_id,
  now(),
  user_seed.joined_at,
  true,
  runtime.mock_batch
from demo_status_seed status_seed
join demo_user_seed user_seed on user_seed.phone_e164 = status_seed.phone_e164
cross join demo_runtime runtime
on conflict (user_id) do update
set
  total_points = excluded.total_points,
  tier = excluded.tier,
  current_streak = excluded.current_streak,
  longest_streak = excluded.longest_streak,
  streak_grace_remaining = excluded.streak_grace_remaining,
  season_points = excluded.season_points,
  active_season_id = excluded.active_season_id,
  updated_at = excluded.updated_at,
  is_mock = excluded.is_mock,
  mock_batch = excluded.mock_batch;
insert into public.season_memberships (
  season_id,
  user_id,
  season_points,
  rank_hint,
  created_at,
  updated_at,
  is_mock,
  mock_batch
)
select
  runtime.season_definition_id,
  user_seed.user_id,
  status_seed.season_points,
  status_seed.rank_hint,
  user_seed.joined_at,
  now(),
  true,
  runtime.mock_batch
from demo_status_seed status_seed
join demo_user_seed user_seed on user_seed.phone_e164 = status_seed.phone_e164
cross join demo_runtime runtime
on conflict (season_id, user_id) do update
set
  season_points = excluded.season_points,
  rank_hint = excluded.rank_hint,
  updated_at = excluded.updated_at,
  is_mock = excluded.is_mock,
  mock_batch = excluded.mock_batch;
create temp table demo_event_seed (
  id uuid primary key,
  phone_e164 text not null,
  event_type text not null,
  source_id text,
  points_awarded integer not null,
  metadata jsonb,
  referrer_phone_e164 text,
  created_at timestamptz not null,
  dedupe_key text,
  campaign_id text
) on commit drop;
insert into demo_event_seed values
  ('7c05076f-ebf4-4e6a-9b0c-1fbf8a316001'::uuid, '+250788767816', 'groupContribution', '7d57d2a9-c482-4d88-a32f-a3e80e5cf304', 20, jsonb_build_object('group_name', 'Kigali Market Circle'), null, timestamptz '2026-03-09 06:55:00+00', 'event:aline:group:1', 'rise-season'),
  ('d0db14f7-2fd0-4cb4-a45f-f5f8ee88c602'::uuid, '+250788767816', 'tripPosted', '7f6a47d7-b60d-4d48-84e2-c75e2f3bc501', 12, jsonb_build_object('route', 'Remera -> Kigali Heights'), null, timestamptz '2026-03-11 05:55:00+00', 'event:aline:trip:1', 'rise-season'),
  ('ed11f944-95a8-4adf-8fb2-174994f52603'::uuid, '+250788767816', 'initiativeSupport', '2ae5d2c7-f4ea-4458-b93c-73208cdc7301', 25, jsonb_build_object('initiative', 'Fan Kit Subsidy Program'), null, timestamptz '2026-03-06 17:15:00+00', 'event:aline:init:1', 'rise-season'),
  ('9c2d769d-5b54-4ffa-823f-7adb31d8e604'::uuid, '+250788767816', 'shopPurchase', '7b74fa3c-4fd2-42dd-82eb-8822f86ec601', 30, jsonb_build_object('order_status', 'confirmed'), null, timestamptz '2026-03-10 15:30:00+00', 'event:aline:shop:1', 'rise-season'),
  ('03e0f64c-f2f1-4d22-95cb-9c1d94dbd705'::uuid, '+250788767816', 'clubJoined', '940f35e3-bd99-4c17-9de9-093298a453c8', 10, jsonb_build_object('club', 'Gikundiro Kigali Ultra'), null, timestamptz '2026-03-04 08:30:00+00', 'event:aline:club:1', 'rise-season'),
  ('771b5eb9-b34a-4d45-907f-33816bd97b06'::uuid, '+25075588248', 'tripCompleted', '6df503b1-2cfd-4300-9426-8a3fa53b3303', 18, jsonb_build_object('vehicle_type', 'moto'), null, timestamptz '2026-03-11 18:35:00+00', 'event:jc:trip:1', 'rise-season'),
  ('2d4fb6a3-6a5a-4a17-a6dd-d1e6c7497907'::uuid, '+35677186193', 'clubJoined', '959121a9-4862-408b-becf-52d656e539a6', 10, jsonb_build_object('club', 'Gikundiro Diaspora'), '+250788767816', timestamptz '2026-03-05 10:00:00+00', 'event:matteo:club:1', 'rise-season');
insert into public.cool_events (
  id,
  user_id,
  event_type,
  source_id,
  points_awarded,
  metadata,
  referrer_id,
  created_at,
  dedupe_key,
  campaign_id,
  season_id,
  is_mock,
  mock_batch
)
select
  event_seed.id,
  user_seed.user_id,
  event_seed.event_type,
  event_seed.source_id,
  event_seed.points_awarded,
  coalesce(event_seed.metadata, '{}'::jsonb),
  referrer_seed.user_id,
  event_seed.created_at,
  event_seed.dedupe_key,
  event_seed.campaign_id,
  runtime.active_cool_season_id,
  true,
  runtime.mock_batch
from demo_event_seed event_seed
join demo_user_seed user_seed on user_seed.phone_e164 = event_seed.phone_e164
left join demo_user_seed referrer_seed on referrer_seed.phone_e164 = event_seed.referrer_phone_e164
cross join demo_runtime runtime
on conflict (id) do update
set
  user_id = excluded.user_id,
  event_type = excluded.event_type,
  source_id = excluded.source_id,
  points_awarded = excluded.points_awarded,
  metadata = excluded.metadata,
  referrer_id = excluded.referrer_id,
  created_at = excluded.created_at,
  dedupe_key = excluded.dedupe_key,
  campaign_id = excluded.campaign_id,
  season_id = excluded.season_id,
  is_mock = excluded.is_mock,
  mock_batch = excluded.mock_batch;
insert into public.cool_mission_progress (
  mission_id,
  user_id,
  contribution_value,
  completed_at,
  updated_at,
  created_at,
  is_mock,
  mock_batch
)
select
  runtime.savings_mission_id,
  user_seed.user_id,
  case user_seed.phone_e164
    when '+250788767816' then 42
    when '+25075588248' then 28
    when '+25088817592' then 14
    else 9
  end,
  null,
  now(),
  user_seed.joined_at,
  true,
  runtime.mock_batch
from demo_user_seed user_seed
cross join demo_runtime runtime
on conflict (mission_id, user_id) do update
set
  contribution_value = excluded.contribution_value,
  completed_at = excluded.completed_at,
  updated_at = excluded.updated_at,
  is_mock = excluded.is_mock,
  mock_batch = excluded.mock_batch;
insert into public.cool_mission_progress (
  mission_id,
  user_id,
  contribution_value,
  completed_at,
  updated_at,
  created_at,
  is_mock,
  mock_batch
)
select
  runtime.matchday_mission_id,
  user_seed.user_id,
  case user_seed.phone_e164
    when '+250788767816' then 2
    when '+35677186193' then 1
    else 0
  end,
  null,
  now(),
  user_seed.joined_at,
  true,
  runtime.mock_batch
from demo_user_seed user_seed
cross join demo_runtime runtime
where user_seed.phone_e164 in ('+250788767816', '+35677186193')
on conflict (mission_id, user_id) do update
set
  contribution_value = excluded.contribution_value,
  completed_at = excluded.completed_at,
  updated_at = excluded.updated_at,
  is_mock = excluded.is_mock,
  mock_batch = excluded.mock_batch;
insert into public.rs_fan_memberships (
  user_id,
  partner_id,
  tier,
  points,
  joined_at,
  chapter,
  membership_number,
  created_at,
  updated_at,
  is_mock,
  mock_batch
)
select
  user_seed.user_id,
  runtime.rayon_partner_id,
  user_seed.rayon_tier,
  user_seed.rayon_points,
  user_seed.joined_at,
  user_seed.rayon_chapter,
  user_seed.membership_number,
  user_seed.joined_at,
  now(),
  true,
  runtime.mock_batch
from demo_user_seed user_seed
cross join demo_runtime runtime
on conflict (user_id, partner_id) do update
set
  tier = excluded.tier,
  points = excluded.points,
  joined_at = excluded.joined_at,
  chapter = excluded.chapter,
  membership_number = excluded.membership_number,
  updated_at = excluded.updated_at,
  is_mock = excluded.is_mock,
  mock_batch = excluded.mock_batch;
insert into public.rs_fan_club_members (
  club_id,
  user_id,
  joined_at,
  created_at,
  is_mock,
  mock_batch
)
select
  club_id,
  user_id,
  joined_at,
  joined_at,
  true,
  runtime.mock_batch
from (
  select
    runtime.club_kigali_id as club_id,
    (select user_id from demo_user_seed where phone_e164 = '+250788767816') as user_id,
    timestamptz '2026-03-04 08:25:00+00' as joined_at
  from demo_runtime runtime
  union all
  select
    runtime.club_huye_id,
    (select user_id from demo_user_seed where phone_e164 = '+25088817592'),
    timestamptz '2026-03-02 14:10:00+00'
  from demo_runtime runtime
  union all
  select
    runtime.club_diaspora_id,
    (select user_id from demo_user_seed where phone_e164 = '+35677186193'),
    timestamptz '2026-03-05 10:00:00+00'
  from demo_runtime runtime
) seeded
cross join demo_runtime runtime
on conflict (club_id, user_id) do update
set
  joined_at = excluded.joined_at,
  is_mock = excluded.is_mock,
  mock_batch = excluded.mock_batch;
insert into public.rs_achievements (
  id,
  user_id,
  partner_id,
  badge_type,
  earned_at,
  created_at,
  emoji,
  name,
  description,
  is_earned,
  is_mock,
  mock_batch
)
select
  seeded.id,
  seeded.user_id,
  runtime.rayon_partner_id,
  seeded.badge_type,
  seeded.earned_at,
  seeded.earned_at,
  seeded.emoji,
  seeded.name,
  seeded.description,
  true,
  true,
  runtime.mock_batch
from (
  values
    (
      '74eab3be-6d33-4b78-af26-b18877d9a601'::uuid,
      (select user_id from demo_user_seed where phone_e164 = '+250788767816'),
      'community_builder',
      timestamptz '2026-03-06 17:20:00+00',
      '🏗️',
      'Community Builder',
      'Backed savings circles and supporter initiatives across the app.'
    ),
    (
      '2473da8e-d9a3-4a83-851f-1dceca4ea602'::uuid,
      (select user_id from demo_user_seed where phone_e164 = '+250788767816'),
      'matchday_regular',
      timestamptz '2026-03-10 08:35:00+00',
      '🎫',
      'Matchday Regular',
      'Locked in ticket activity and kept the chapter active.'
    ),
    (
      '32a53226-1978-49f5-9325-f4d29f120603'::uuid,
      (select user_id from demo_user_seed where phone_e164 = '+35677186193'),
      'diaspora_voice',
      timestamptz '2026-03-05 10:05:00+00',
      '🌍',
      'Diaspora Voice',
      'Joined and contributed through the diaspora supporters chapter.'
    )
) as seeded(id, user_id, badge_type, earned_at, emoji, name, description)
cross join demo_runtime runtime
on conflict (user_id, partner_id, badge_type) do update
set
  earned_at = excluded.earned_at,
  emoji = excluded.emoji,
  name = excluded.name,
  description = excluded.description,
  is_earned = excluded.is_earned,
  is_mock = excluded.is_mock,
  mock_batch = excluded.mock_batch;
insert into public.rs_matches (
  id,
  partner_id,
  home_team,
  away_team,
  competition,
  venue,
  match_date,
  kickoff_time,
  is_on_sale,
  ticket_general_price,
  ticket_vip_price,
  sale_starts_at,
  capacity,
  created_at,
  updated_at,
  is_mock,
  mock_batch
)
select
  seeded.id,
  runtime.rayon_partner_id,
  seeded.home_team,
  seeded.away_team,
  seeded.competition,
  seeded.venue,
  seeded.match_date,
  seeded.kickoff_time,
  seeded.is_on_sale,
  seeded.ticket_general_price,
  seeded.ticket_vip_price,
  seeded.sale_starts_at,
  seeded.capacity,
  seeded.created_at,
  now(),
  true,
  runtime.mock_batch
from (
  values
    (
      '85474e9b-99d4-40fe-9088-f5d9620e4901'::uuid,
      'Rayon Sports FC',
      'APR FC',
      'Rwanda Premier League',
      'Amahoro Stadium',
      date '2026-04-04',
      time '15:30:00',
      true,
      18000,
      45000,
      timestamptz '2026-03-10 08:00:00+00',
      18000,
      timestamptz '2026-03-10 08:00:00+00'
    ),
    (
      '1b41a945-8349-48ea-8415-cfdbd5e9e902'::uuid,
      'Rayon Sports FC',
      'AS Kigali',
      'Peace Cup',
      'Kigali Pelé Stadium',
      date '2026-04-18',
      time '18:00:00',
      true,
      15000,
      40000,
      timestamptz '2026-03-15 08:00:00+00',
      12000,
      timestamptz '2026-03-15 08:00:00+00'
    )
) as seeded(
  id,
  home_team,
  away_team,
  competition,
  venue,
  match_date,
  kickoff_time,
  is_on_sale,
  ticket_general_price,
  ticket_vip_price,
  sale_starts_at,
  capacity,
  created_at
)
cross join demo_runtime runtime
on conflict (id) do update
set
  partner_id = excluded.partner_id,
  home_team = excluded.home_team,
  away_team = excluded.away_team,
  competition = excluded.competition,
  venue = excluded.venue,
  match_date = excluded.match_date,
  kickoff_time = excluded.kickoff_time,
  is_on_sale = excluded.is_on_sale,
  ticket_general_price = excluded.ticket_general_price,
  ticket_vip_price = excluded.ticket_vip_price,
  sale_starts_at = excluded.sale_starts_at,
  capacity = excluded.capacity,
  updated_at = excluded.updated_at,
  is_mock = excluded.is_mock,
  mock_batch = excluded.mock_batch;
insert into public.rs_shop_products (
  id,
  partner_id,
  name,
  category,
  price,
  image_emoji,
  stock,
  is_active,
  created_at,
  updated_at,
  bg_color,
  is_new,
  is_mock,
  mock_batch
)
select
  seeded.id,
  runtime.rayon_partner_id,
  seeded.name,
  seeded.category,
  seeded.price,
  seeded.image_emoji,
  seeded.stock,
  true,
  seeded.created_at,
  now(),
  seeded.bg_color,
  seeded.is_new,
  true,
  runtime.mock_batch
from (
  values
    ('4d47c95f-93d7-44a5-b2e5-bad6067b2501'::uuid, 'Home Jersey 2026', 'kits', 45000, '👕', 28, '#20448F', true, timestamptz '2026-03-09 08:00:00+00'),
    ('9f4f20ff-56f7-4745-b125-6f06d95f7d02'::uuid, 'Matchday Scarf', 'scarves', 12000, '🧣', 44, '#16356D', true, timestamptz '2026-03-09 08:00:00+00'),
    ('c9227a09-44b1-4e68-84ca-0f9f5e0db603'::uuid, 'Blue Cap', 'caps', 9000, '🧢', 35, '#D5A62C', false, timestamptz '2026-03-09 08:00:00+00'),
    ('8d474d0f-65bc-417c-8b1d-9350b80d7404'::uuid, 'Supporter Bundle', 'bundles', 65000, '🎁', 12, '#1E2A50', true, timestamptz '2026-03-09 08:00:00+00')
) as seeded(id, name, category, price, image_emoji, stock, bg_color, is_new, created_at)
cross join demo_runtime runtime
on conflict (id) do update
set
  partner_id = excluded.partner_id,
  name = excluded.name,
  category = excluded.category,
  price = excluded.price,
  image_emoji = excluded.image_emoji,
  stock = excluded.stock,
  is_active = excluded.is_active,
  updated_at = excluded.updated_at,
  bg_color = excluded.bg_color,
  is_new = excluded.is_new,
  is_mock = excluded.is_mock,
  mock_batch = excluded.mock_batch;
insert into public.rs_shop_orders (
  id,
  user_id,
  items,
  subtotal,
  discount,
  total,
  delivery_address,
  momo_reference,
  status,
  created_at,
  updated_at,
  is_mock,
  mock_batch
)
select
  '7b74fa3c-4fd2-42dd-82eb-8822f86ec601'::uuid,
  (select user_id from demo_user_seed where phone_e164 = '+250788767816'),
  jsonb_build_array(
    jsonb_build_object(
      'product_id', '8d474d0f-65bc-417c-8b1d-9350b80d7404',
      'name', 'Supporter Bundle',
      'quantity', 1,
      'unit_price', 65000
    )
  ),
  65000,
  0,
  65000,
  'KG 11 Ave, Kimironko, Kigali',
  'RS-SHOP-ALINE-01',
  'confirmed',
  timestamptz '2026-03-10 15:25:00+00',
  now(),
  true,
  runtime.mock_batch
from demo_runtime runtime
on conflict (id) do update
set
  user_id = excluded.user_id,
  items = excluded.items,
  subtotal = excluded.subtotal,
  discount = excluded.discount,
  total = excluded.total,
  delivery_address = excluded.delivery_address,
  momo_reference = excluded.momo_reference,
  status = excluded.status,
  updated_at = excluded.updated_at,
  is_mock = excluded.is_mock,
  mock_batch = excluded.mock_batch;
insert into public.rs_initiative_contributions (
  id,
  initiative_id,
  user_id,
  amount,
  momo_reference,
  status,
  created_at,
  updated_at,
  is_mock,
  mock_batch
)
select
  '2ae5d2c7-f4ea-4458-b93c-73208cdc7301'::uuid,
  runtime.initiative_fan_kit_id,
  (select user_id from demo_user_seed where phone_e164 = '+250788767816'),
  12000,
  'RS-SUPPORT-ALINE-01',
  'confirmed',
  timestamptz '2026-03-06 17:10:00+00',
  now(),
  true,
  runtime.mock_batch
from demo_runtime runtime
on conflict (id) do update
set
  initiative_id = excluded.initiative_id,
  user_id = excluded.user_id,
  amount = excluded.amount,
  momo_reference = excluded.momo_reference,
  status = excluded.status,
  updated_at = excluded.updated_at,
  is_mock = excluded.is_mock,
  mock_batch = excluded.mock_batch;
insert into public.rs_tickets (
  id,
  match_id,
  user_id,
  seat_type,
  amount_paid,
  qr_code,
  momo_reference,
  status,
  purchased_at,
  updated_at,
  is_mock,
  mock_batch
)
select
  '3e5046e7-1ffd-44ee-9550-627fb5f17701'::uuid,
  '85474e9b-99d4-40fe-9088-f5d9620e4901'::uuid,
  (select user_id from demo_user_seed where phone_e164 = '+250788767816'),
  'General',
  18000,
  null,
  'RS-TICKET-ALINE-01',
  'valid',
  timestamptz '2026-03-10 08:30:00+00',
  now(),
  true,
  runtime.mock_batch
from demo_runtime runtime
on conflict (id) do update
set
  match_id = excluded.match_id,
  user_id = excluded.user_id,
  seat_type = excluded.seat_type,
  amount_paid = excluded.amount_paid,
  qr_code = excluded.qr_code,
  momo_reference = excluded.momo_reference,
  status = excluded.status,
  purchased_at = excluded.purchased_at,
  updated_at = excluded.updated_at,
  is_mock = excluded.is_mock,
  mock_batch = excluded.mock_batch;
commit;
