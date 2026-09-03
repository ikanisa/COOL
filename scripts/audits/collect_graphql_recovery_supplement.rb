# Read the exact Supabase-managed wrapper omitted from pg_dump as an extension
# member. No schema mutation; this is recovery metadata, not customer records.
require_relative 'collect_encrypted_database_backup'

output = ARGV.fetch(0)
raise 'New JSON output required' unless output.end_with?('.json') && !File.exist?(output)
STDOUT.sync = true
puts 'Awaiting credential on non-echoing stdin.'
raw = STDIN.tty? ? STDIN.noecho(&:gets) : STDIN.gets
credential = JSON.parse(raw)
raw.clear
raise 'Source mismatch' unless credential.fetch('project_url') == "https://#{REF}.supabase.co"
token = credential.fetch('access_token')
begin
  project = api(token, '')
  raise 'Authenticated project mismatch' unless project['id'] == REF && project['name'] == 'COOL'
  data = api(token, '/database/query', {read_only: true, query: <<~SQL}).first
    select pg_get_functiondef(p.oid) as definition,
      pg_get_userbyid(p.proowner) as owner,
      (select e.extname from pg_depend d join pg_extension e on e.oid=d.refobjid
       where d.classid='pg_proc'::regclass and d.objid=p.oid and d.deptype='e') as extension,
      (select jsonb_agg(jsonb_build_object('name',extname,'version',extversion) order by extname) from pg_extension) as installed_extensions,
      (select jsonb_agg(jsonb_build_object('name',extname,'owner',pg_get_userbyid(extowner)) order by extname) from pg_extension) as extension_owners
    from pg_proc p where p.oid=to_regprocedure('graphql_public.graphql(text,text,jsonb,jsonb)');
  SQL
  raise 'Unexpected recovery wrapper identity' unless data && data['definition'].start_with?('CREATE OR REPLACE FUNCTION graphql_public.graphql(') &&
    data['owner'] == 'supabase_admin' && data['extension'] == 'pg_graphql'
  report = { captured_at: Time.now.utc.iso8601, project: REF, mode: 'read_only_recovery_metadata',
    definition_sha256: Digest::SHA256.hexdigest(data.fetch('definition')), wrapper: data }
  private_write(output, JSON.pretty_generate(report)+"\n")
  puts JSON.pretty_generate(report)
ensure
  token.clear
end
