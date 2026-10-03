# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
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
end
