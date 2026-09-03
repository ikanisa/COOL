require 'open3'

# Schema-only LOCAL replay fixture. Never connects to hosted Supabase, copies
# customer data, or alters a shared UAT database.
ROOT = File.expand_path('../..', __dir__)
CONTAINER = 'supabase_db_collect_release_replay_20260902'
SOURCE_DB = 'postgres'
DB = 'collect_directory_presentation_v2_uat_20260903'
BASE = ['docker', 'exec', '-i', CONTAINER, 'psql', '-XqAt', '-U', 'supabase_admin', '-v', 'ON_ERROR_STOP=1'].freeze

def sql(database, statement)
  out, err, status = Open3.capture3(*BASE, '-d', database, stdin_data: statement)
  abort(err) unless status.success?
  warn(err) unless err.empty?
  out
end

if ARGV == ['--setup'] || ARGV == ['--resume-empty-setup']
  if ARGV == ['--setup']
    abort('Refusing to overwrite existing directory UAT database') unless sql('postgres', "select datname from pg_database where datname='#{DB}';").strip.empty?
    sql('postgres', "create database #{DB} template template0;")
  else
    abort('Only an empty, rolled-back setup can resume') unless sql(DB, "select count(*) from pg_class where relnamespace='public'::regnamespace;").strip == '0'
  end
  schema, err, status = Open3.capture3('docker', 'exec', CONTAINER, 'pg_dump', '-U', 'postgres', '-d', SOURCE_DB, '--schema-only', '--no-owner', '--no-publications', '--no-subscriptions', '--exclude-schema=cron')
  abort(err) unless status.success?
  # pg_cron can only install in the server's configured scheduler database.
  # Omit the scheduler extension/ACLs, never the application ACLs or RLS.
  schema = schema.lines.reject do |line|
    (line.start_with?('ALTER DEFAULT PRIVILEGES FOR ROLE ') && !line.start_with?('ALTER DEFAULT PRIVILEGES FOR ROLE postgres ')) ||
      line.start_with?('CREATE EXTENSION IF NOT EXISTS pg_cron ', 'COMMENT ON EXTENSION pg_cron ') ||
      line.match?(/\A(?:GRANT|REVOKE) .* ON (?:FUNCTION|TABLE|SCHEMA) cron[. ]/)
  end.join
  sql(DB, "begin;\n#{schema}\ncommit;")
  data, err, status = Open3.capture3('docker', 'exec', CONTAINER, 'pg_dump', '-U', 'postgres', '-d', SOURCE_DB, '--data-only', '--no-owner', '--table=public.admin_roles', '--table=public.admin_permissions', '--table=public.admin_role_permissions')
  abort(err) unless status.success?
  sql(DB, data)
  puts 'Created schema-only local directory UAT database with reference roles only.'
elsif ARGV.empty?
  abort('Synthetic fixture is not empty') unless sql(DB, 'select count(*) from auth.users;').strip == '0'
  abort('Current directory prerequisite missing') unless sql(DB, "select to_regclass('collect_hybrid.member_account_claims') is not null;").strip == 't'
  sql(DB, "insert into public.admin_queue_specs(rpc_name,title,subtitle,required_permission) values('admin_list_members','Members','Users only','users.read') on conflict (rpc_name) do nothing;")
  sql(DB, File.read(ROOT + '/supabase/migrations/20260903200322_hybrid_directory_presentation.sql'))
  puts sql(DB, File.read(__dir__ + '/hybrid_directory_presentation_uat.sql')).lines.grep(/^(PASS |HYBRID_)/)
else
  abort('Usage: ruby scripts/tests/hybrid_directory_presentation_uat.rb [--setup|--resume-empty-setup]')
end
