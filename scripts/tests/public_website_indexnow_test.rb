# frozen_string_literal: true

require 'json'
require 'minitest/autorun'
require 'open3'
require 'tmpdir'
require_relative '../qa/public_website/indexnow'

class PublicWebsiteIndexNowTest < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)
  ORIGIN = 'https://collect.example.test'
  FIXTURE_KEY = 'IndexNow-Test-Key'
  LOCATIONS = ["#{ORIGIN}/", "#{ORIGIN}/privacy/"].freeze

  def setup
    @directory = Dir.mktmpdir('collect-public-indexnow-')
    File.write(File.join(@directory, "#{FIXTURE_KEY}.txt"), "#{FIXTURE_KEY}\n")
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def test_shared_site_input_validates_the_published_urls
    sitemap(*LOCATIONS)
    site = PublicWebsiteIndexNow.new(build_dir: @directory, public_url: "#{ORIGIN}/", key: FIXTURE_KEY)
    report = site.readiness
    assert_equal 'ready', report.fetch('status')
    assert_equal LOCATIONS, report.fetch('sample_urls')
    assert_equal LOCATIONS, site.submission_payload.fetch('urlList')
    assert_equal "#{ORIGIN}/#{FIXTURE_KEY}.txt", site.submission_payload.fetch('keyLocation')
  end

  def test_empty_or_malformed_sitemap_cannot_be_ready
    sitemap
    assert_readiness_status('fail', expected_exit: 1)
    File.write(File.join(@directory, 'sitemap.xml'), '<urlset>BROKEN')
    assert_readiness_status('fail', expected_exit: 1)
  end

  def test_different_origin_cannot_be_ready
    sitemap(*LOCATIONS, 'https://collect.example.test:8443/privacy/')
    assert_readiness_status('fail', expected_exit: 1)
  end

  def test_keyless_readiness_is_read_only
    sitemap(*LOCATIONS)
    report = assert_readiness_status('owner_key_not_provided', expected_exit: 0, key: '')
    assert_equal true, report.fetch('same_host_urls')
    assert_equal true, report.fetch('not_submitted_by_codex')
  end

  private

  def sitemap(*locations)
    rows = locations.map { |location| "<url><loc>#{location}</loc></url>" }.join
    File.write(File.join(@directory, 'sitemap.xml'), "<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">#{rows}</urlset>")
  end

  def assert_readiness_status(expected, expected_exit:, key: FIXTURE_KEY)
    environment = {
      'PUBLIC_BUILD_DIR' => @directory,
      'PUBLIC_WEBSITE_URL' => ORIGIN,
      'PUBLIC_INDEXNOW_KEY' => key,
      'PUBLIC_INDEXNOW_KEY_SOURCE' => File.join(@directory, 'absent-owner-key'),
    }
    output, _, result = Open3.capture3(environment, 'bash', 'scripts/public_website_indexnow_readiness.sh', '--json', chdir: ROOT)
    assert_equal expected_exit, result.exitstatus
    report = JSON.parse(output)
    assert_equal expected, report.fetch('status')
    report
  end
end
