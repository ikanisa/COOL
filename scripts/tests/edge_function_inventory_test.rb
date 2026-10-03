# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'open3'
require_relative '../edge_function_inventory'

class EdgeFunctionInventoryTest < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)

  def setup
    @root = Dir.mktmpdir('collect-edge-inventory-')
    FileUtils.mkdir_p(File.join(@root, 'contracts'))
    FileUtils.cp(File.join(ROOT, 'contracts/edge-functions.json'), File.join(@root, 'contracts'))
    FileUtils.mkdir_p(File.join(@root, 'supabase'))
    FileUtils.cp(File.join(ROOT, 'supabase/config.toml'), File.join(@root, 'supabase'))
    FileUtils.cp_r(File.join(ROOT, 'supabase/functions'), File.join(@root, 'supabase'))
    @manifest = CollectEdgeInventory.read(@root)
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def write_manifest
    File.write(File.join(@root, 'contracts/edge-functions.json'), JSON.pretty_generate(@manifest))
  end

  def test_current_sources_all_thirteen_and_eight_custom_auth_settings_agree
    assert CollectEdgeInventory.validate(@root, @manifest, auth: true)
    assert_equal 13, @manifest.fetch('functions').length
    actual = Dir[File.join(@root, 'supabase/functions/*/index.ts')].map { |path| File.basename(File.dirname(path)) }.sort
    assert_equal actual, @manifest.fetch('functions').map { |entry| entry.fetch('name') }.sort
    custom = @manifest.fetch('functions').reject { |entry| entry.fetch('verify_jwt') }
    assert_equal 8, custom.length
    assert_includes custom.map { |entry| entry.fetch('auth') }, 'device_signature'
    assert_includes custom.map { |entry| entry.fetch('auth') }, 'supervisor_signature'
    assert_includes custom.map { |entry| entry.fetch('auth') }, 'scheduler_secret'
  end

  def test_missing_and_unreviewed_entrypoints_fail
    path = File.join(@root, 'supabase/functions/reconciliation-finalize/index.ts')
    File.delete(path)
    assert_raises(RuntimeError) { CollectEdgeInventory.validate(@root, @manifest) }
    File.write(path, 'export {};')
    extra = File.join(@root, 'supabase/functions/unreviewed/index.ts')
    FileUtils.mkdir_p(File.dirname(extra))
    File.write(extra, 'export {};')
    assert_raises(RuntimeError) { CollectEdgeInventory.validate(@root, @manifest) }
  end

  def test_wrong_jwt_and_duplicate_config_sections_fail
    config = File.join(@root, 'supabase/config.toml')
    original = File.read(config)
    File.write(config, original.sub("[functions.collect-android-gateway]\nverify_jwt = false", "[functions.collect-android-gateway]\nverify_jwt = true"))
    assert_raises(RuntimeError) { CollectEdgeInventory.validate(@root, @manifest) }
    File.write(config, original + "\n[functions.collect-android-gateway]\nverify_jwt = false\n")
    assert_raises(RuntimeError) { CollectEdgeInventory.validate(@root, @manifest) }
  end

  def test_duplicate_retired_overlap_or_contradictory_auth_is_rejected
    @manifest['functions'] << @manifest['functions'].first.dup
    write_manifest
    assert_raises(RuntimeError) { CollectEdgeInventory.read(@root) }
    @manifest['functions'].pop
    @manifest['retired'] << @manifest['functions'].first.fetch('name')
    write_manifest
    assert_raises(RuntimeError) { CollectEdgeInventory.read(@root) }
    @manifest['retired'].pop
    @manifest['functions'].first['verify_jwt'] = true
    write_manifest
    assert_raises(RuntimeError) { CollectEdgeInventory.read(@root) }
  end

  def test_removed_signature_wiring_fails_auth_contract
    path = File.join(@root, 'supabase/functions/collect-android-gateway/handler.ts')
    File.write(path, File.read(path).gsub('crypto.subtle.verify', 'unverified'))
    assert_raises(RuntimeError) { CollectEdgeInventory.validate(@root, @manifest, auth: true) }
  end

  def test_factored_otp_handler_is_checked_and_static_hook_header_is_rejected
    path = File.join(@root, 'supabase/functions/_shared/signed_sms_hook.ts')
    File.write(path, File.read(path) + "\nconst forbidden = 'x-hook-secret';\n")
    assert_raises(RuntimeError) { CollectEdgeInventory.validate(@root, @manifest, auth: true) }
  end

  def successor_source(name)
    File.join(@root, 'supabase/functions/collect-receipt-successor-gateway', name)
  end

  def refuse_successor_mutation(file, before, after, error_text)
    path = successor_source(file)
    original = File.read(path)
    assert_includes original, before
    File.write(path, original.sub(before, after))
    error = assert_raises(RuntimeError) { CollectEdgeInventory.validate(@root, @manifest, auth: true) }
    assert_includes error.message, error_text
  ensure
    File.write(path, original) if path && original
  end

  def test_successor_registered_device_signature_entry_and_builtin_only_secrets
    entry = @manifest.fetch('functions').find { |row| row.fetch('name') == CollectEdgeInventory::SUCCESSOR }
    assert_equal 'active', entry.fetch('status')
    assert_equal 'device_signature', entry.fetch('auth')
    assert_equal false, entry.fetch('verify_jwt')
    assert_empty entry.fetch('required_secrets')
    assert_equal 6, CollectEdgeInventory::SUCCESSOR_RPC.length
    assert CollectEdgeInventory.validate_successor_wiring(@root)
  end

  def test_successor_wrong_supported_auth_or_jwt_is_refused
    entry = @manifest.fetch('functions').find { |row| row.fetch('name') == CollectEdgeInventory::SUCCESSOR }
    entry['auth'] = 'user_jwt'
    entry['verify_jwt'] = true
    write_manifest
    assert_includes assert_raises(RuntimeError) { CollectEdgeInventory.read(@root) }.message, 'must retain device signature'
    entry['auth'] = 'device_signature'
    write_manifest
    assert_raises(RuntimeError) { CollectEdgeInventory.read(@root) }
  end

  def test_successor_wrong_family_or_audience_is_refused
    refuse_successor_mutation('wire.ts', 'FAMILY = "receipt_successor"', 'FAMILY = "receipt"', 'FAMILY namespace')
    refuse_successor_mutation('wire.ts', 'AUDIENCE = "collect-receipt-successor-gateway"', 'AUDIENCE = "collect-android-gateway"', 'AUDIENCE namespace')
  end

  def test_each_of_six_successor_action_rpc_swaps_is_refused
    CollectEdgeInventory::SUCCESSOR_RPC.each do |action, rpc|
      refuse_successor_mutation('wire.ts', "#{action}: \"#{rpc}\"", "#{action}: \"unreviewed_rpc_v1\"", 'action/RPC mapping')
    end
  end

  def test_extra_duplicate_and_cross_family_successor_actions_are_refused
    first = 'dispatch_grant: "gateway_receipt_successor_grant_v1",'
    refuse_successor_mutation('wire.ts', first, first + "\n  extra_action: \"unreviewed_rpc_v1\",", 'action/RPC mapping')
    refuse_successor_mutation('wire.ts', first, first + "\n  " + first, 'action/RPC mapping')
    refuse_successor_mutation('wire.ts', 'archive_attempt:', 'dispatch_grant:', 'action/RPC mapping')
  end

  def test_successor_namespace_comparisons_and_allowlisted_action_call_are_required
    refuse_successor_mutation('handler.ts', 'envelope.protocol_family === FAMILY', 'envelope.protocol_family !== FAMILY', 'family comparison')
    refuse_successor_mutation('handler.ts', 'envelope.audience === AUDIENCE', 'envelope.audience !== AUDIENCE', 'audience comparison')
    refuse_successor_mutation('handler.ts', 'Object.hasOwn(RPC, envelope.action)', 'Boolean(envelope.action)', 'action allowlist')
    refuse_successor_mutation('handler.ts', 'rpc(RPC[action],', 'rpc("unreviewed_rpc_v1",', 'allowlisted action RPC')
    refuse_successor_mutation('handler.ts', 'p_request_sha256: await digest(raw)', 'p_request_sha256: "unbound"', 'raw request digest')
  end

  def test_successor_key_id_signature_and_registered_hash_wiring_are_required
    refuse_successor_mutation('handler.ts', 'X-Collect-Gateway-Key-Id', 'X-Unreviewed-Key-Id', 'key ID header')
    refuse_successor_mutation('handler.ts', 'X-Collect-Gateway-Signature', 'X-Unreviewed-Signature', 'device_signature source wiring')
    refuse_successor_mutation('handler.ts', 'key.key_sha256 !== keyId', 'key.key_sha256 !== "unbound"', 'registered key hash comparison')
    refuse_successor_mutation('handler.ts', 'rpc("gateway_device_key_v1",', 'rpc("unreviewed_key_v1",', 'device key lookup')
    refuse_successor_mutation('handler.ts', 'crypto.subtle.verify', 'unverified', 'device_signature source wiring')
  end

  def test_successor_index_requires_actual_handler_service_import_and_abort_signal
    refuse_successor_mutation('index.ts', '../_shared/supabase.ts', '../_shared/unreviewed.ts', 'service client import')
    refuse_successor_mutation('index.ts', './handler.ts', './unreviewed.ts', 'handler import')
    refuse_successor_mutation('index.ts', 'Deno.serve(createSuccessorGatewayHandler', 'Deno.serve(unreviewedHandler', 'served handler')
    refuse_successor_mutation('index.ts', 'serviceClient().rpc(name, args)', 'unreviewedClient().rpc(name, args)', 'served handler')
    refuse_successor_mutation('index.ts', '.abortSignal(signal)', '.abortSignal(new AbortController().signal)', 'served handler')
  end

  def test_successor_missing_and_duplicate_inventory_and_source_are_refused
    entry = @manifest.fetch('functions').find { |row| row.fetch('name') == CollectEdgeInventory::SUCCESSOR }
    @manifest['functions'].delete(entry)
    assert_raises(RuntimeError) { CollectEdgeInventory.validate(@root, @manifest, auth: true) }
    @manifest['functions'] << entry << entry.dup
    write_manifest
    assert_raises(RuntimeError) { CollectEdgeInventory.read(@root) }
    @manifest['functions'].pop
    path = successor_source('index.ts')
    File.delete(path)
    assert_raises(RuntimeError) { CollectEdgeInventory.validate(@root, @manifest, auth: true) }
  end

  def test_successor_wire_must_be_regular_and_present
    path = successor_source('wire.ts')
    original = File.read(path)
    File.delete(path)
    assert_includes assert_raises(RuntimeError) { CollectEdgeInventory.validate(@root, @manifest, auth: true) }.message, 'Missing regular successor source'
    target = File.join(@root, 'unreviewed-wire.ts')
    File.write(target, original)
    File.symlink(target, path)
    assert_includes assert_raises(RuntimeError) { CollectEdgeInventory.validate(@root, @manifest, auth: true) }.message, 'Missing regular successor source'
  end

  def test_successor_jwt_config_must_remain_false
    config = File.join(@root, 'supabase/config.toml')
    original = File.read(config)
    wrong = original.sub("[functions.collect-receipt-successor-gateway]\nverify_jwt = false", "[functions.collect-receipt-successor-gateway]\nverify_jwt = true")
    refute_equal original, wrong
    File.write(config, wrong)
    assert_includes assert_raises(RuntimeError) { CollectEdgeInventory.validate(@root, @manifest, auth: true) }.message, 'JWT config differs'
  end

  def test_denial_plan_preserves_all_current_auth_boundaries
    rows = CollectEdgeInventory.denial_probes(@manifest)
    assert_equal @manifest.fetch('functions').map { |entry| entry.fetch('name') }, rows.map(&:first)
    assert_equal rows.length, rows.map(&:first).uniq.length
    expected = {
      'auth-send-whatsapp-otp' => [401, 'invalid_hook_signature'],
      'collect-android-gateway' => [400, 'GATEWAY_REQUEST_INVALID'],
      'collect-receipt-successor-gateway' => [400, 'GATEWAY_REQUEST_INVALID'],
      'collect-receipt-supervisor' => [400, 'SUPERVISOR_REQUEST_INVALID'],
      'collect-receipt-exception-worker' => [401, 'WORKER_AUTH_REQUIRED']
    }
    rows.each do |name, status, error|
      assert_equal expected.fetch(name, [401, '']), [status, error], name
    end
  end

  def test_denial_plan_rejects_unsupported_auth_without_partial_output
    @manifest.fetch('functions').last['auth'] = 'unreviewed_auth'
    write_manifest
    output, = capture_io do
      assert_raises(RuntimeError) { CollectEdgeInventory.run(['denial-probes'], root: @root) }
    end
    assert_empty output
    assert_raises(RuntimeError) { CollectEdgeInventory.denial_probes(@manifest) }
  end

  def test_denial_cli_revalidates_source_auth_and_rejects_extra_arguments
    output, = capture_io { CollectEdgeInventory.run(['denial-probes'], root: @root) }
    assert_equal CollectEdgeInventory.denial_probes(@manifest).map { |row| row.join("\t") + "\n" }.join, output
    assert_raises(RuntimeError) { CollectEdgeInventory.run(['denial-probes', 'unreviewed'], root: @root) }
    File.delete(File.join(@root, 'supabase/functions/reconciliation-finalize/index.ts'))
    output, = capture_io do
      assert_raises(RuntimeError) { CollectEdgeInventory.run(['denial-probes'], root: @root) }
    end
    assert_empty output
  end

  # The shell functions replace every potential provider/management command.
  # Production readiness's main is never sourced or executed in this fixture.
  def run_unsigned_probe_fixture(extra_env = {})
    scripts = File.join(@root, 'scripts')
    FileUtils.mkdir_p(scripts)
    %w[edge_function_inventory.rb edge_function_inventory.sh supabase_cli_helpers.sh load_dotenv_strict.sh].each do |name|
      FileUtils.cp(File.join(ROOT, 'scripts', name), scripts)
    end
    source = File.read(File.join(ROOT, 'scripts/supabase_production_readiness.sh'))
    prefix, marker, suffix = source.rpartition('main "$@"')
    raise 'Missing readiness main boundary' if marker.empty? || !suffix.strip.empty?

    fixture = File.join(scripts, 'readiness-functions.sh')
    File.write(fixture, prefix)
    log = File.join(@root, 'probe-calls.jsonl')
    File.delete(log) if File.exist?(log)
    command = <<~'BASH'
      . "$1"
      supabase_cli() {
        ruby "$ROOT_DIR/scripts/edge_function_inventory.rb" expected |
          ruby -r json -e 'puts STDIN.readlines.map { |x| {name: x.strip} }.to_json'
      }
      curl() {
        ruby -r json -e 'File.open(ENV.fetch("PROBE_LOG"), "a") { |f| f.puts ARGV.to_json }' -- "$@"
        local url='' arg status=401 error='authentication_required' discard=false
        for arg in "$@"; do
          case "$arg" in
            */functions/v1/*) url="$arg" ;;
            /dev/null) discard=true ;;
          esac
        done
        case "$url" in
          */auth-send-whatsapp-otp) error=invalid_hook_signature ;;
          */collect-android-gateway|*/collect-receipt-successor-gateway) status=400; error=GATEWAY_REQUEST_INVALID ;;
          */collect-receipt-supervisor) status=400; error=SUPERVISOR_REQUEST_INVALID ;;
          */collect-receipt-exception-worker) error=WORKER_AUTH_REQUIRED ;;
        esac
        [[ "${url##*/}" != "${PROBE_WRONG_BODY:-}" ]] || error=UNEXPECTED_ERROR
        [[ "$discard" == true ]] || printf '{"error":"%s"}\n' "$error"
        printf '%s' "$status"
      }
      check_functions
    BASH
    env = {'PATH' => '/usr/bin:/bin', 'LANG' => 'en_US.UTF-8', 'LC_ALL' => 'en_US.UTF-8', 'SUPABASE_ACCESS_TOKEN' => 'unused-test-only-token',
           'SUPABASE_PROJECT_REF' => 'abcdefghijklmnopqrst', 'PROBE_LOG' => log,
           'PROBE_WRONG_BODY' => ''}.merge(extra_env)
    stdout, stderr, result = Open3.capture3(env, 'bash', '-c', command, 'bash', fixture, unsetenv_others: true)
    calls = File.exist?(log) ? File.readlines(log).map { |line| JSON.parse(line) } : []
    [stdout, stderr, result, calls]
  end

  def test_actual_readiness_probes_follow_a_reviewed_manifest_name_change
    entry = @manifest.fetch('functions').find { |row| row.fetch('name') == 'collect-notification-operator' }
    entry['name'] = 'reviewed-operator-fixture'
    write_manifest
    FileUtils.mv(File.join(@root, 'supabase/functions/collect-notification-operator'),
                 File.join(@root, 'supabase/functions/reviewed-operator-fixture'))
    config = File.join(@root, 'supabase/config.toml')
    File.write(config, File.read(config).sub('[functions.collect-notification-operator]', '[functions.reviewed-operator-fixture]'))
    _, stderr, result, calls = run_unsigned_probe_fixture
    assert result.success?, stderr
    observed = calls.map { |args| args.find { |arg| arg.include?('/functions/v1/') }.split('/').last }
    assert_equal @manifest.fetch('functions').map { |row| row.fetch('name') }, observed
    assert_includes observed, 'reviewed-operator-fixture'
    refute_includes observed, 'collect-notification-operator'
    calls.each do |args|
      assert_equal 'POST', args.fetch(args.index('-X') + 1)
      assert_equal '{}', args.fetch(args.index('--data') + 1)
      headers = args.each_index.select { |index| args[index] == '-H' }.map { |index| args[index + 1] }
      assert_equal ['content-type: application/json'], headers
      refute args.any? { |arg| arg.downcase.include?('authorization') || arg.include?('unused-test-only-token') }
    end
  end

  def test_actual_readiness_requires_custom_auth_error_even_when_status_matches
    _, stderr, result, = run_unsigned_probe_fixture('PROBE_WRONG_BODY' => 'collect-receipt-supervisor')
    refute result.success?
    assert_includes stderr, 'collect-receipt-supervisor unsigned negative probe did not reach its rejection boundary'
  end
end
