-- Harden runtime app configuration reads.
--
-- app_config contains operational values that should not be exposed wholesale
-- to anon/authenticated clients. Runtime clients must use the allowlisted RPC
-- below; direct table SELECT is limited to platform admins.

alter table public.app_config
  add column if not exists is_public boolean not null default false;

comment on column public.app_config.is_public is
  'Controls exposure through get_public_app_config(); direct app_config reads remain admin-only.';

update public.app_config
set is_public = true
where key in (
  'allowed_countries',
  'biopay_cache_ttl_hours',
  'biopay_match_rate_limit',
  'biopay_match_rate_window_minutes',
  'biopay_match_threshold',
  'biopay_stable_frames',
  'default_country',
  'default_map_lat',
  'default_map_lng',
  'feature_biopay_enabled',
  'notification_categories',
  'support_whatsapp',
  'tier_gold_min',
  'tier_platinum_min',
  'tier_silver_min'
);

drop policy if exists "Public read app_config" on public.app_config;

drop policy if exists app_config_select_admin on public.app_config;
create policy app_config_select_admin
  on public.app_config
  for select
  to authenticated
  using (public.is_admin_user());

create or replace function public.get_public_app_config(p_keys text[] default null)
returns table (
  key text,
  value text,
  description text
)
language sql
stable
security definer
set search_path = public
as $$
  select ac.key, ac.value, ac.description
  from public.app_config ac
  where ac.is_public = true
    and (p_keys is null or ac.key = any(p_keys))
  order by ac.key;
$$;

revoke all on function public.get_public_app_config(text[]) from public;
grant execute on function public.get_public_app_config(text[]) to anon, authenticated, service_role;

comment on function public.get_public_app_config(text[]) is
  'Returns only app_config rows explicitly marked is_public=true. Use this for client runtime config.';
