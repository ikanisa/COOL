begin;
-- Enforce the live Rwanda-only runtime contract on environments that still
-- carry earlier multi-market or multi-language seed data.

delete from public.app_config
where key = 'supported_languages';
delete from public.supported_countries
where iso_code <> 'RW';
update public.supported_countries
set
  country_name = 'Rwanda',
  dial_code = '+250',
  currency_code = 'RWF',
  currency_name = 'Rwandan franc',
  default_lat = -1.9441,
  default_lng = 30.0619,
  sort_order = 0,
  is_active = true
where iso_code = 'RW';
create or replace view public.operational_config_issues as
with required_configs(config_key, scope_mode, stale_after_days, description) as (
  values
    ('support_whatsapp', 'shared', 45, 'Primary support escalation contact.')
),
matching_configs as (
  select
    rc.config_key,
    rc.scope_mode,
    rc.stale_after_days,
    rc.description,
    ac.key,
    ac.country,
    nullif(btrim(coalesce(ac.value, '')), '') as config_value,
    coalesce(ac.updated_at, ac.created_at) as last_updated_at
  from required_configs rc
  left join lateral (
    select *
    from public.app_config ac
    where ac.key = rc.config_key
      and (
        rc.scope_mode = 'any'
        or (rc.scope_mode = 'shared' and ac.country is null)
      )
    order by coalesce(ac.updated_at, ac.created_at) desc nulls last
    limit 1
  ) ac on true
)
select
  format('config:%s', config_key) as issue_id,
  case
    when config_value is null then 'missing_required_config'
    else 'stale_config_review'
  end as issue_type,
  case
    when config_value is null then 'critical'
    else 'warning'
  end as severity,
  'config_hygiene'::text as service,
  case
    when config_value is null then 'Required config is missing'
    else 'Config review window expired'
  end as title,
  case
    when config_value is null then
      format('%s is missing. %s', config_key, description)
    else
      format(
        '%s has not been reviewed in %s days. %s',
        config_key,
        greatest(
          1,
          floor(extract(epoch from (now() - last_updated_at)) / 86400)::int
        ),
        description
      )
  end as detail,
  'app_config'::text as subject_table,
  config_key as subject_id,
  null::uuid as user_id,
  config_key as reference,
  last_updated_at as first_seen_at,
  last_updated_at as last_seen_at,
  jsonb_build_object(
    'config_key', config_key,
    'scope_mode', scope_mode,
    'country', country,
    'last_updated_at', last_updated_at,
    'stale_after_days', stale_after_days
  ) as metadata
from matching_configs
where config_value is null
   or last_updated_at <= now() - make_interval(days => stale_after_days);
-- If 'Western Blue Wave' already exists for the partner, just delete the
-- diaspora-named duplicates. Otherwise rename one and delete the rest.
do $$
declare
  v_partner_id uuid;
  v_has_western boolean;
begin
  select partner_id into v_partner_id
  from public.rs_fan_clubs
  where lower(btrim(region)) in ('diaspora', 'international')
     or lower(btrim(name)) in ('gikundiro diaspora', 'diaspora blue wave')
  limit 1;

  if v_partner_id is null then
    -- No diaspora rows to clean up
    return;
  end if;

  select exists(
    select 1 from public.rs_fan_clubs
    where partner_id = v_partner_id
      and name = 'Western Blue Wave'
  ) into v_has_western;

  if v_has_western then
    -- Target name already exists; delete the diaspora rows
    delete from public.rs_fan_clubs
    where (lower(btrim(region)) in ('diaspora', 'international')
       or lower(btrim(name)) in ('gikundiro diaspora', 'diaspora blue wave'))
      and name != 'Western Blue Wave';
  else
    -- Rename one diaspora row, delete the rest
    with keep_one as (
      select id from public.rs_fan_clubs
      where lower(btrim(region)) in ('diaspora', 'international')
         or lower(btrim(name)) in ('gikundiro diaspora', 'diaspora blue wave')
      order by created_at asc
      limit 1
    )
    update public.rs_fan_clubs
    set
      name = 'Western Blue Wave',
      region = 'Western',
      description = 'Supporters across Rubavu, Rusizi, Karongi, and the western corridor organizing buses, watch parties, and community drives.',
      updated_at = now()
    where id in (select id from keep_one);

    delete from public.rs_fan_clubs
    where (lower(btrim(region)) in ('diaspora', 'international')
       or lower(btrim(name)) in ('gikundiro diaspora', 'diaspora blue wave'))
      and name != 'Western Blue Wave';
  end if;

  -- Ensure the surviving Western Blue Wave row has correct region/description
  update public.rs_fan_clubs
  set
    region = 'Western',
    description = 'Supporters across Rubavu, Rusizi, Karongi, and the western corridor organizing buses, watch parties, and community drives.',
    updated_at = now()
  where partner_id = v_partner_id
    and name = 'Western Blue Wave';
end;
$$;
update public.rs_achievements
set
  badge_type = 'western_voice',
  name = 'Western Voice',
  description = 'Joined and contributed through the western Rwanda supporters chapter.'
where badge_type = 'diaspora_voice'
   or name = 'Diaspora Voice';
alter table public.groups disable trigger trg_enforce_group_momo_fields;
update public.groups
set
  name = 'Western Builders Pool',
  description = 'Private support pool for travel, matchday plans, and family projects across western Rwanda.',
  updated_at = now()
where name = 'Diaspora Builders Pool';
alter table public.groups enable trigger trg_enforce_group_momo_fields;
update public.cool_events
set metadata = jsonb_set(metadata, '{club}', to_jsonb('Western Blue Wave'::text), true)
where metadata ->> 'club' = 'Gikundiro Diaspora';
update public.cool_events
set metadata = jsonb_set(metadata, '{group_name}', to_jsonb('Western Builders Pool'::text), true)
where metadata ->> 'group_name' = 'Diaspora Builders Pool';
commit;
