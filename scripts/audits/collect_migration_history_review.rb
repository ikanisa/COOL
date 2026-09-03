# Read-only, exact-project history comparison. Never exports statement bodies.
require 'json'
require 'net/http'
require 'io/console'
require 'digest'
require 'time'
require_relative 'collect_hosted_preflight'

module CollectMigrationHistoryReview
  def self.compare(rows, directory)
    rows.map do |row|
      version = row.fetch('version')
      raise 'Unexpected version' unless %w[202605230012 202605230013 202605230014].include?(version)
      paths = Dir[File.join(directory, "#{version}_*.sql")]
      raise 'Local version ambiguous' unless paths.one?
      local = File.read(paths.first)
      statements = row.fetch('statements')
      raise 'Stored statement history missing' unless statements.is_a?(Array) && !statements.empty?
      joined = statements.join("\n")
      # Diagnostic only: no claim of semantic equivalence or authority to repair
      # migration history. Report raw digests separately from textual comparison.
      compact = ->(s) { s.gsub(/--[^\n]*/, '').gsub(/\s+/, '').sub(/;\z/, '') }
      {
        version: version, remote_name: row.fetch('name'), local_file: File.basename(paths.first),
        remote_statement_count: statements.length,
        declared_function_names: joined.scan(/\bcreate(?:\s+or\s+replace)?\s+function\s+(?:public\.)?([a-z_][a-z0-9_]*)\s*\(/i).flatten.uniq.sort,
        local_sha256: Digest::SHA256.hexdigest(local),
        remote_joined_sha256: Digest::SHA256.hexdigest(joined),
        exact_joined_text_match: joined == local,
        whitespace_comment_insensitive_match: compact.call(joined) == compact.call(local)
      }
    end
  end

  def self.run(path)
    raise 'New JSON report path required' unless path.end_with?('.json') && !File.exist?(path)
    ref = CollectHostedPreflight::REF
    raise 'Linked project mismatch' unless File.read(CollectHostedPreflight::ROOT + '/supabase/.temp/project-ref').strip == ref
    STDOUT.sync = true
    puts 'Awaiting credential on non-echoing stdin; statement bodies are not saved.'
    input = STDIN.tty? ? STDIN.noecho(&:gets) : STDIN.gets
    credential = JSON.parse(input.to_s)
    input&.clear
    raise 'Credential source mismatch' unless credential.fetch('project_url') == "https://#{ref}.supabase.co"
    token = credential.fetch('access_token')
    request = lambda do |suffix, query = nil|
      uri = URI("https://api.supabase.com/v1/projects/#{ref}#{suffix}")
      req = query ? Net::HTTP::Post.new(uri) : Net::HTTP::Get.new(uri)
      req['Authorization'] = "Bearer #{token}"
      if query
        req['Content-Type'] = 'application/json'
        req.body = JSON.generate(query: query, read_only: true)
      end
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 15
      http.read_timeout = 45
      response = http.request(req)
      raise "HTTP #{response.code} at #{suffix}" unless response.is_a?(Net::HTTPSuccess)
      JSON.parse(response.body)
    end
    project = request.call('')
    raise 'Remote target mismatch' unless project['id'] == ref && project['name'] == 'COOL'
    rows = request.call('/database/query', <<~SQL)
      select version,name,statements from supabase_migrations.schema_migrations
      where version in ('202605230012','202605230013','202605230014') order by version;
    SQL
    raise 'Incomplete history response' unless rows.length == 3
    retired = request.call('/database/query', <<~SQL)
      select name, exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
        where n.nspname='public' and p.proname=names.name) as still_exists
      from unnest(array['admin_manage_admin_user_roles','admin_manage_feature_flag',
        'admin_manage_receiver','admin_manage_system_setting','admin_update_user_status','hash_phone']) names(name)
      order by name;
    SQL
    report = { captured_at: Time.now.utc.iso8601, project: ref, mode: 'read_only_no_history_repair',
      comparisons: compare(rows, CollectHostedPreflight::ROOT + '/supabase/migrations'),
      retired_helpers_from_followup_migration_202605230016: retired,
      limitations: ['Text comparison is not SQL semantic equivalence or a complete deployed-schema diff'] }
    File.open(path, File::WRONLY|File::CREAT|File::EXCL, 0o600) { |file| file.write(JSON.pretty_generate(report) + "\n") }
    puts JSON.pretty_generate(report)
  ensure
    token&.clear
  end
end

CollectMigrationHistoryReview.run(ARGV.fetch(0)) if $PROGRAM_NAME == __FILE__
