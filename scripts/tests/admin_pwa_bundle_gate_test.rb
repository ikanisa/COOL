#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'minitest/autorun'
require 'open3'
require 'tmpdir'

class AdminPwaBundleGateTest < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)

  def test_manifest_gate_rejects_an_empty_compiled_bundle
    Dir.mktmpdir('collect-admin-bundle-gate-') do |build_dir|
      File.write(File.join(build_dir, 'main.dart.js'), '')
      _out, err, status = Open3.capture3(
        { 'ADMIN_PWA_BUILD_DIR' => build_dir },
        'bash', File.join(ROOT, 'scripts/admin_pwa_manifest_gate.sh')
      )
      refute status.success?
      assert_includes err, 'missing or empty build/web/main.dart.js'

      File.write(File.join(build_dir, 'main.dart.js'), 'synthetic compiled bytes')
      _out, err, status = Open3.capture3(
        { 'ADMIN_PWA_BUILD_DIR' => build_dir },
        'bash', File.join(ROOT, 'scripts/admin_pwa_manifest_gate.sh')
      )
      refute status.success? # Other PWA files were deliberately not built.
      refute_includes err, 'missing or empty build/web/main.dart.js'
    end
  end

  def test_release_builder_rejects_successful_compile_without_bundle
    Dir.mktmpdir('collect-admin-builder-gate-') do |root|
      scripts = File.join(root, 'scripts')
      FileUtils.mkdir_p(scripts)
      %w[admin_pwa_release_build.sh load_dotenv_strict.sh].each do |name|
        FileUtils.cp(File.join(ROOT, 'scripts', name), File.join(scripts, name))
      end
      fake_flutter = File.join(root, 'fake-flutter')
      File.write(fake_flutter, <<~SH)
        #!/usr/bin/env bash
        mkdir -p build/web
        : > build/web/main.dart.js
      SH
      FileUtils.chmod(0o755, fake_flutter)
      env = {
        'FLUTTER' => fake_flutter,
        'COLLECT_SKIP_DOTENV' => '1',
        'SUPABASE_PRODUCTION_URL' => 'https://synthetic.invalid',
        'SUPABASE_PRODUCTION_ANON_KEY' => 'synthetic-public-key'
      }
      _out, err, status = Open3.capture3(
        env, 'bash', File.join(scripts, 'admin_pwa_release_build.sh'),
        chdir: root
      )
      refute status.success?
      assert_includes err, 'did not produce a nonempty main.dart.js bundle'
    end
  end
end
