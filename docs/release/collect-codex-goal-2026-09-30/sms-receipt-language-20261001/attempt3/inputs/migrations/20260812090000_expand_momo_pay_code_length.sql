alter table public.profiles
  drop constraint if exists profiles_momo_pay_code_format;

alter table public.profiles
  add constraint profiles_momo_pay_code_format
  check (momo_pay_code is null or momo_pay_code ~ '^[0-9]{4,9}$')
  not valid;

alter table public.profiles
  validate constraint profiles_momo_pay_code_format;
