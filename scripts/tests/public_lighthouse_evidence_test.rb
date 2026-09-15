# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'json'
require 'time'
require 'open3'
require 'rbconfig'

helper = File.expand_path('../qa/public_lighthouse_evidence.rb', __dir__)
if File.file?(helper)
  require helper
else
  # Baseline reproduction calls the existing gate's actual validator.
  gate = File.read(File.expand_path('../public_website_completion_gate.sh', __dir__))
  eval(gate[gate.index('def binary_artifact_valid?')...gate.index('def png_dimensions')], TOPLEVEL_BINDING)
end

class PublicLighthouseEvidenceTest < Minitest::Test
  def setup
    @directory = Dir.mktmpdir('collect-lighthouse-evidence-')
    @now = Time.iso8601('2026-09-15T00:00:00Z')
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def report
    {
      'lighthouseVersion' => '13.4.0',
      'requestedUrl' => 'https://collect.ikanisa.com/',
      'finalDisplayedUrl' => 'https://collect.ikanisa.com/',
      'fetchTime' => '2026-09-14T23:00:00Z',
      'configSettings' => { 'formFactor' => 'mobile' },
      'environment' => { 'hostUserAgent' => 'Mozilla/5.0 Chrome/152.0.7977.84' },
      'categories' => %w[performance accessibility best-practices seo].to_h { |id| [id, { 'score' => 0.95 }] },
      'audits' => { 'http-status-code' => { 'score' => 1 } }
    }
  end

  def valid?(data, profile: 'mobile', name: 'mobile.json')
    path = File.join(@directory, name)
    File.write(path, data.is_a?(String) ? data : JSON.generate(data))
    if defined?(PublicLighthouseEvidence)
      PublicLighthouseEvidence.validate_file(path, expected_url: 'https://collect.ikanisa.com/', profile: profile, now: @now)['status'] == 'pass'
    else
      lighthouse_artifact_valid?(path)
    end
  end

  def test_complete_current_mobile_report
    assert valid?(report)
  end

  def test_matching_desktop_report
    data = report
    data['configSettings']['formFactor'] = 'desktop'
    assert valid?(data, profile: 'desktop')
  end

  def test_pagespeed_envelope
    assert valid?({ 'lighthouseResult' => report })
  end

  def test_arbitrary_pdf_cannot_replace_a_scored_report
    refute valid?('not a report ' * 20, name: 'mobile.pdf')
  end

  def test_html_is_supplementary_not_an_automatic_score_claim
    refute valid?('<html>unscored screenshot</html>' * 10, name: 'mobile.html')
  end

  def test_wrong_target_is_rejected
    data = report
    data['requestedUrl'] = data['finalDisplayedUrl'] = 'https://example.org/'
    refute valid?(data)
  end

  def test_redirect_to_a_different_page_is_rejected
    data = report
    data['finalDisplayedUrl'] = 'https://collect.ikanisa.com/login/'
    refute valid?(data)
  end

  def test_wrong_device_profile_is_rejected
    data = report
    data['configSettings']['formFactor'] = 'desktop'
    refute valid?(data)
  end

  def test_old_report_is_rejected
    data = report
    data['fetchTime'] = '2020-01-01T00:00:00Z'
    refute valid?(data)
  end

  def test_future_report_is_rejected
    data = report
    data['fetchTime'] = '2026-09-16T00:00:00Z'
    refute valid?(data)
  end

  def test_missing_timestamp_is_rejected
    data = report
    data.delete('fetchTime')
    refute valid?(data)
  end

  def test_runtime_error_is_not_a_successful_audit
    data = report
    data['runtimeError'] = { 'code' => 'NO_FCP', 'message' => 'No render observed' }
    refute valid?(data)
  end

  def test_http_error_is_not_a_successful_target
    data = report
    data['audits']['http-status-code']['score'] = 0
    refute valid?(data)
  end

  def test_unchanged_category_threshold
    data = report
    data['categories']['performance']['score'] = 0.89
    refute valid?(data)
  end

  def test_missing_performance_category_is_not_inferred_from_other_scores
    data = report
    data['categories'].delete('performance')
    refute valid?(data)
  end

  def test_invalid_score_range_is_rejected
    data = report
    data['categories']['performance']['score'] = 95
    refute valid?(data)
  end

  def test_scores_without_audited_document_evidence_are_rejected
    data = report
    data.delete('audits')
    refute valid?(data)
  end

  def test_malformed_json_is_rejected
    refute valid?('{not json')
  end

  def failed_completion
    {
      'status' => 'fail',
      'code_checks' => { 'static_quality_gate' => false, 'live_quality_gate' => false, 'live_audit_evidence' => false },
      'missing_external_count' => 0, 'missing_external' => {}, 'gate_summaries' => {}
    }
  end

  def render_failed_completion(completion = failed_completion)
    input = File.join(@directory, 'completion.json')
    output = File.join(@directory, 'completion.md')
    File.write(input, JSON.generate(completion))
    script = File.read(File.expand_path('../public_website_completion_report.sh', __dir__))
    ruby = script.split("<<'RUBY'\n", 2).last.split("\nRUBY", 2).first
    _stdout, stderr, status = Open3.capture3(RbConfig.ruby, '-r', 'json', '-r', 'time', '-', input, output, '1', stdin_data: ruby)
    assert_equal 1, status.exitstatus, stderr
    File.read(output)
  end

  def test_failed_code_checks_cannot_be_reported_as_green
    output = render_failed_completion
    refute_includes output, 'code-owned remediation is green'
    refute_match(/T-3[^\n]*\| PASS \|/, output)
  end

  def test_lighthouse_lab_score_cannot_claim_field_core_web_vitals
    output = render_failed_completion
    refute_includes output, '| Lighthouse/Core Web Vitals | PASS |'
    assert_includes output, 'Field Core Web Vitals remain unverified'
  end

  def test_failed_checks_do_not_invent_static_success_or_publication_state
    output = render_failed_completion
    refute_match(/Static gates? verif(?:y|ies)|Static gates encode|Live robots\/sitemap crawl readiness is proven/, output)
    refute_match(/production deployment is pending|production still has the previous copy|production deployment is still required/, output)
  end

  def test_absent_external_results_cannot_establish_approval
    output = render_failed_completion
    refute_match(/T-1[^\n]*\| PASS \||U-5[^\n]*\| PASS \||Play Console action boundary[^\n]*\| PASS \|/, output)
    refute_includes output, 'Google Search Console accepted the production sitemap'
  end

  def test_missing_code_results_are_not_an_all_green_run
    completion = failed_completion
    completion['code_checks'] = {}
    output = render_failed_completion(completion)
    refute_includes output, 'The recorded code checks pass'
  end

  def test_valid_lab_results_remain_separate_from_failed_code_and_field_data
    completion = failed_completion
    completion['external_checks'] = %w[lighthouse_mobile lighthouse_desktop].to_h { |id| [id, { 'status' => 'pass' }] }
    output = render_failed_completion(completion)
    assert_includes output, '| Lighthouse lab reports | PASS |'
    assert_includes output, '| Field Core Web Vitals | UNVERIFIED |'
    refute_includes output, 'The recorded code checks pass'
  end
end
