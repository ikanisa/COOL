alter table public.profiles
  add column if not exists momo_pay_code text;

alter table public.profiles
  add constraint profiles_momo_pay_code_format
  check (momo_pay_code is null or momo_pay_code ~ '^[0-9]{5,6}$')
  not valid;

alter table public.profiles
  validate constraint profiles_momo_pay_code_format;

grant update (momo_pay_code, updated_at) on public.profiles to authenticated;
