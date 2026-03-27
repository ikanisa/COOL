-- Add image_url to rs_matches for admin-managed hero backgrounds
alter table rs_matches
  add column if not exists image_url text;

-- Home banners: dynamic promotional cards managed by platform admins
create table if not exists rs_home_banners (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  subtitle text,
  badge_label text,
  cta_label text not null default 'LEARN MORE',
  route text not null default '/',
  image_url text,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Enable RLS
alter table rs_home_banners enable row level security;

-- Public read access for active banners
create policy if not exists "Public can read active home banners"
  on rs_home_banners for select
  using (is_active = true);

-- Admin write access
create policy if not exists "Admins can manage home banners"
  on rs_home_banners for all
  using (
    exists (
      select 1 from auth.users
      where auth.uid() = id
        and raw_user_meta_data->>'role' in ('admin', 'super_admin')
    )
  );

-- Seed the "Official Fan Registry" banner
insert into rs_home_banners (title, subtitle, badge_label, cta_label, route, sort_order)
values (
  'OFFICIAL FAN REGISTRY',
  'Register as an official member to get your digital ID.',
  'REGISTRY',
  'REGISTER NOW',
  '/rayon/registry',
  0
)
on conflict do nothing;
