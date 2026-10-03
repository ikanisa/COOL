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

  def test_current_sources_all_twelve_and_seven_custom_auth_settings_agree
    assert CollectEdgeInventory.validate(@root, @manifest, auth: true)
    assert_equal 12, @manifest.fetch('functions').length
    custom = @manifest.fetch('functions').reject { |entry| entry.fetch('verify_jwt') }
    assert_equal 7, custom.length
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
end
