-- ==========================================================================
-- User profile wallet route semantics
-- ==========================================================================

alter table public.users
  add column if not exists momo_route_type text;
alter table public.users
  drop constraint if exists users_momo_route_type_check;
alter table public.users
  add constraint users_momo_route_type_check
    check (momo_route_type in ('phone_number', 'code'));
drop trigger if exists trg_enforce_user_momo_fields on public.users;
update public.users
set
  country = public.normalize_country_code(country),
  momo_route_type = case
  when public.is_valid_momo_phone_for_country(
    public.normalize_country_code(country),
    momo_number
  ) then
    'phone_number'
  when public.is_valid_momo_code_for_country(
    public.normalize_country_code(country),
    momo_code
  ) then
    'code'
  else null
end
where momo_route_type is null;
create or replace function public.enforce_user_momo_fields()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_country public.supported_countries;
begin
  new.country := public.normalize_country_code(
    coalesce(nullif(btrim(coalesce(new.country, '')), ''), 'RW')
  );
  new.momo_number := nullif(btrim(coalesce(new.momo_number, '')), '');
  new.momo_code := nullif(btrim(coalesce(new.momo_code, '')), '');
  new.momo_route_type := nullif(
    lower(btrim(coalesce(new.momo_route_type, ''))),
    ''
  );
  new.momo_provider := coalesce(new.momo_provider, '');

  if new.momo_number is not null then
    new.momo_number := public.normalize_momo_phone_for_country(
      new.country,
      new.momo_number
    );
  end if;

  if new.momo_code is not null then
    new.momo_code := public.normalize_momo_code_for_country(
      new.country,
      new.momo_code
    );
  end if;

  if btrim(new.momo_provider) = '' then
    select *
    into v_country
    from public.get_supported_country_momo_config(new.country);

    if v_country.iso_code is not null then
      new.momo_provider := coalesce(v_country.momo_provider_id, '');
    end if;
  end if;

  if new.momo_number is not null then
    new.momo_route_type := 'phone_number';
  elsif new.momo_code is not null then
    new.momo_route_type := 'code';
  else
    new.momo_route_type := null;
  end if;

  return new;
end;
$$;
drop trigger if exists trg_enforce_user_momo_fields on public.users;
create trigger trg_enforce_user_momo_fields
  before insert or update on public.users
  for each row
  execute function public.enforce_user_momo_fields();
