# Approved production logical-backup attempt. No SQL writes, migrations, role
# changes, provider sends, restore, or paid services. The only hosted mutation
# is the explicitly approved single-IP network rule, removed in ensure.
require_relative 'collect_backup_network_probe'
require 'open3'
require 'digest'
require 'securerandom'
require 'base64'
require 'openssl'

REF = CollectBackupNetworkProbe::REF
APPROVED_IP = '129.222.149.205'.freeze
IMAGE = 'sha256:3f8ad1de081c241b0ed59468590ed789453f352daeff3bc4dff2b169b3bbf43a'.freeze
VAULT = '/Users/jeanbosco/Library/Application Support/CollectRecovery/bin/collect-recovery-vault'.freeze
CA_URL = 'https://supabase-downloads.s3-ap-southeast-1.amazonaws.com/prod/ssl/prod-ca-2021.crt'.freeze
CA_DER_SHA256 = '807025ad50d4ed219d2c9c7d299c004f824eb00cf7f65afef607d07b72e6cafa'.freeze

# Password and CA arrive only on stdin, into a private container tmpfs. There
# are no host bind mounts: Docker's file-sharing service otherwise retains a
# directory handle that can prevent safe encrypted-volume detach on macOS.
CLIENT_BOOTSTRAP = <<~'SH'.freeze
  set -eu
  umask 077
  IFS= read -r passline
  IFS= read -r caline
  printf '%s\n' "$passline" > /run/collect/pgpass
  printf '%s' "$caline" | base64 -d > /run/collect/root.crt
  unset passline caline
  exec "$@"
SH

def supabase_ca
  uri = URI(CA_URL)
  http = Net::HTTP.new(uri.host, 443)
  http.use_ssl = true
  http.open_timeout = 15
  http.read_timeout = 30
  response = http.request(Net::HTTP::Get.new(uri))
  raise 'Official CA download failed' unless response.is_a?(Net::HTTPSuccess)
  cert = OpenSSL::X509::Certificate.new(response.body)
  raise 'Official CA fingerprint mismatch' unless Digest::SHA256.hexdigest(cert.to_der) == CA_DER_SHA256
  raise 'Official CA outside validity period' unless cert.not_before <= Time.now && cert.not_after > Time.now
  response.body
end

def private_write(path, content)
  File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |file| file.write(content); file.fsync }
end

def command(*arguments, input: '')
  out, err, status = Open3.capture3(*arguments, stdin_data: input, binmode: true)
  [out, err, status]
end

def vault(action, identifier)
  out, _err, status = command(VAULT, action, identifier)
  raise "Vault #{action} failed; no plaintext fallback" unless status.success?
  JSON.parse(out)
end

def api(token, path, payload = nil)
  uri = URI("https://api.supabase.com/v1/projects/#{REF}#{path}")
  request = payload ? Net::HTTP::Post.new(uri) : Net::HTTP::Get.new(uri)
  request['Authorization'] = "Bearer #{token}"
  if payload
    request['Content-Type'] = 'application/json'
    request.body = JSON.generate(payload)
  end
  http = Net::HTTP.new(uri.host, 443)
  http.use_ssl = true
  http.open_timeout = 15
  http.read_timeout = 45
  response = http.request(request)
  raise "Management HTTP #{response.code} at #{path}" unless response.is_a?(Net::HTTPSuccess)
  JSON.parse(response.body)
end

def wait_network(token)
  20.times do
    network = api(token, '/network-restrictions')
    return network if network['status'] == 'applied'
    sleep 3
  end
  raise 'Network configuration did not reach applied state within 60 seconds'
end

def configuration(network)
  network.fetch('config').slice('dbAllowedCidrs', 'dbAllowedCidrsV6').tap do |config|
    raise 'Invalid IPv4/IPv6 configuration' unless config.values.length == 2 && config.values.all? { |value| value.is_a?(Array) }
  end
