# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'json'

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
end
