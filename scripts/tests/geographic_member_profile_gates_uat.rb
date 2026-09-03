require 'open3'
require 'json'

# Fixed local replay target: no URL, credentials or production mode accepted.
abort('No arguments accepted') unless ARGV.empty?
root = File.expand_path('../..', __dir__)
migration = File.read(File.join(root, 'supabase/migrations/20260903201326_geographic_member_profile_gates.sql'))
tests = File.read(File.join(__dir__, 'geographic_member_profile_gates_uat.sql'))
sql = "begin;\nset local statement_timeout = '30s';\n" +
  migration.sub(/\Abegin;\s*/, '').sub(/commit;\s*\z/, '') + tests + "\nrollback;\n"
out, err, result = Open3.capture3(
  'docker', 'exec', '-i', 'supabase_db_collect_release_replay_20260902',
  'psql', '-U', 'postgres', '-d', 'postgres', '-X', '-q', '-v', 'ON_ERROR_STOP=1',
  stdin_data: sql
)
puts out
warn err unless err.empty?
abort('Local profile-gate UAT failed; connection closure rolled back changes') unless result.success?
puts JSON.generate(status: 'LOCAL_ROLLBACK_UAT_PASS', production_writes: 0)
