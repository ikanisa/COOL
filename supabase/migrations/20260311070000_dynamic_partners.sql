-- ==========================================================================
-- Cool App — Dynamic partners enhancement
-- Adds missing columns to partners table and seeds all 5 initial partners.
-- Partners are country-specific and managed dynamically (no hardcoding).
-- ==========================================================================

-- ── Add new columns ──────────────────────────────────────────────────────

alter table public.partners
  add column if not exists slug              text unique,
  add column if not exists emoji             text not null default '🤝',
  add column if not exists subtitle          text,
  add column if not exists whatsapp_number   text,
  add column if not exists is_active         boolean not null default true,
  add column if not exists sort_order        int not null default 0,
  add column if not exists updated_at        timestamptz not null default now();

-- ── updated_at trigger ───────────────────────────────────────────────────

create or replace function public.partners_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_partners_set_updated_at on public.partners;
create trigger trg_partners_set_updated_at
  before update on public.partners
  for each row
  execute function public.partners_set_updated_at();

-- ── Backfill slug for existing Rayon Sports row ─────────────────────────

update public.partners
set
  slug       = 'rayon-sports',
  emoji      = '⚽',
  subtitle   = 'Rwanda Premier League · Gikundiro Hub',
  sort_order = 10,
  is_active  = true
where lower(name) = 'rayon sports fc'
  and slug is null;

-- ── Seed the remaining 4 partners ────────────────────────────────────────

insert into public.partners (
  name, slug, category, country, emoji, subtitle, description,
  whatsapp_number, fan_count, club_count, game_count, is_active, sort_order
)
values
  -- Football: APR FC
  (
    'APR FC',
    'apr-fc',
    'football',
    'RW',
    '⚽',
    'Rwanda Premier League · Official Cool Partner',
    'APR FC fan hub — registry, clubs, ticketing, and shop.',
    null,
    12480,
    34,
    5,
    true,
    0
  ),
  -- Finance: Urwego Finance
  (
    'Urwego Finance',
    'urwego',
    'bank',
    'RW',
    '🏦',
    'Custodian of Group Savings · Microfinance Leader',
    'Microfinance partner for group savings custody, loans, and bank accounts.',
    null,
    0,
    0,
    0,
    true,
    0
  ),
  -- Organization: Radiant Insurance
  (
    'Radiant Insurance',
    'radiant',
    'organization',
    'RW',
    '🛡️',
    'Group savings insurance & member protection',
    'Insurance partner providing coverage for savings groups and members.',
    '250795588248',
    0,
    0,
    0,
    true,
    0
  ),
  -- Organization: PRISMA
  (
    'PRISMA',
    'prisma',
    'organization',
    'RW',
    '⚖️',
    'Accounting · Tax · Audit · Legal · Advisory',
    'Professional services firm providing accounting, tax, legal, and advisory.',
    '250795588248',
    0,
    0,
    0,
    true,
    10
  )
on conflict (slug) do update
set
  name              = excluded.name,
  category          = excluded.category,
  country           = excluded.country,
  emoji             = excluded.emoji,
  subtitle          = excluded.subtitle,
  description       = excluded.description,
  whatsapp_number   = excluded.whatsapp_number,
  fan_count         = excluded.fan_count,
  club_count        = excluded.club_count,
  game_count        = excluded.game_count,
  is_active         = excluded.is_active,
  sort_order        = excluded.sort_order,
  updated_at        = now();