end

def pgpass_field(value)
  raise 'Newline in database credential' if value.match?(/[\r\n\0]/)
  value.gsub(/[\\:]/) { |character| "\\#{character}" }
end

def failure_class(text)
  case text
  when /password authentication failed/i then 'database_password_authentication_failed'
  when /certificate.*failed|root certificate|SSL error/i then 'tls_certificate_validation_failed'
  when /permission denied/i then 'database_object_permission_denied'
  when /timeout expired|timed out/i then 'database_connection_timeout'
  when /Network is unreachable|Cannot assign requested address/i then 'network_route_unavailable'
  when /no pg_hba.conf entry/i then 'database_connection_policy_denied'
  else 'database_client_failed_see_encrypted_log'
  end
end

if $PROGRAM_NAME == __FILE__
  abort('Usage: collect_encrypted_database_backup.rb --approved-ip-129.222.149.205 NEW_REPORT.json [--roles-only]') unless [2,3].include?(ARGV.length) && ARGV[0] == '--approved-ip-129.222.149.205' && (ARGV.length == 2 || ARGV[2] == '--roles-only')
  roles_only = ARGV[2] == '--roles-only'
  report_path = ARGV[1]
  raise 'New JSON report required' unless report_path.end_with?('.json') && !File.exist?(report_path)
  raise 'Linked project mismatch' unless File.read(File.join(CollectBackupNetworkProbe::ROOT, 'supabase/.temp/project-ref')).strip == REF
  STDOUT.sync = true
  puts 'Awaiting credentials on non-echoing stdin.'
  input = STDIN.tty? ? STDIN.noecho(&:gets) : STDIN.gets
  credential = JSON.parse(input)
  input.clear
  raise 'Source project mismatch' unless credential.fetch('project_url') == "https://#{REF}.supabase.co"
  source = CollectBackupNetworkProbe.database_endpoint(credential.fetch('database_url'))
  token = credential.fetch('access_token')
  identifier = "collect-production-#{Time.now.utc.strftime('%Y%m%dT%H%M%S').downcase}-#{SecureRandom.hex(3)}"
  report = { started_at: Time.now.utc.iso8601, project: REF, mode: 'approved_encrypted_database_backup',
    migration_applied: false, database_writes: false, network_rule: APPROVED_IP + '/32',
    capture_scope: roles_only ? 'global_roles_without_passwords' : 'database',
    result: 'IN_PROGRESS', cleanup: {}, limitations: [
      'Database archive excludes Storage object bytes, global role passwords and provider configuration',
      'No production restore or off-site recovery demonstrated',
      'Recovery key remains in this Mac Keychain; independent key escrow still needed'] }
  mounted = false
  may_have_added_rule = false
  original = nil
  begin
    project = api(token, '')
    raise 'Authenticated project mismatch' unless project['id'] == REF && project['name'] == 'COOL' && project['status'] == 'ACTIVE_HEALTHY'
    ip_text, _, ip_status = command('docker', 'run', '--rm', '--read-only', '--entrypoint', 'curl', IMAGE,
      '--fail', '--silent', '--show-error', '--max-time', '15', 'https://api.ipify.org?format=json')
    raise 'Could not verify database-client egress' unless ip_status.success?
    raise 'Current IP differs from specific approval; no network rule changed' unless JSON.parse(ip_text).fetch('ip') == APPROVED_IP
    network = wait_network(token)
    original = configuration(network)
    report[:network_before] = original
    rows = api(token, '/config/database/pooler')
    primary = rows.select { |row| row['database_type'] == 'PRIMARY' }
    raise 'Ambiguous primary pooler' unless primary.length == 1
    host = primary.first.fetch('db_host')
    raise 'Unexpected authenticated pooler host' unless host.match?(/\Aaws-[0-9]+-[a-z0-9-]+\.pooler\.supabase\.com\z/)
    # Supabase documents this same shared host on 5432 for session mode. Do not
    # change the server's pooler configuration or use transaction port 6543.
    user = "postgres.#{REF}"
    report[:database_route] = { host: host, port: 5432, mode: 'session', tls: 'verify-full' }
    vault_info = vault('create', identifier)
    report[:vault] = vault_info
    mount_info = vault('attach', identifier)
    mounted = true
    mount = mount_info.fetch('mount')
    password = URI::DEFAULT_PARSER.unescape(source.password)
    client_input = [host, '5432', 'postgres', user, password].map { |value| pgpass_field(value) }.join(':') + "\n" + Base64.strict_encode64(supabase_ca) + "\n"
    password.clear
    report[:ca] = { url: CA_URL, der_sha256: CA_DER_SHA256 }
    puts 'Encrypted destination mounted; official CA pinned; credentials stay in memory/tmpfs.'
    cidr = APPROVED_IP + '/32'
    unless original.fetch('dbAllowedCidrs').include?(cidr)
      raise 'Network configuration changed during preflight' unless configuration(api(token, '/network-restrictions')) == original
      may_have_added_rule = true # Set BEFORE the call, including uncertain replies.
      api(token, '/network-restrictions/apply', original.merge('dbAllowedCidrs' => original.fetch('dbAllowedCidrs') + [cidr]))
      changed = configuration(wait_network(token))
      raise 'Temporary rule or preserved rules mismatch' unless changed == original.merge('dbAllowedCidrs' => original.fetch('dbAllowedCidrs') + [cidr])
      puts 'Approved temporary /32 rule applied and existing rules verified.'
    end
    report[:network_temporary_applied] = true
    common = ['docker', 'run', '--rm', '-i', '--read-only', '--cap-drop=ALL', '--security-opt=no-new-privileges',
      '--user', '1000:1000', '--tmpfs', '/run/collect:rw,noexec,nosuid,size=1m,mode=0700,uid=1000,gid=1000',
      '--env', 'PGPASSFILE=/run/collect/pgpass', '--env', 'PGSSLMODE=verify-full',
      '--env', 'PGSSLROOTCERT=/run/collect/root.crt', '--env', 'PGCONNECT_TIMEOUT=15',
      '--env', 'PGOPTIONS=-c default_transaction_read_only=on -c statement_timeout=120000']
    connect = ['-w', '-h', host, '-p', '5432', '-U', user, '-d', 'postgres']
    out, err, status = command(*common, '--entrypoint', 'sh', IMAGE, '-c', CLIENT_BOOTSTRAP, 'sh',
      'psql', *connect, '-XAt', '-v', 'ON_ERROR_STOP=1',
      '-c', 'select json_build_object(\'database\',current_database(),\'version\',current_setting(\'server_version\'),\'migrations\',(select count(*) from supabase_migrations.schema_migrations));', input: client_input)
    unless status.success?
      private_write(File.join(mount, 'connection-error.log'), err)
      raise failure_class(err)
    end
    report[:source_check] = JSON.parse(out)
    raise 'Unexpected source migration state' unless report[:source_check]['database'] == 'postgres' && report[:source_check]['migrations'] == 97
    puts 'Read-only production database connection verified; starting logical capture.'
    if roles_only
      out, err, status = command(*common, '--entrypoint', 'sh', IMAGE, '-c', CLIENT_BOOTSTRAP, 'sh',
        'pg_dumpall', '-w', '-h', host, '-p', '5432', '-U', user, '-l', 'postgres',
        '--roles-only', '--no-role-passwords', input: client_input)
    else
      out, err, status = command(*common, '--entrypoint', 'sh', IMAGE, '-c', CLIENT_BOOTSTRAP, 'sh',
        'pg_dump', *connect, '--format=custom', '--lock-wait-timeout=10s', input: client_input)
    end
    private_write(File.join(mount, 'pg-dump.log'), err)
    raise failure_class(err) unless status.success?
    archive = File.join(mount, roles_only ? 'roles.sql' : 'database.dump')
    raise 'Role export unexpectedly contains password clauses' if roles_only && out.match?(/\bPASSWORD\s+(?:'|NULL)/i)
    private_write(archive, out)
    out.clear
    report[:archive] = { bytes: File.size(archive), sha256: Digest::SHA256.file(archive).hexdigest }
    raise 'Empty database archive' unless report[:archive][:bytes] > 1024
    if roles_only
      report[:archive][:roles_without_passwords] = true
      report[:archive][:role_definitions] = File.read(archive).lines.count { |line| line.start_with?('CREATE ROLE ') }
    else
      out, err, status = command('docker', 'run', '--rm', '-i', '--read-only', '--network', 'none',
        '--entrypoint', 'pg_restore', IMAGE, '--list', input: File.binread(archive))
      raise 'Archive table-of-contents read failed' unless status.success?
      private_write(File.join(mount, 'database.toc'), out)
      report[:archive][:toc_entries] = out.lines.count { |line| line.match?(/\A[0-9]+;/) }
      report[:archive][:schemas_seen] = %w[public auth storage private collect_member_actions collect_admin_access collect_hybrid supabase_migrations].select { |schema| out.include?(" #{schema} ") }
    end
    client_input.clear
    report[:cleanup][:credential_tmpfs_destroyed_with_clients] = true
    vault('detach', identifier)
    mounted = false
    vault('readonly', identifier)
    mounted = true
    raise 'Archive differs after encrypted-volume remount' unless Digest::SHA256.file(archive).hexdigest == report[:archive][:sha256]
    report[:archive][:hash_verified_after_remount] = true
    report[:result] = 'DATABASE_ARCHIVE_CAPTURED_NOT_FULL_RECOVERY_ACCEPTANCE'
    puts 'Logical capture verified after encrypted read-only remount.'
  rescue StandardError => error
    report[:result] = 'FAILED_NO_MIGRATIONS_APPLIED'
    # Errors emitted here are controlled helper strings; never print raw clients.
    report[:error] = error.message.gsub(token, '[redacted]').gsub(source.password.to_s, '[redacted]')
    puts "Backup attempt stopped: #{report[:error]}"
  ensure
    begin
      if may_have_added_rule
        current = configuration(wait_network(token))
        cidr = APPROVED_IP + '/32'
        if current.fetch('dbAllowedCidrs').include?(cidr)
          remaining = current.merge('dbAllowedCidrs' => current.fetch('dbAllowedCidrs') - [cidr])
          api(token, '/network-restrictions/apply', remaining)
          raise 'Network cleanup readback mismatch' unless configuration(wait_network(token)) == remaining
        end
        report[:cleanup][:temporary_network_rule_removed] = true
        report[:network_after] = configuration(api(token, '/network-restrictions'))
        puts 'Temporary network rule removed and read back.'
      else
        report[:cleanup][:temporary_network_rule_added] = false
      end
    rescue StandardError
      report[:cleanup][:network_requires_attention] = true
      puts 'ATTENTION: temporary network rule cleanup is unconfirmed; inspect before ending work.'
    end
    if mounted
      begin
        vault('detach', identifier)
        report[:cleanup][:vault_detached] = true
      rescue StandardError
        report[:cleanup][:vault_requires_attention] = true
        puts 'ATTENTION: encrypted vault detach is unconfirmed.'
      end
    end
    report[:finished_at] = Time.now.utc.iso8601
    private_write(report_path, JSON.pretty_generate(report) + "\n")
    token.clear
    client_input&.clear
    credential.fetch('database_url').clear
  end
  exit(report[:result].start_with?('DATABASE_ARCHIVE') && !report[:cleanup].keys.any? { |key| key.to_s.end_with?('requires_attention') } ? 0 : 1)
end
