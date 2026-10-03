begin;

-- Auth creates a profile before a member chooses a Rwanda MoMo provider.
-- Keep that empty onboarding state writable while rejecting new foreign or
-- partially mixed country/currency profiles. Historical rows stay available
-- for controlled review until the Rwanda-only cutover is reconciled.
alter table public.profiles
  drop constraint if exists profiles_rwanda_momo_only;
alter table public.profiles
  add constraint profiles_rwanda_momo_only
  check (
    (country_code is null and currency_code is null)
    or (
      country_code is not null and currency_code is not null
      and country_code = 'RW' and currency_code = 'RWF'
    )
  ) not valid;

commit;
