begin;
set local statement_timeout = '30s';

do $$
begin
  if not exists (
    select 1 from public.profile_country_rules
    where country_code = 'RW' and currency_code = 'RWF' and enabled
  ) then
    raise exception 'Rwanda RWF country rule missing';
  end if;
  if exists (
    select 1 from public.profile_country_rules
    where country_code <> 'RW'
  ) then
    raise exception 'Foreign profile rule remains in the catalog';
  end if;
  if exists (
    select 1 from public.feature_flags
    where key = 'bank_transfer_v1'
  ) then
    raise exception 'Retired payment flag remains in the catalog';
  end if;
  if not has_function_privilege(
    'authenticated',
    'public.update_current_member_profile(text,text,text,text)',
    'EXECUTE'
  ) then
    raise exception 'Rwanda MoMo profile API is unavailable';
  end if;
  if to_regprocedure('public.update_current_member_profile(text,text,text,text,text)') is not null
     or to_regprocedure('public.update_current_member_profile(text,text,text,text,text,text)') is not null then
    raise exception 'Retired member profile overload remains';
  end if;
  if not exists (
    select 1 from pg_trigger
    where tgname = 'payment_intents_rwanda_momo_only' and not tgisinternal
  ) or not exists (
    select 1 from pg_trigger
    where tgname = 'payments_rwanda_momo_only' and not tgisinternal
  ) then
    raise exception 'Rwanda MoMo payment write guard is missing';
  end if;
  if exists (
    select 1 from information_schema.routine_privileges
    where specific_schema = 'public'
      and grantee in ('PUBLIC', 'anon', 'authenticated', 'service_role')
      and routine_name ~ '(bank|diaspora|stripe|sepa)'
  ) then
    raise exception 'Retired payment routine remains executable';
  end if;
  if exists (
    select 1
    from (values
      ('collect_member_actions.payment_history()'::regprocedure),
      ('public.list_current_member_payment_intents()'::regprocedure),
      ('public.list_current_member_collection_balances()'::regprocedure)
    ) required(signature)
    where pg_get_functiondef(required.signature) ~
      '(bank_transactions|bank_transfer_intents|diaspora_bank)'
  ) then
    raise exception 'Member read API still includes retired payment activity';
  end if;
end $$;

select 'RWANDA_MOMO_SCOPE_UAT_PASS';
rollback;
