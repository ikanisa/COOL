# Dedicated schema-only local sandbox. Never copies customer records or changes
# the original postgres/member UAT databases. Reference role data only.
require 'open3'
ROOT = File.expand_path('../..', __dir__)
COMBINED = !!ARGV.delete('--combined')
DB = (if COMBINED
  'collect_release_combined_uat_20260902'
elsif ARGV.delete('--final')
  'collect_platform_access_final_20260902'
elsif ARGV.delete('--replay')
  'collect_platform_access_replay_20260902'
else
  'collect_platform_access_uat_20260902'
end).freeze
BASE = %w[docker exec -i supabase_db_collect psql -XqAt -U postgres -v ON_ERROR_STOP=1].freeze
def sql(database, input)
  out, err, status = Open3.capture3(*BASE, '-d', database, stdin_data: input)
  abort(err) unless status.success?
  warn(err) unless err.empty?
  out
end

# The hybrid registry makes Collect IDs immutable. Fixtures must consume the
# IDs allocated by the actual generator, not overwrite them or disable guards.
def fixture_ids(prefix)
  <<~SQL
    create temporary table fixture_public_ids as
      select right(id::text,1)::int as fixture_number, public_id::text as public_id
      from public.profiles where id::text like '#{prefix}%';
    grant select on pg_temp.fixture_public_ids to authenticated, service_role;
    create function pg_temp.fixture_public_id(n int) returns text
    language sql stable as $$
      select public_id from pg_temp.fixture_public_ids where fixture_number=n;
    $$;
  SQL
end

def combined_fixture(statement, kind)
  return statement unless COMBINED
  case kind
  when :platform
    marker = "update public.profiles set public_id='98200'||right(id::text,1) where id::text like '98200000%';"
    abort('Platform fixture changed') unless statement.include?(marker)
    statement = statement.sub(marker, fixture_ids('98200000'))
    statement = statement.gsub("'982006'", 'pg_temp.fixture_public_id(6)')
  when :group
    marker = "update public.profiles set public_id='98000'||right(id::text,1)\nwhere id::text like '98000000-0000-4000-8000-%';"
    abort('Group fixture changed') unless statement.include?(marker)
    statement = statement.sub(marker, fixture_ids('98000000'))
    receipt = %q{'{"collection_id":"98000000-0000-4000-8000-000000000010","public_id":"980002","role":"admin","status":"active"}'::jsonb}
    abort('Group receipt assertion changed') unless statement.include?(receipt)
    statement = statement.sub(receipt, "jsonb_build_object('collection_id','98000000-0000-4000-8000-000000000010','public_id',pg_temp.fixture_public_id(2),'role','admin','status','active')")
    statement = statement.gsub("' 980002 '", "(' ' || pg_temp.fixture_public_id(2) || ' ')")
    (1..8).each { |n| statement = statement.gsub("'98000#{n}'", "pg_temp.fixture_public_id(#{n})") }
  when :journey
    marker = /set public_id = case id.*?end,\n    country_code = 'RW',/m
    abort('Journey fixture changed') unless statement.match?(marker)
    statement = statement.sub(marker, "set country_code = 'RW',")
    statement = statement.sub('update public.profiles', fixture_ids('81000000') + "\nupdate public.profiles")
    statement = statement.gsub("'810002'", 'pg_temp.fixture_public_id(2)')
  end
  statement
end
if ARGV == ['--setup']
  abort('Refusing to overwrite existing platform UAT database') unless sql('postgres', "select datname from pg_database where datname='#{DB}';").strip.empty?
  sql('postgres', "create database #{DB} template template0;")
  schema, err, status = Open3.capture3('docker', 'exec', 'supabase_db_collect', 'pg_dump',
    '-U', 'postgres', '-d', 'collect_uat_20260902', '--schema-only', '--no-owner', '--no-publications', '--no-subscriptions')
  abort(err) unless status.success?
  schema = schema.lines.reject { |line| line.start_with?('ALTER DEFAULT PRIVILEGES FOR ROLE ') && !line.start_with?('ALTER DEFAULT PRIVILEGES FOR ROLE postgres ') }.join
  sql(DB, schema)
  data, err, status = Open3.capture3('docker', 'exec', 'supabase_db_collect', 'pg_dump',
    '-U', 'postgres', '-d', 'collect_uat_20260902', '--data-only', '--no-owner',
    '--table=public.admin_roles', '--table=public.admin_permissions', '--table=public.admin_role_permissions',
    '--table=public.admin_queue_specs', '--table=public.admin_queue_filter_options')
  abort(err) unless status.success?
  sql(DB, data)
  puts 'Platform sandbox created from schema and role definitions only; no user/payment/session records copied.'
