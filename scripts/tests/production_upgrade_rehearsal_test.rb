require 'minitest/autorun'
require_relative 'production_archive_restore'
require_relative 'production_upgrade_rehearsal'

class ProductionUpgradeRehearsalTest < Minitest::Test
  def test_exact_reviewed_manifest
    manifest=ProductionUpgradeRehearsal.manifest(ROOT)
    assert_equal 23, manifest.length
    assert_equal '20260902073741',manifest.first.fetch('version')
    assert_equal '20260903092500',manifest.last.fetch('version')
    assert manifest.all? { |entry| Digest::SHA256.hexdigest(entry.fetch('content'))==entry.fetch('sha256') }
  end

  def test_original_columns_are_projected_with_only_explicit_exceptions
    headers=['COPY public.profiles (id, display_name, updated_at) FROM stdin;',
      'COPY public.collections (id, title, updated_at) FROM stdin;',
      'COPY public.feature_flags (key, enabled) FROM stdin;',
      'COPY public.admin_navigation_items (key, label) FROM stdin;',
      'COPY public.admin_queue_specs (rpc_name, title) FROM stdin;',
      'COPY public.admin_queue_filter_options (rpc_name, value) FROM stdin;',
      'COPY public.app_realtime_events (id, area, created_at) FROM stdin;']
    assert_equal [
      ['public.profiles','id, display_name, updated_at'],
      ['public.collections','id, title'],
      ['public.admin_navigation_items','key, label'],
      ['public.admin_queue_specs','rpc_name, title']
    ],
      ProductionUpgradeRehearsal.projection(headers)
    assert_equal " WHERE key <> 'hybrid_sms_receipts'",
      ProductionUpgradeRehearsal.projection_predicate('public.admin_navigation_items')
    assert_equal " WHERE rpc_name <> 'admin_list_hybrid_sms_receipts'",
      ProductionUpgradeRehearsal.projection_predicate('public.admin_queue_specs')
    assert_equal '', ProductionUpgradeRehearsal.projection_predicate('public.profiles')
    assert_raises(RuntimeError) { ProductionUpgradeRehearsal.projection(['COPY other; DROP SCHEMA public; (id) FROM stdin;']) }
    assert_raises(RuntimeError) { ProductionUpgradeRehearsal.projection(['COPY public.profiles (id FROM auth.users) FROM stdin;']) }
  end

  def test_realtime_events_must_preserve_original_content
    old="original\tpayments\t2026-09-01"
    added="added\tmembers\t2026-09-03"
    result=ProductionUpgradeRehearsal.appended_events([old],[old,added])
    assert_equal 1,result[:existing_rows_preserved]
    assert_equal 1,result[:new_invalidation_events]
    assert_equal({'members'=>1},result[:areas])
    assert_raises(RuntimeError) { ProductionUpgradeRehearsal.appended_events([old],[added]) }
    assert_raises(RuntimeError) { ProductionUpgradeRehearsal.appended_events([old],[old.sub('payments','collections')]) }
    assert_raises(RuntimeError) { ProductionUpgradeRehearsal.appended_events([old],[old,added.sub('members','payments')]) }
  end
end
