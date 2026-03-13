-- Rwanda-only local catalog cleanup.
-- These tables remain part of the fixed Rwanda app shell, so country-specific
-- scoping is removed from the local catalog rows themselves. Partner payment
-- routes stay country-scoped because their schema and validation still require
-- an explicit Rwanda route.

delete from public.app_config
where key ~ '^feature_.*_allowed_[a-z_]+$';

update public.app_config
set country = null
where country is not null;

delete from public.quick_actions
where country is not null
  and upper(btrim(country)) <> 'RW';

update public.quick_actions
set country = null
where country is not null;

delete from public.vehicle_types
where country is not null
  and upper(btrim(country)) <> 'RW';

update public.vehicle_types
set country = null
where country is not null;

delete from public.partner_services
where country is not null
  and upper(btrim(country)) <> 'RW';

update public.partner_services
set country = null
where country is not null;
