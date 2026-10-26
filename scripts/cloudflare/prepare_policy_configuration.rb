# frozen_string_literal: true
require_relative 'prepare_public_configuration'

# Reuses the maintained legal conversion. It does not load, certify or republish
# compiled mobile defaults and has no network or database execution path.
class CollectExistingPolicyConfigurationPayload < CollectPublicConfigurationPayload
  GENERATOR = 'scripts/cloudflare/prepare_policy_configuration.rb'

  def initialize(root:, api_source_id:)
    @root = File.expand_path(root)
    raise 'Physical source root required' unless File.realpath(@root) == @root && File.directory?(@root)
    raise 'Invalid API source identity' unless api_source_id.is_a?(String) && api_source_id.match?(SHA)
    @api_source_id = api_source_id
    @source_inputs = {}; @coverage = {}
  end

  def payload
    bundle = yaml(BUNDLE)
    raise 'Legal source review status changed' unless bundle.dig('site', 'content_status') == 'draft_for_legal_review'
    @bundle_pages = bundle.fetch('pages')
    values = LEGAL_SOURCES.to_h { |kind, _| ['policy:' + kind, policy(kind)] }
    read_source(CollectPublicConfigurationPayload::GENERATOR)
    read_source(GENERATOR)
    records = values.sort.map { |key, value| { 'key' => key, 'value_json' => JSON.generate(value) } }
    raise 'Policy configuration exceeds bound' if records.sum { |r| r.fetch('value_json').bytesize } > 131_072
    { 'schema_version' => 1, 'kind' => 'collect_existing_policy_configuration', 'api_source_id' => @api_source_id,
      'legal_release_approved' => false, 'provider_approved' => false, 'retention_policy_activation' => false,
      'source_inputs' => @source_inputs.sort.to_h, 'records' => records }
  end
end

if $PROGRAM_NAME == __FILE__
  options = {}
  OptionParser.new do |p|
    %w[root api-source-id out].each { |name| p.on('--' + name + ' VALUE') { |value| raise 'Duplicate argument' if options.key?(name); options[name] = value } }
  end.parse!
  raise 'Exactly three explicit preparation arguments required' unless ARGV.empty? && options.keys.sort == %w[api-source-id out root]
  generator = CollectExistingPolicyConfigurationPayload.new(root: options.fetch('root'), api_source_id: options.fetch('api-source-id'))
  payload = generator.payload
  out = File.expand_path(options.fetch('out')); Dir.mkdir(out, 0o700)
  raw = JSON.pretty_generate(payload) + "\n"
  File.open(File.join(out, 'payload.json'), File::WRONLY | File::CREAT | File::EXCL, 0o600) { |f| f.write(raw) }
  receipt = { 'status' => 'prepared_only_no_database_effect', 'payload_sha256' => Digest::SHA256.hexdigest(raw),
    'source_inputs' => generator.source_inputs, 'coverage' => generator.coverage,
    'mobile_defaults_loaded_or_certified' => false, 'static_website_rebuilt' => false,
    'legal_release_approved' => false, 'provider_approved' => false, 'retention_policy_activation' => false }
  File.open(File.join(out, 'preparation.json'), File::WRONLY | File::CREAT | File::EXCL, 0o600) { |f| f.write(JSON.pretty_generate(receipt) + "\n") }
  puts JSON.generate({ 'status' => receipt['status'], 'payload_sha256' => receipt['payload_sha256'], 'keys' => payload.fetch('records').map { |r| r.fetch('key') } })
end
