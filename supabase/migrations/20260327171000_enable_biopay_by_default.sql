-- Enable BioPay by default for all refreshed environments.
-- This keeps the database seed aligned with the app's runtime launch posture.

insert into public.app_config (key, value, description)
values (
  'feature_biopay_enabled',
  'true',
  'Enable the BioPay feature module inside the MoMo hub'
)
on conflict (key) do update set
  value = excluded.value,
  description = excluded.description;
