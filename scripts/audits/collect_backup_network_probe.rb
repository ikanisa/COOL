# Read-only backup-route check. No network changes or database connection retry.
require 'json'
require 'net/http'
require 'io/console'
require 'ipaddr'
require 'time'

module CollectBackupNetworkProbe
  REF = 'lhbowpbcpwoiparwnwgt'.freeze
  ROOT = File.expand_path('../..', __dir__)

  def self.database_endpoint(value)
    database = URI.parse(value)
    direct = database.host == "db.#{REF}.supabase.co"
    session_pooler = database.host.to_s.match?(/\Aaws-[0-9]+-[a-z0-9-]+\.pooler\.supabase\.com\z/) &&
      database.user == "postgres.#{REF}"
    valid = %w[postgres postgresql].include?(database.scheme) &&
      (direct || session_pooler) && (database.port || 5432) == 5432 &&
      database.path == '/postgres' && !database.password.to_s.empty?
    raise 'Unexpected database endpoint; value withheld' unless valid
    database
  rescue URI::InvalidURIError, TypeError
    raise 'Stored database URL cannot be parsed; value withheld'
  end

  def self.explicitly_allowed?(ip, network)
    address = IPAddr.new(ip)
    rules = network.fetch('config').fetch(address.ipv4? ? 'dbAllowedCidrs' : 'dbAllowedCidrsV6')
    raise 'Invalid network-rule response' unless rules.is_a?(Array)
    # Empty or missing rules must never become permission to change access.
    parsed = rules.map { |cidr| IPAddr.new(cidr) }
    parsed.any? { |rule| rule.include?(address) }
  end

  def self.run(path)
    raise 'A new JSON report is required' unless path.end_with?('.json') && !File.exist?(path)
    raise 'Linked project mismatch' unless File.read(File.join(ROOT, 'supabase/.temp/project-ref')).strip == REF
    STDOUT.sync = true
    puts 'Awaiting source credentials on non-echoing stdin.'
    input = STDIN.tty? ? STDIN.noecho(&:gets) : STDIN.gets
    credentials = JSON.parse(input.to_s)
    input&.clear
    raise 'Project URL mismatch' unless credentials.fetch('project_url') == "https://#{REF}.supabase.co"
    token = credentials.fetch('access_token')
    raise 'Invalid management credential' unless token.start_with?('sbp_')
    database = database_endpoint(credentials.fetch('database_url'))
    request = lambda do |url, query = nil|
      uri = URI(url)
      raise 'Unexpected HTTPS host' unless uri.scheme == 'https' && %w[api.supabase.com api.ipify.org].include?(uri.host)
      req = query ? Net::HTTP::Post.new(uri) : Net::HTTP::Get.new(uri)
      req['Authorization'] = "Bearer #{token}" if uri.host == 'api.supabase.com'
      if query
        req['Content-Type'] = 'application/json'
        req.body = JSON.generate(query: query, read_only: true)
      end
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 15
      http.read_timeout = 30
      response = http.request(req)
      raise "HTTP #{response.code} from #{uri.host}" unless response.is_a?(Net::HTTPSuccess)
      JSON.parse(response.body)
    end
    base = "https://api.supabase.com/v1/projects/#{REF}"
    project = request.call(base)
    raise 'Authenticated project mismatch' unless project['id'] == REF && project['name'] == 'COOL'
    network = request.call(base + '/network-restrictions')
    ip = request.call('https://api.ipify.org?format=json').fetch('ip')
    allowed = explicitly_allowed?(ip, network)
    backups = request.call(base + '/database/backups')
    counts = request.call(base + '/database/query', <<~SQL).first
      select (select count(*) from supabase_migrations.schema_migrations) as migrations,
        pg_database_size(current_database()) as database_bytes,
        (select count(*) from storage.objects) as storage_objects,
        (select count(*) from storage.buckets) as storage_buckets;
    SQL
    report = { captured_at: Time.now.utc.iso8601, mode: 'read_only_no_export_or_network_change',
      project: REF, project_status: project['status'], database_host: database.host,
      database_port: database.port || 5432, credential_present: !database.password.to_s.empty?,
      observed_public_ip: ip, current_address_explicitly_allowed: allowed,
      network_status: network['status'], ipv4_rules: network.dig('config','dbAllowedCidrs'),
      ipv6_rules: network.dig('config','dbAllowedCidrsV6'),
      listed_backups: backups.fetch('backups').length, pitr_enabled: backups['pitr_enabled'],
      physical_backup_metadata_present: !backups.fetch('physical_backup_data',{}).empty?,
      inventory: counts }
    File.open(path, File::WRONLY|File::CREAT|File::EXCL, 0o600) { |file| file.write(JSON.pretty_generate(report)+"\n") }
    puts JSON.pretty_generate(report)
  ensure
    input&.clear
    token&.clear
    credentials&.fetch('database_url', nil)&.clear
  end
end

CollectBackupNetworkProbe.run(ARGV.fetch(0)) if $PROGRAM_NAME == __FILE__
