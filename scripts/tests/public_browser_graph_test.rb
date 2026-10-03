# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative '../public_app_media'

class PublicBrowserGraphTest < Minitest::Test
  def fixture
    Dir.mktmpdir('collect-browser-graph-') do |root|
      rows = {
        'pubspec.yaml' => YAML.dump({'name' => 'collect_app', 'dependencies' => {'flutter' => {'sdk' => 'flutter'}},
          'dependency_overrides' => {'gotrue' => {'path' => 'third_party/gotrue'}},
          'flutter' => {'assets' => ['assets/icon.png']}}),
        'pubspec.lock' => 'pinned package fixture', '.fvmrc' => '{"flutter":"3.44.4"}', '.metadata' => 'project metadata',
        'analysis_options.yaml' => 'fixture options',
        'tool/public_app_media_capture.dart' => "import 'package:collect_app/main.dart';\n",
        'lib/main.dart' => "import 'package:flutter/material.dart';\nimport 'src/a.dart';\nimport 'src/stub.dart' if (dart.library.io) 'src/native.dart';\nexport 'src/b.dart';\npart 'src/p.dart';\n",
        'lib/src/a.dart' => "import 'b.dart';\n", 'lib/src/b.dart' => "import 'a.dart';\n",
        'lib/src/stub.dart' => 'stub source', 'lib/src/native.dart' => 'conditional source',
        'lib/src/p.dart' => "part of '../main.dart';\n",
        'assets/icon.png' => 'actual bundled fixture bytes',
        'web/index.html' => 'web scaffold', 'web/manifest.json' => '{}',
        'scripts/public_app_media.rb' => 'bound implementation source',
        'scripts/qa/asset_manifest_integrity.rb' => 'bound helper source',
        'third_party/gotrue/lib/gotrue.dart' => 'local fork runtime',
        'third_party/gotrue/pubspec.yaml' => 'local fork metadata',
        'third_party/gotrue/LICENSE' => 'retained license',
        'third_party/gotrue/COLLECT_FORK.md' => 'retained provenance'
      }
      rows.each do |name, bytes|
        path = File.join(root, name)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, bytes)
      end
      yield root, PublicAppMedia.new(root)
    end
  end

  def fingerprint(media)
    ENV['COLLECT_GRAPH_PRIOR'] == 'true' ? media.runtime_fingerprint : media.browser_runtime_fingerprint
  end

  def test_actual_unrelated_admin_and_gateway_additions_preserve_browser_fingerprint
    fixture do |root, media|
      before = fingerprint(media)
      %w[lib/admin/new_control.dart lib/gateway/gateway_app.dart].each do |name|
        path = File.join(root, name)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, 'new unrelated runtime')
      end
      assert_equal before, fingerprint(media)
    end
  end

  def test_actual_unrelated_native_callback_change_preserves_browser_fingerprint
    fixture do |root, media|
      before = fingerprint(media)
      directory = File.join(root, 'third_party/gotrue/ios')
      FileUtils.mkdir_p(directory)
      File.write(File.join(directory, 'callback.m'), 'new native callback')
      assert_equal before, fingerprint(media)
    end
  end

  def test_multiline_conditional_part_export_and_cycles_have_complete_closure
    fixture do |_root, media|
      expected = %w[tool/public_app_media_capture.dart lib/main.dart lib/src/a.dart lib/src/b.dart lib/src/stub.dart lib/src/native.dart lib/src/p.dart]
      assert_equal expected.sort, media.browser_source_snapshot.keys.grep(/\A(?:lib|tool)\//).sort
    end
  end

  def test_actual_reachable_source_asset_fork_and_web_mutations_change_fingerprint
    %w[lib/src/native.dart assets/icon.png third_party/gotrue/lib/gotrue.dart third_party/gotrue/LICENSE web/index.html pubspec.lock].each do |name|
      fixture do |root, media|
        before = media.browser_runtime_fingerprint
        File.write(File.join(root, name), 'changed actual input')
        refute_equal before, media.browser_runtime_fingerprint, name
      end
    end
  end

  def test_new_reachable_import_expands_and_changes_observed_closure
    fixture do |root, media|
      before = media.browser_runtime_fingerprint
      File.write(File.join(root, 'lib/src/new.dart'), 'new reachable source')
      File.open(File.join(root, 'lib/main.dart'), 'a') { |file| file.puts "import 'src/new.dart';" }
      refute_equal before, media.browser_runtime_fingerprint
      assert media.browser_source_snapshot.key?('lib/src/new.dart')
    end
  end

  def test_missing_entrypoint_and_missing_directive_target_are_refused
    fixture do |root, media|
      File.unlink(File.join(root, 'tool/public_app_media_capture.dart'))
      assert_raises(AssetManifestIntegrity::InvalidPath) { media.browser_runtime_fingerprint }
    end
    fixture do |root, media|
      File.unlink(File.join(root, 'lib/src/native.dart'))
      assert_raises(AssetManifestIntegrity::InvalidPath) { media.browser_runtime_fingerprint }
    end
  end

  def test_unknown_directives_undeclared_packages_and_escaping_paths_are_refused
    ["import unknown;", "import 'package:undeclared/private.dart';", "import '../../outside.dart';"].each do |directive|
      fixture do |root, media|
        File.open(File.join(root, 'lib/main.dart'), 'a') { |file| file.puts directive }
        assert_raises(RuntimeError) { media.browser_runtime_fingerprint }
      end
    end
  end

  def test_reachable_symlink_is_refused_even_if_target_is_local
    fixture do |root, media|
      path = File.join(root, 'lib/src/a.dart')
      File.unlink(path)
      File.symlink(File.join(root, 'lib/src/b.dart'), path)
      assert_raises(AssetManifestIntegrity::InvalidPath) { media.browser_runtime_fingerprint }
    end
  end

  def test_derived_published_media_is_not_its_own_capture_input
    fixture do |root, media|
      before = media.browser_runtime_fingerprint
      directory = File.join(root, 'web/public/app-screens')
      FileUtils.mkdir_p(directory)
      File.write(File.join(directory, 'home.png'), 'new derived route image')
      assert_equal before, media.browser_runtime_fingerprint
    end
  end

  def test_actual_local_fork_directives_bind_sources_outside_its_lib_directory
    fixture do |root, media|
      before = media.browser_runtime_fingerprint
      path = File.join(root, 'third_party/gotrue/shared.dart')
      File.write(path, 'additional fork source')
      File.write(File.join(root, 'third_party/gotrue/lib/gotrue.dart'), "import '../shared.dart';\n")
      refute_equal before, media.browser_runtime_fingerprint
      assert media.browser_source_snapshot.key?('third_party/gotrue/shared.dart')
      bound = media.browser_runtime_fingerprint
      File.write(path, 'changed additional fork source')
      refute_equal bound, media.browser_runtime_fingerprint
    end
  end

  def test_missing_local_fork_directive_is_refused
    fixture do |root, media|
      File.write(File.join(root, 'third_party/gotrue/lib/gotrue.dart'), "import 'missing.dart';\n")
      assert_raises(AssetManifestIntegrity::InvalidPath) { media.browser_runtime_fingerprint }
    end
  end
end
