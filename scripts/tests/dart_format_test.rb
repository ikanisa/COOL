# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'json'
require 'digest'

class DartFormatTest < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)

  def setup
    @root = Dir.mktmpdir('collect-format-fixture-')
    FileUtils.mkdir_p(File.join(@root, 'scripts/qa'))
    FileUtils.cp(File.join(ROOT, 'scripts/qa/dart_format.rb'), File.join(@root, 'scripts/qa/dart_format.rb'))
    FileUtils.mkdir_p(File.join(@root, 'lib'))
    FileUtils.mkdir_p(File.join(@root, 'build/vendor'))
    File.write(File.join(@root, '.gitignore'), "/build/\n")
    @source = File.join(@root, 'lib/space name.dart')
    @generated = File.join(@root, 'build/vendor/dependency.dart')
    File.write(@source, 'unformatted owned source')
    File.write(@generated, 'unformatted generated dependency')
    assert system('git', 'init', '-q', @root)
    @dart = File.join(@root, 'fixture-dart')
    File.write(@dart, <<~'RUBY')
      #!/usr/bin/ruby
      require 'json'
      File.write('formatter-arguments.json', JSON.generate(ARGV))
      unless ARGV.include?('--output=none')
        ARGV.grep(/\.dart\z/).each { |file| File.write(file, 'formatted by fixture') }
      end
      exit(ARGV.include?('--set-exit-if-changed') ? 1 : 0)
    RUBY
    File.chmod(0o755, @dart)
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def run_format(mode)
    Open3.capture3({ 'DART' => @dart }, 'ruby', File.join(@root, 'scripts/qa/dart_format.rb'), mode)
  end

  def test_check_rejects_unformatted_source_without_writing_or_scanning_generated_dependencies
    _stdout, stderr, status = run_format('--check')
    assert_equal 1, status.exitstatus, stderr
    assert_equal 'unformatted owned source', File.read(@source)
    assert_equal 'unformatted generated dependency', File.read(@generated)
    arguments = JSON.parse(File.read(File.join(@root, 'formatter-arguments.json')))
    assert_includes arguments, 'lib/space name.dart'
    refute_includes arguments, 'build/vendor/dependency.dart'
  end

  def test_invalid_mode_does_not_invoke_formatter
    _stdout, _stderr, status = run_format('--unknown')
    refute status.success?
    refute File.exist?(File.join(@root, 'formatter-arguments.json'))
  end

  def test_upstream_bytes_are_preserved_and_modified_fork_files_are_checked
    original = 'third_party/synthetic_fork/lib/upstream.dart'
    modified = 'third_party/synthetic_fork/lib/modified.dart'
    [original, modified].each do |path|
      FileUtils.mkdir_p(File.dirname(File.join(@root, path)))
      File.write(File.join(@root, path), 'original upstream source')
    end
    upstream = [original, modified].to_h do |path|
      [path.delete_prefix('third_party/synthetic_fork/'), Digest::SHA256.file(File.join(@root, path)).hexdigest]
    end
    File.write(File.join(@root, 'third_party/synthetic_fork/UPSTREAM-SHA256.json'), JSON.generate(upstream))
    File.write(File.join(@root, modified), 'Collect fork change')
    _stdout, _stderr, status = run_format('--write')
    assert status.success?
    arguments = JSON.parse(File.read(File.join(@root, 'formatter-arguments.json')))
    refute_includes arguments, original
    assert_includes arguments, modified
    assert_equal 'original upstream source', File.read(File.join(@root, original))
    assert_equal 'formatted by fixture', File.read(File.join(@root, modified))
  end

  def test_hash_preserved_snapshots_are_not_reformatted_but_tests_and_tools_remain
    archive = 'docs/release/prior/attempt1/source-snapshot/lib/source.dart'
    removed = 'docs/release/asset-build-hygiene-2026-09-30/removed-source/lib/unused.dart'
    evidence = ['test/regression.dart', 'tool/capture.dart', 'third_party/fork/lib/source.dart']
    partial = ['docs/release/admin-roster-reload-2026-09-30/sources-attempt1/lib/a.dart',
               'docs/release/admin-roster-reload-2026-09-30/sources-attempt2-actual144/test/b.dart',
               'docs/release/admin-roster-reload-2026-09-30/sources-attempt3-current-logout/lib/c.dart',
               'docs/release/local-browser-lifecycle-2026-09-30/logout-regression/source/test/d.dart',
               'docs/release/local-browser-lifecycle-2026-09-30/attempt4-uncaught-logout/source/lib/e.dart',
               'docs/release/local-browser-lifecycle-2026-09-30/attempt5-current-logout/source/tool/f.dart',
               'docs/release/shared-ui-accessibility-2026-09-30/attempt2/source/third_party/fork/lib/g.dart']
    ([archive, removed] + partial + evidence).each do |relative|
      FileUtils.mkdir_p(File.dirname(File.join(@root, relative)))
      File.write(File.join(@root, relative), 'unformatted evidence')
    end
    _stdout, _stderr, _status = run_format('--write')
    arguments = JSON.parse(File.read(File.join(@root, 'formatter-arguments.json')))
    ([archive, removed] + partial).each do |relative|
      refute_includes arguments, relative
      assert_equal 'unformatted evidence', File.read(File.join(@root, relative))
    end
    evidence.each { |relative| assert_includes arguments, relative }
  end
end
