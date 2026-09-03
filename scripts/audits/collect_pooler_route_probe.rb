# Read-only route metadata; credential values and connection strings are withheld.
require_relative 'collect_backup_network_probe'

STDOUT.sync = true
puts 'Awaiting credentials on non-echoing stdin.'
input = STDIN.tty? ? STDIN.noecho(&:gets) : STDIN.gets
credential = JSON.parse(input)
input.clear
ref = CollectBackupNetworkProbe::REF
raise 'Source project mismatch' unless credential.fetch('project_url') == "https://#{ref}.supabase.co"
CollectBackupNetworkProbe.database_endpoint(credential.fetch('database_url'))
token = credential.fetch('access_token')
get = lambda do |path|
  uri = URI("https://api.supabase.com/v1/projects/#{ref}#{path}")
  request = Net::HTTP::Get.new(uri)
  request['Authorization'] = "Bearer #{token}"
  http = Net::HTTP.new(uri.host, 443)
  http.use_ssl = true
  http.open_timeout = 15
  http.read_timeout = 30
  response = http.request(request)
  raise "HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)
  JSON.parse(response.body)
end
project = get.call('')
raise 'Authenticated project mismatch' unless project['id'] == ref && project['name'] == 'COOL'
rows = get.call('/config/database/pooler')
report = rows.map do |row|
  connection = row['connection_string'] || row['connectionString'] || ''
  host = connection[/@([a-z0-9.-]+):([0-9]+)\//, 1]
  port = connection[/@([a-z0-9.-]+):([0-9]+)\//, 2]
  row.slice('database_type', 'db_host', 'db_port', 'db_name', 'pool_mode').merge(
    'connection_host' => host, 'connection_port' => port && port.to_i,
    'connection_has_project_user' => connection.include?("postgres.#{ref}"))
end
puts JSON.pretty_generate(report)
token.clear
credential.fetch('database_url').clear
