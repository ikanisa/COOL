require 'open3'

# Explicit isolated LOCAL database. Never reads production, customer records,
# environment credentials or changes the shared member/mobile UAT database.
ROOT = File.expand_path('../..', __dir__)
DB = 'collect_hybrid_uat_20260902'
BASE = %w[docker exec -i supabase_db_collect psql -XqAt -U postgres -v ON_ERROR_STOP=1].freeze

def sql(database, input)
  out, err, status = Open3.capture3(*BASE, '-d', database, stdin_data: input)
  abort(err) unless status.success?
  out
end

if ARGV == ['--setup']
  abort('Refusing to overwrite existing hybrid UAT database') unless sql('postgres', "select datname from pg_database where datname='#{DB}';").strip.empty?
  sql('postgres', "create database #{DB} template template0;")
  schema, err, status = Open3.capture3('docker', 'exec', 'supabase_db_collect', 'pg_dump',
    '-U', 'postgres', '-d', 'collect_uat_20260902', '--schema-only', '--no-owner', '--no-publications', '--no-subscriptions')
  abort(err) unless status.success?
  # A local postgres role cannot alter another owner's future default ACLs.
  # Keep all actual object grants and RLS; omit only foreign-role defaults.
  schema = schema.lines.reject { |line| line.start_with?('ALTER DEFAULT PRIVILEGES FOR ROLE ') && !line.start_with?('ALTER DEFAULT PRIVILEGES FOR ROLE postgres ') }.join
  sql(DB, schema)
  puts 'Created isolated schema-only hybrid UAT database. No user data copied.'
elsif ARGV == ['--migrate']
  files = Dir[ROOT + '/supabase/migrations/*_hybrid_receipt_capture_contract.sql'] +
    Dir[ROOT + '/supabase/migrations/*_hybrid_member_registry.sql']
  abort('Expected candidate migrations not found') if files.empty?
  files.sort.each { |file| sql(DB, File.read(file)); puts "Applied locally: #{File.basename(file)}" }
elsif ARGV.empty?
  puts sql(DB, File.read(__dir__ + '/hybrid_backend_uat.sql')).lines.grep(/^(PASS |HYBRID_)/)
else
  abort('Usage: ruby scripts/tests/hybrid_backend_uat.rb [--setup|--migrate]')
end
