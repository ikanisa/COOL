require 'minitest/autorun'
require 'open3'

# Local disposable database only; all schema and account fixtures roll back.
class MemberProfileMomoCodeTest < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)
  DATABASE = 'collect_release_combined_uat_20260902'.freeze
  ACTOR = '99660000-0000-4000-8000-000000000001'.freeze
  OTHER = '99660000-0000-4000-8000-000000000002'.freeze

  def migration(name)
    File.read(File.join(ROOT, 'supabase/migrations', name))
      .sub(/\Abegin;\s*/i, '').sub(/\s*commit;\s*\z/i, '')
  end

  def test_private_code_round_trip_validation_compatibility_and_permissions
    # This retained fixture predates the geographical account-number RPC.
    # Replay that prerequisite inside the same rollback-only transaction.
    sql = <<~SQL
      begin;
      set local statement_timeout='30s';
      do $$ begin
        if current_database()<>'#{DATABASE}' then raise exception 'Wrong fixture database'; end if;
      end $$;
      #{migration('20260903201326_geographic_member_profile_gates.sql')}
      #{migration('20260906093000_member_profile_momo_code.sql')}
      create function pg_temp.assert_true(ok boolean, message text) returns void language plpgsql as $$
      begin if ok is not true then raise exception 'FAIL: %',message; end if; end $$;
      create function pg_temp.invalid_code(code text) returns void language plpgsql as $$
      begin
        begin
          perform public.update_current_member_profile('RW','mtn_momo','0788123401',null,null,code);
        exception when raise_exception then
          if sqlerrm='Enter a MoMo code with 4 to 9 digits.' then return; end if;
          raise;
        end;
        raise exception 'Invalid code accepted';
      end $$;
      insert into public.profile_country_rules(country_code,currency_code)
        values('RW','RWF'),('DE','EUR') on conflict(country_code) do nothing;
      insert into auth.users(id,aud,role,phone,phone_confirmed_at,raw_app_meta_data,raw_user_meta_data)
        values('#{ACTOR}','authenticated','authenticated','250788123401',now(),'{}','{}'),
              ('#{OTHER}','authenticated','authenticated','250788123402',now(),'{}','{}');
      create temporary table other_before as select to_jsonb(p) as payload from public.profiles p where id='#{OTHER}';
      select pg_temp.assert_true(not has_any_column_privilege('authenticated','public.profiles','UPDATE'),'direct profile writes stay denied');
      select pg_temp.assert_true(not has_function_privilege('anon','public.update_current_member_profile(text,text,text,text,text,text)','EXECUTE'),'anonymous RPC stays denied');
      select set_config('request.jwt.claims','{"sub":"#{ACTOR}","role":"authenticated"}',true);
      set local role authenticated;
      select pg_temp.assert_true(
        public.update_current_member_profile('RW','mtn_momo','0788123401',null,null,'008000')->>'momo_pay_code'='008000',
        'leading zero code is saved');
      select pg_temp.assert_true(public.get_current_member_profile()->>'momo_pay_code'='008000','code survives profile reload');
      select pg_temp.assert_true(public.get_current_member_profile()->>'momo_number'='0788123401','number retained beside code');
      select pg_temp.assert_true(not (public.get_current_member_profile() ? 'display_name'),'private identity allowlist retained');
      select pg_temp.invalid_code('12');
      select pg_temp.invalid_code('12*45');
      select pg_temp.invalid_code('1234567890');
      select pg_temp.assert_true(public.get_current_member_profile()->>'momo_pay_code'='008000','invalid updates are atomic');
      select pg_temp.assert_true(
        public.update_current_member_profile('RW','mtn_momo','0788123401',null,null,'')->>'momo_pay_code' is null,
        'number alone clears optional code');
      select public.update_current_member_profile('RW','mtn_momo','0788123401',null,null,'41258');
      select public.update_current_member_profile('RW','mtn_momo','0788123401',null,null);
      select pg_temp.assert_true(public.get_current_member_profile()->>'momo_pay_code'='41258','old clients preserve optional code');
      select pg_temp.assert_true(
        public.update_current_member_profile('DE',null,null,null,'000123456780',null)->>'momo_pay_code' is null,
        'diaspora switch clears Rwanda code');
      reset role;
      select pg_temp.assert_true((select to_jsonb(p) from public.profiles p where id='#{OTHER}')=(select payload from other_before),'other account unchanged');
      select pg_temp.assert_true(not exists(select 1 from public.audit_logs where actor_user_id='#{ACTOR}' and metadata::text like '%008000%'),'code omitted from audit metadata');
      select 'MOMO_CODE_ROUND_TRIP_PASS';
      rollback;
    SQL
    out, err, status = Open3.capture3('docker', 'exec', '-i', 'supabase_db_collect',
      'psql', '-XqAt', '-U', 'postgres', '-d', DATABASE, '-v', 'ON_ERROR_STOP=1', stdin_data: sql)
    assert status.success?, err
    assert_includes out, 'MOMO_CODE_ROUND_TRIP_PASS'
  end
end
