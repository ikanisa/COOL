-- Seed additional app config for coordinates and support numbers
insert into public.app_config (key, value, description) values 
(
  'default_map_lat', 
  '-1.9403', 
  'Default latitude for map center (e.g. Kigali)'
),
(
  'default_map_lng', 
  '29.8739', 
  'Default longitude for map center (e.g. Kigali)'
),
(
  'support_whatsapp', 
  '250795588248', 
  'Support WhatsApp number with country code'
)
on conflict (key) do update set 
  value = excluded.value,
  description = excluded.description;
