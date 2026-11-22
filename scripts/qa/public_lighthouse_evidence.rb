# frozen_string_literal: true

require 'json'
require 'time'
require 'uri'
require 'digest'

module PublicLighthouseEvidence
  THRESHOLDS = {
    'performance' => 0.9,
    'accessibility' => 0.9,
    'best-practices' => 0.9,
    'seo' => 0.9
  }.freeze
  # QA evidence freshness policy, not a Core Web Vitals or Lighthouse standard.
  MAX_AGE_SECONDS = 7 * 24 * 60 * 60
  FUTURE_TOLERANCE_SECONDS = 5 * 60

  def self.url_identity(value)
    return nil unless value.is_a?(String)

    uri = URI.parse(value)
    return nil unless %w[http https].include?(uri.scheme) && uri.host && !uri.userinfo

    [uri.scheme, uri.host.downcase, uri.port, uri.path.empty? ? '/' : uri.path, uri.query]
  rescue URI::InvalidURIError
    nil
  end

  def self.validate_file(path, expected_url:, profile:, now: Time.now.utc)
    result = {
      'status' => 'fail', 'path' => path, 'expected_url' => expected_url,
      'profile' => profile, 'thresholds' => THRESHOLDS, 'scores' => {},
      'max_age_seconds' => MAX_AGE_SECONDS, 'issues' => []
    }
    issues = result['issues']
    unless File.file?(path) && File.extname(path).downcase == '.json'
      issues << 'Structured Lighthouse/PageSpeed JSON required; HTML/PDF are supplementary.'
      return result
    end

    raw = File.binread(path)
    result['sha256'] = Digest::SHA256.hexdigest(raw)
    parsed = JSON.parse(raw)
    parsed = parsed['lighthouseResult'] if parsed.is_a?(Hash) && parsed.key?('lighthouseResult')
    unless parsed.is_a?(Hash)
      issues << 'Lighthouse result must be an object.'
      return result
    end
    expected = url_identity(expected_url)
    issues << 'Expected target URL is invalid.' unless expected
    issues << 'Requested URL does not match the target.' unless expected && url_identity(parsed['requestedUrl']) == expected
    final_urls = %w[finalDisplayedUrl finalUrl].map { |key| parsed[key] }.compact
    issues << 'Final URL does not match the target.' unless !final_urls.empty? && final_urls.all? { |url| url_identity(url) == expected }
    result['requested_url'] = parsed['requestedUrl']
    result['final_url'] = final_urls.first
    result['lighthouse_version'] = parsed['lighthouseVersion']
    issues << 'Lighthouse version is missing or invalid.' unless parsed['lighthouseVersion'].is_a?(String) && parsed['lighthouseVersion'].match?(/\A\d+\.\d+\.\d+(?:[-+].+)?\z/)
    settings = parsed['configSettings']
    issues << 'Device profile does not match.' unless %w[mobile desktop].include?(profile) && settings.is_a?(Hash) && settings['formFactor'] == profile
    environment = parsed['environment']
    issues << 'Browser environment is missing.' unless environment.is_a?(Hash) && environment['hostUserAgent'].is_a?(String) && !environment['hostUserAgent'].strip.empty?
    issues << 'Lighthouse reported a runtime error.' unless parsed['runtimeError'].nil?

    result['fetch_time'] = parsed['fetchTime']
    begin
      timestamp = Time.iso8601(parsed.fetch('fetchTime'))
      age = now - timestamp
      issues << 'Report is older than the seven-day QA evidence window.' if age > MAX_AGE_SECONDS
      issues << 'Report timestamp is in the future.' if age < -FUTURE_TOLERANCE_SECONDS
    rescue ArgumentError, TypeError, KeyError
      issues << 'Report timestamp is missing or invalid.'
    end

    audits = parsed['audits']
    document = audits.is_a?(Hash) ? audits['http-status-code'] : nil
    issues << 'Successful document HTTP audit is missing.' unless document.is_a?(Hash) && document['score'] == 1
    categories = parsed['categories']
    THRESHOLDS.each do |id, threshold|
      category = categories.is_a?(Hash) ? categories[id] : nil
      score = category.is_a?(Hash) ? category['score'] : nil
      result['scores'][id] = score
      unless score.is_a?(Numeric) && score.finite? && score >= threshold && score <= 1
        issues << "#{id} score is missing, invalid or below #{threshold}."
      end
    end
    result['status'] = 'pass' if issues.empty?
    result
  rescue JSON::ParserError, Errno::ENOENT, Errno::EACCES => error
    result['issues'] << "Report cannot be read: #{error.class}."
    result
  end
end

if $PROGRAM_NAME == __FILE__
  path, profile, expected_url = ARGV
  abort('Usage: public_lighthouse_evidence.rb REPORT.json mobile|desktop TARGET_URL') unless path && profile && expected_url
  result = PublicLighthouseEvidence.validate_file(path, expected_url: expected_url, profile: profile)
  puts JSON.pretty_generate(result)
  exit(result['status'] == 'pass' ? 0 : 1)
end
