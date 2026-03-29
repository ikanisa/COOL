alter table public.contribution_groups
  add column if not exists momo_number text,
  add column if not exists receiving_momo_code text,
  add column if not exists momo_route_type text;

update public.contribution_groups
set receiving_momo_code = nullif(btrim(coalesce(momo_code, '')), '')
where nullif(btrim(coalesce(receiving_momo_code, '')), '') is null
  and nullif(btrim(coalesce(momo_code, '')), '') is not null;

update public.contribution_groups
set momo_route_type = case
  when nullif(btrim(coalesce(momo_route_type, '')), '') is not null then momo_route_type
  when nullif(btrim(coalesce(momo_number, '')), '') is not null then 'phone_number'
  when nullif(btrim(coalesce(receiving_momo_code, '')), '') is not null then 'code'
  else null
end
where nullif(btrim(coalesce(momo_route_type, '')), '') is null;

comment on column public.contribution_groups.momo_number is
  'Default group collection MoMo number. Prefilled from the creator profile when available but editable per group.';

comment on column public.contribution_groups.receiving_momo_code is
  'Default group collection MoMo code. Prefilled from the creator profile when available but editable per group.';

comment on column public.contribution_groups.momo_route_type is
  'Preferred routing type for the group collection recipient: phone_number or code.';