elsif ARGV == ['--migrate'] || ARGV == ['--refresh-functions']
  abort('Combined sandbox does not permit refresh shortcuts') if COMBINED && ARGV == ['--refresh-functions']
  if COMBINED
    %w[20260902120435_hybrid_receipt_capture_contract.sql 20260902120555_hybrid_member_registry.sql].each do |name|
      sql(DB, File.read(ROOT + '/supabase/migrations/' + name))
      puts "Combined sandbox only: applied #{name}"
    end
  end
  file = ROOT + '/supabase/migrations/20260902140151_platform_admin_whatsapp_approval.sql'
  candidate = File.read(file)
  if ARGV == ['--refresh-functions']
    # Iteration on this exact disposable database only; preserve schema/data.
    marker = 'create function collect_admin_access.verified_phone'
    abort('Candidate function marker missing') unless candidate.include?(marker)
    candidate = "begin;\n" + candidate[candidate.index(marker)..].gsub(/^create function /, 'create or replace function ')
  end
  puts sql(DB, candidate)
  puts 'Candidate applied only to dedicated platform UAT sandbox.'
elsif ARGV == ['--member-regressions']
  # Keep the existing assertions. Only the platform-operator fixture gains
  # approval and a session. Ordinary members remain unapproved.
  journey = File.read(ROOT + '/scripts/group_creation_journey_uat.sql')
  journey = journey.sub("begin;", <<~SQL)
    begin;
    insert into public.collection_type_catalog(key,label,short_purpose,icon_key,default_category_subtype,default_purpose_template_key)
    values('ikimina','Group savings','Synthetic catalogue fixture','savings','group_savings','group_savings');
    insert into public.collection_category_subtypes(collection_type_key,key,label) values('ikimina','group_savings','Group savings');
    insert into public.collection_purpose_templates(collection_type_key,key,label) values('ikimina','group_savings','Group savings');
    insert into public.collection_type_country_rules(collection_type_key,country_code) values('ikimina','RW');
  SQL
  templates = File.read(ROOT + '/supabase/migrations/20260703225455_notification_templates_runtime.sql')
  seed_marker = 'insert into notification_channels (key, label, description, platform, display_order, enabled)'
  abort('Notification reference seed changed') unless templates.scan(seed_marker).length == 1
  template_seed = templates[templates.index(seed_marker)..].sub(/\ncommit;\s*\z/, '')
  # Reuse the complete checked-in reference templates inside the rolled-back
  # journey. No provider jobs or deliveries are executed by this local SQL test.
  journey = journey.sub('create or replace function pg_temp.assert_true', template_seed + "\ncreate or replace function pg_temp.assert_true")
  marker = "where role.name = 'platform_owner';"
  abort('Group fixture marker changed') unless journey.scan(marker).length == 1
  journey = journey.sub(marker, marker + <<~SQL)

    insert into collect_admin_access.whatsapp_approvals(user_id,phone_e164,reason)
    values(:'admin_id','+250788100004','Synthetic approved platform operator');
    insert into auth.sessions(id,user_id,created_at)
    values('81010000-0000-4000-8000-000000000004',:'admin_id',clock_timestamp());
  SQL
  journey = journey.gsub("json_build_object('sub', :'admin_id', 'role', 'authenticated')",
    "json_build_object('sub', :'admin_id', 'role', 'authenticated', 'session_id', '81010000-0000-4000-8000-000000000004')")
  puts sql(DB, combined_fixture(journey, :journey))
  puts sql(DB, combined_fixture(File.read(ROOT + '/scripts/tests/group_admin_contract.sql').sub('collect_uat_20260902', DB), :group))
  puts 'PLATFORM_AND_MEMBER_REGRESSIONS_PASS'
elsif ARGV == ['--hybrid-regressions'] && COMBINED
  fixture = File.read(ROOT + '/scripts/tests/hybrid_backend_uat.sql').sub('collect_hybrid_uat_20260902', DB)
  marker = "update public.profiles set is_platform_admin=true where id='96000000-0000-4000-8000-000000000001';"
  abort('Hybrid operator fixture changed') unless fixture.include?(marker)
  fixture = fixture.sub(marker, <<~SQL)
    insert into public.admin_user_roles(user_id,role_id,reason)
    select '96000000-0000-4000-8000-000000000001',id,'Synthetic combined operator' from public.admin_roles where name='platform_owner';
    insert into collect_admin_access.whatsapp_approvals(user_id,phone_e164,reason)
    values('96000000-0000-4000-8000-000000000001','+250788000001','Synthetic combined operator');
    insert into auth.sessions(id,user_id,created_at)
    values('96010000-0000-4000-8000-000000000001','96000000-0000-4000-8000-000000000001',clock_timestamp());
  SQL
  fixture = fixture.gsub(%q{"sub":"96000000-0000-4000-8000-000000000001","role":"authenticated"},
    %q{"sub":"96000000-0000-4000-8000-000000000001","role":"authenticated","session_id":"96010000-0000-4000-8000-000000000001"})
  puts sql(DB, fixture)
  puts 'COMBINED_HYBRID_REGRESSIONS_PASS'
elsif ARGV.empty?
  puts sql(DB, combined_fixture(File.read(__dir__ + '/platform_admin_access_contract.sql').sub('collect_platform_access_uat_20260902', DB), :platform))
else
  abort('Usage: platform_admin_access_uat.rb [--setup|--migrate|--refresh-functions|--member-regressions|--hybrid-regressions] [--replay|--final|--combined]')
end
