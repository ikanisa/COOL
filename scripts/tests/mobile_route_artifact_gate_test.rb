# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'json'
require 'open3'

class MobileRouteArtifactGateTest < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)

  def setup
    @bundle = Dir.mktmpdir('mobile-route-artifact-test-')
    @dir = File.join(@bundle, 'mobile_route_render_smoke')
    FileUtils.mkdir_p(@dir)
    @captures = 10.times.map do |index|
      path = "route-#{index}.png"
      image = File.join(@dir, path)
      File.binwrite(image, "\x89PNG\r\n\x1a\n".b + 'a' * 9_000)
      record = { 'path' => path, 'status' => 'pass', 'bytes' => File.size(image),
        'width' => 390, 'height' => 844, 'distinct_rgb' => 48, 'non_background_pixels' => 9000 }
      File.write("#{image}.json", JSON.generate(record))
      record
    end
    write_summary
  end

  def teardown
    FileUtils.remove_entry(@bundle)
  end

  def write_summary
    File.write(File.join(@dir, 'summary.json'), JSON.generate(
      'status' => 'pass', 'route_count' => @captures.length, 'captures' => @captures
    ))
  end

  def run_gate(bundle: @bundle)
    stdout, stderr, status = Open3.capture3(
      { 'MOBILE_ROUTE_RENDER_EVIDENCE_DIR' => @dir, 'QA_UAT_BUNDLE_DIR' => bundle.to_s },
      File.join(ROOT, 'scripts/mobile_route_artifact_gate.sh'), '--json'
    )
    [JSON.parse(stdout), stderr, status.exitstatus]
  end

  def test_complete_route_capture_passes_without_granting_release_approval
    result, _stderr, code = run_gate
    assert_equal 0, code
    assert_equal 'pass', result['status']
    assert_equal false, result['release_approval']
  end

  def test_external_capture_requires_selected_qa_bundle
    result, _stderr, code = run_gate(bundle: '')
    assert_equal 1, code
    assert_equal 'fail', result['status']
  end

  def test_missing_screenshot_fails
    File.delete(File.join(@dir, @captures.first.fetch('path')))
    result, _stderr, code = run_gate
    assert_equal 1, code
    assert_equal 'fail', result['status']
  end

  def test_path_traversal_fails
    @captures.first['path'] = '../outside.png'
    write_summary
    result, _stderr, code = run_gate
    assert_equal 1, code
    assert_equal 'fail', result['status']
  end

  def test_mismatched_image_size_fails
    @captures.first['bytes'] = 1
    write_summary
    result, _stderr, code = run_gate
    assert_equal 1, code
    assert_equal 'fail', result['status']
  end
end
