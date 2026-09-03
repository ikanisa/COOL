require 'minitest/autorun'
require 'open3'

# Full PostgreSQL schema, disposable local fixture database, rollback only.
# No production URL, credential, provider send, or persisted fixture is accepted.
class MemberProfileRpcOnlyWritesTest < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)
  DATABASE = 'collect_release_combined_uat_20260902'.freeze
  MIGRATION = '20260903083947_member_profile_rpc_only_writes.sql'.freeze
  ACTOR = '99630000-0000-4000-8000-000000000001'.freeze
  OTHER = '99630000-0000-4000-8000-000000000002'.freeze

  def sql(body, patched: false)
    migration = File.read(File.join(ROOT, 'supabase/migrations', MIGRATION))
      .sub(/\Abegin;\s*/i, '').sub(/\s*commit;\s*\z/i, '')
    fixture = <<~SQL
      begin;
      set local statement_timeout='20s';
      do $$ begin
        if current_database()<>'#{DATABASE}' then raise exception 'Wrong fixture database'; end if;
      end $$;
      create function pg_temp.assert_true(ok boolean, message text) returns void language plpgsql as $$
      begin if ok is not true then raise exception 'FAIL: %',message; end if; end $$;
      create function pg_temp.denied(statement text) returns void language plpgsql as $$
      begin
        begin execute statement;
        exception when insufficient_privilege then return; end;
        raise exception 'Expected permission denial: %',statement;
      end $$;
      -- Reconstruct the exact pre-cutover constraint state inside this rollback-only fixture.
      alter table public.profiles drop constraint if exists profiles_momo_number_hash_matches;
      insert into public.profile_country_rules(country_code,currency_code)
        values('RW','RWF'),('GB','GBP') on conflict(country_code) do nothing;
      insert into auth.users(id,aud,role,phone,phone_confirmed_at,raw_app_meta_data,raw_user_meta_data)
        values('#{ACTOR}','authenticated','authenticated','250788123401',now(),'{}','{}'),
              ('#{OTHER}','authenticated','authenticated','250788123402',now(),'{}','{}');
      update public.profiles set country_code='RW',currency_code='RWF',momo_provider='mtn_momo',
        momo_number='0788123401',momo_number_hash=encode(extensions.digest('+250788123401','sha256'),'hex'),
        display_name='Private Admin-only evidence',revolut_name='Private account evidence'
        where id='#{ACTOR}';
      create temporary table profile_before as select * from public.profiles;
      create temporary table audit_before as select count(*) as n from public.audit_logs;
      create temporary table service_before as select
        has_table_privilege('service_role','public.profiles','UPDATE') as table_update,
        has_any_column_privilege('service_role','public.profiles','UPDATE') as column_update;
      -- Reproduce exactly the legacy grants, even when a later local replay has the fix.
      grant update(momo_number,momo_number_hash,momo_pay_code,updated_at) on public.profiles to authenticated;
      #{patched ? migration : ''}
      select set_config('request.jwt.claims','{"sub":"#{ACTOR}","role":"authenticated"}',true);
      set local role authenticated;
      #{body}
      reset role;
      select pg_temp.assert_true(
        (select to_jsonb(p) from public.profiles p where id='#{OTHER}') =
        (select to_jsonb(p) from profile_before p where id='#{OTHER}'),'other profile unchanged');
      rollback;
    SQL
    out, err, status = Open3.capture3('docker', 'exec', '-i', 'supabase_db_collect',
      'psql', '-XqAt', '-U', 'postgres', '-d', DATABASE, '-v', 'ON_ERROR_STOP=1', stdin_data: fixture)
    assert status.success?, err
    assert_includes out, 'PROFILE_WRITE_TEST_PASS'
  end

  def test_legacy_grants_reproduce_unaudited_hash_bypass
    sql <<~SQL
      update public.profiles set momo_number_hash=repeat('f',64) where id='#{ACTOR}';
      reset role;
      select pg_temp.assert_true((select momo_number_hash=repeat('f',64) and momo_number='0788123401'
        from public.profiles where id='#{ACTOR}'),'unrelated hash accepted without changing phone');
      select pg_temp.assert_true(public._authenticated_momo_phone_hash('#{ACTOR}')=repeat('f',64),
        'contribution helper consumes the tampered hash');
      select pg_temp.assert_true((select count(*) from public.audit_logs)=(select n from audit_before),
        'direct write bypasses profile audit');
      select 'PROFILE_WRITE_TEST_PASS';
    SQL
  end

  def test_cutover_fails_closed_when_a_hash_was_tampered_before_migration
    migration = File.read(File.join(ROOT, 'supabase/migrations', MIGRATION))
    add_constraint = migration.match(/alter table public\.profiles\n  add constraint profiles_momo_number_hash_matches.*?\n  \) not valid;/m)&.to_s
    refute_nil add_constraint
    fixture = <<~SQL
      begin;
      set local statement_timeout='20s';
      do $$ begin
        if current_database()<>'#{DATABASE}' then raise exception 'Wrong fixture database'; end if;
      end $$;
      insert into public.profile_country_rules(country_code,currency_code)
        values('RW','RWF') on conflict(country_code) do nothing;
      alter table public.profiles drop constraint if exists profiles_momo_number_hash_matches;
      insert into auth.users(id,aud,role,phone,phone_confirmed_at,raw_app_meta_data,raw_user_meta_data)
        values('#{ACTOR}','authenticated','authenticated','250788123401',now(),'{}','{}');
      update public.profiles set country_code='RW',currency_code='RWF',momo_provider='mtn_momo',
        momo_number='0788123401',momo_number_hash=encode(extensions.digest('+250788123401','sha256'),'hex')
        where id='#{ACTOR}';
      grant update(momo_number,momo_number_hash,momo_pay_code,updated_at) on public.profiles to authenticated;
      select set_config('request.jwt.claims','{"sub":"#{ACTOR}","role":"authenticated"}',true);
      set local role authenticated;
      update public.profiles set momo_number_hash=repeat('f',64) where id='#{ACTOR}';
      reset role;
      #{add_constraint}
      do $$
      begin
        begin
          execute 'alter table public.profiles validate constraint profiles_momo_number_hash_matches';
        exception when check_violation then
          perform set_config('collect_test.validation_failed_closed','true',true);
        end;
      end $$;
      select case
        when current_setting('collect_test.validation_failed_closed',true)='true'
          and not (select convalidated from pg_constraint
            where conrelid='public.profiles'::regclass
              and conname='profiles_momo_number_hash_matches')
          and (select momo_number_hash=repeat('f',64) from public.profiles where id='#{ACTOR}')
        then 'PROFILE_HASH_CUTOVER_FAILS_CLOSED'
        else 'PROFILE_HASH_CUTOVER_UNSAFE'
      end;
      rollback;
    SQL
    out, err, status = Open3.capture3('docker', 'exec', '-i', 'supabase_db_collect',
      'psql', '-XqAt', '-U', 'postgres', '-d', DATABASE, '-v', 'ON_ERROR_STOP=1', stdin_data: fixture)
    assert status.success?, err
    assert_includes out, 'PROFILE_HASH_CUTOVER_FAILS_CLOSED'
  end

  def test_direct_writes_and_alternate_syntax_are_denied
    sql <<~SQL, patched: true
      select pg_temp.denied($q$update public.profiles set momo_number_hash=repeat('f',64) where id='#{ACTOR}'$q$);
      select pg_temp.denied($q$update only public.profiles set momo_number_hash=null where id='#{ACTOR}'$q$);
      select pg_temp.denied($q$update public.profiles set momo_number='0788123499' where id='#{ACTOR}'$q$);
      select pg_temp.denied($q$update public.profiles set momo_pay_code='99999' where id='#{ACTOR}'$q$);
      select pg_temp.denied($q$update public.profiles set updated_at=now() where id='#{ACTOR}'$q$);
      select pg_temp.denied($q$update public.profiles set momo_number_hash=repeat('a',64) where id='#{OTHER}'$q$);
      select pg_temp.denied($q$select public.update_current_profile('Name','RW',null,null,null,null,null)$q$);
      set local role anon;
      select pg_temp.denied($q$update public.profiles set momo_number_hash=repeat('f',64)$q$);
      select pg_temp.denied($q$select public.update_current_member_profile('RW','mtn_momo','0788123401')$q$);
      reset role;
      select pg_temp.assert_true(not exists(select 1 from unnest(array['anon','authenticated']) r
        where has_table_privilege(r,'public.profiles','UPDATE')
          or has_any_column_privilege(r,'public.profiles','UPDATE')),'no client write privilege remains');
      select pg_temp.assert_true((select to_jsonb(p) from public.profiles p where id='#{ACTOR}')=
        (select to_jsonb(p) from profile_before p where id='#{ACTOR}'),'denied writes change no fields');
      select 'PROFILE_WRITE_TEST_PASS';
    SQL
  end

  def test_valid_rwanda_and_diaspora_saves_preserve_identity_and_audit
    sql <<~SQL, patched: true
      select pg_temp.assert_true(public.update_current_member_profile('RW','mtn_momo','0788123401')->>'momo_number'='0788123401','MTN save');
      select pg_temp.assert_true(public.update_current_member_profile('RW','airtel_money','0728123401')->>'momo_provider'='airtel_money','Airtel save');
      reset role;
      select pg_temp.assert_true((select momo_number_hash=encode(extensions.digest('+250728123401','sha256'),'hex')
        and momo_number_verified_at is null from public.profiles where id='#{ACTOR}'),'server derives Airtel hash and clears verification');
      set local role authenticated;
      select pg_temp.assert_true(public.update_current_member_profile('GB',null,null,'https://revolut.me/fixture123','EUR account')->>'currency_code'='GBP','diaspora save');
      select pg_temp.assert_true(public.get_current_member_profile()->>'whatsapp_phone'='250788123401','verified sign-in identity unchanged');
      reset role;
      select pg_temp.assert_true((select momo_number is null and momo_number_hash is null and momo_provider is null
        and display_name='Private Admin-only evidence' and revolut_name='Private account evidence'
        from public.profiles where id='#{ACTOR}'),'rail switch clears MoMo and preserves private evidence');
      select pg_temp.assert_true((select public_id from public.profiles where id='#{ACTOR}')=
        (select public_id from profile_before where id='#{ACTOR}'),'numeric ID unchanged');
      select pg_temp.assert_true((select count(*) from public.audit_logs where actor_user_id='#{ACTOR}'
        and action='profile.payment_route.updated')=3,'every valid save audited');
      select pg_temp.assert_true(has_table_privilege('service_role','public.profiles','UPDATE')=
        (select table_update from service_before) and has_any_column_privilege('service_role','public.profiles','UPDATE')=
        (select column_update from service_before),'service privileges unchanged');
      select 'PROFILE_WRITE_TEST_PASS';
    SQL
  end
end
