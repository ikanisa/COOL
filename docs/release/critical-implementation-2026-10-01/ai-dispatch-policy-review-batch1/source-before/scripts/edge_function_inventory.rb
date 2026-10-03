# frozen_string_literal: true

require 'json'

# One deploy/readiness contract. This validates inventory and source wiring;
# handler tests and database UAT are still required to prove authorization.
module CollectEdgeInventory
  MODES = %w[user_jwt signed_auth_hook internal_signature device_signature supervisor_signature scheduler_secret].freeze
  SLUG = /\A[a-z][a-z0-9]*(?:-[a-z0-9]+)*\z/

  def self.read(root)
    path = File.join(root, 'contracts/edge-functions.json')
    raise 'Edge inventory must be a regular file' unless File.file?(path) && !File.symlink?(path)

    manifest = JSON.parse(File.read(path))
    raise 'Unsupported Edge inventory schema' unless manifest.keys.sort == %w[functions retired schema_version] && manifest['schema_version'] == 1
    entries = manifest['functions']
    retired = manifest['retired']
    raise 'Edge inventory must contain active functions' unless entries.is_a?(Array) && !entries.empty?
    raise 'Invalid retired inventory' unless retired.is_a?(Array) && retired.all? { |name| name.is_a?(String) && SLUG.match?(name) } && retired.uniq == retired

    entries.each do |entry|
      raise 'Invalid Edge function entry' unless entry.is_a?(Hash) && entry.keys.sort == %w[auth caller name required_secrets rollout status verify_jwt]
      raise 'Invalid Edge function name' unless entry['name'].is_a?(String) && SLUG.match?(entry['name'])
      raise "Unsupported lifecycle for #{entry['name']}" unless entry['status'] == 'active'
      raise "Invalid auth mode for #{entry['name']}" unless MODES.include?(entry['auth'])
      raise "JWT mode contradicts auth for #{entry['name']}" unless entry['verify_jwt'] == (entry['auth'] == 'user_jwt')
      %w[caller rollout].each { |key| raise "Missing #{key} for #{entry['name']}" unless entry[key].is_a?(String) && !entry[key].strip.empty? }
      secrets = entry['required_secrets']
      raise "Invalid secrets for #{entry['name']}" unless secrets.is_a?(Array) && secrets.uniq == secrets && secrets.all? { |name| name.is_a?(String) && /\A[A-Z][A-Z0-9_]+\z/.match?(name) }
    end
    names = entries.map { |entry| entry.fetch('name') }
    raise 'Duplicate Edge function names' unless names.uniq == names
    raise 'Active and retired functions overlap' unless (names & retired).empty?

    manifest
  end

  def self.validate(root, manifest, auth: false)
    expected = manifest.fetch('functions').map { |entry| entry.fetch('name') }.sort
    actual = Dir[File.join(root, 'supabase/functions/*/index.ts')].map { |path| File.basename(File.dirname(path)) }.sort
    raise "Edge source inventory differs: missing=#{expected - actual}, extra=#{actual - expected}" unless expected == actual

    config = File.read(File.join(root, 'supabase/config.toml'))
    blocks = config.scan(/^\[functions\.([^\]]+)\]\s*\n(.*?)(?=^\[|\z)/m)
    raise 'Duplicate function config sections' unless blocks.map(&:first).uniq.length == blocks.length
    raise 'Edge configuration inventory differs' unless blocks.map(&:first).sort == expected
    configured = blocks.to_h
    manifest.fetch('functions').each do |entry|
      values = configured.fetch(entry.fetch('name')).scan(/^verify_jwt\s*=\s*(true|false)\s*(?:#.*)?$/).flatten
      raise "JWT config differs for #{entry['name']}" unless values == [entry.fetch('verify_jwt').to_s]
      next unless auth

      source = Dir[File.join(root, "supabase/functions/#{entry['name']}/*.ts")].reject { |path| path.end_with?('_test.ts') }.map { |path| File.read(path) }.join("\n")
      required = case entry.fetch('auth')
                 when 'signed_auth_hook' then %w[verifySmsHook SEND_SMS_HOOK_SECRET]
                 when 'internal_signature' then %w[requireInternalRequest]
                 when 'device_signature' then ['crypto.subtle.verify', 'X-Collect-Gateway-Signature', 'GATEWAY_SIGNATURE_REFUSED']
                 when 'supervisor_signature' then ['crypto.subtle.verify', 'X-Collect-Supervisor-Signature', 'SUPERVISOR_SIGNATURE_REFUSED']
                 when 'scheduler_secret' then %w[COLLECT_RECEIPT_EXCEPTION_WORKER_SECRET sameSecret x-collect-receipt-worker WORKER_AUTH_REQUIRED]
                 when 'user_jwt'
                   entry['name'] == 'reconciliation-finalize' ? %w[userClient authorize_reconciliation_finalization_v2 authentication_required] : %w[requireUser]
                 end
      required.each { |token| raise "Missing #{entry['auth']} source wiring for #{entry['name']}: #{token}" unless source.include?(token) }
    end
    if auth
      signed = File.read(File.join(root, 'supabase/functions/_shared/signed_sms_hook.ts'))
      %w[webhook-id webhook-timestamp webhook-signature crypto.subtle.verify invalid_hook_signature].each do |token|
        raise "Missing signed Auth hook boundary: #{token}" unless signed.include?(token)
      end
      raise 'Retired static Auth hook header is still accepted' if signed.include?('x-hook-secret')
    end
    true
  end

  def self.run(args, root: File.expand_path('..', __dir__))
    manifest = read(root)
    action = args.shift
    raise 'Usage: edge_function_inventory.rb check|auth-check|expected|no-verify-jwt|retired|secrets' unless args.empty?
    case action
    when 'check', 'auth-check'
      validate(root, manifest, auth: action == 'auth-check')
      puts "[collect-edge-inventory] #{manifest.fetch('functions').length} active endpoints and auth configuration agree#{action == 'auth-check' ? '; source wiring checked' : ''}"
    when 'expected' then puts manifest.fetch('functions').map { |entry| entry.fetch('name') }.sort
    when 'no-verify-jwt' then puts manifest.fetch('functions').reject { |entry| entry.fetch('verify_jwt') }.map { |entry| entry.fetch('name') }.sort
    when 'retired' then puts manifest.fetch('retired').sort
    when 'secrets' then puts manifest.fetch('functions').flat_map { |entry| entry.fetch('required_secrets') }.uniq.sort
    else raise 'Unknown Edge inventory action'
    end
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    CollectEdgeInventory.run(ARGV)
  rescue StandardError => error
    warn "[collect-edge-inventory][FAIL] #{error.message}"
    exit 1
  end
end
