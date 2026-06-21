#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

OUTPUT_FORMAT="text"
if [[ "${1:-}" == "--json" ]]; then
  OUTPUT_FORMAT="json"
elif [[ "${1:-}" != "" ]]; then
  printf 'usage: %s [--json]\n' "$0" >&2
  exit 2
fi

PACKAGE_NAME="${PACKAGE_NAME:-app.cool.mobile}"
DAYS="${DAYS:-28}"
OUTPUT_PATH="${OUTPUT_PATH:-.cache/google_play_optimization/google_play_reporting_snapshot.json}"

ROOT_DIR="$ROOT_DIR" PACKAGE_NAME="$PACKAGE_NAME" DAYS="$DAYS" OUTPUT_PATH="$OUTPUT_PATH" OUTPUT_FORMAT="$OUTPUT_FORMAT" ruby -r json -r net/http -r uri -r open3 -r time -r fileutils -r date <<'RUBY'
SCOPE = "https://www.googleapis.com/auth/playdeveloperreporting"
BASE = "https://playdeveloperreporting.googleapis.com/v1beta1"

root = ENV.fetch("ROOT_DIR")
package_name = ENV.fetch("PACKAGE_NAME")
days = Integer(ENV.fetch("DAYS"))
output_path = File.expand_path(ENV.fetch("OUTPUT_PATH"), root)
output_format = ENV.fetch("OUTPUT_FORMAT")

def token_from_command(command)
  return nil unless command && !command.strip.empty?
  stdout, stderr, status = Open3.capture3(command)
  return [stdout.strip, "custom_command"] if status.success? && !stdout.strip.empty?
  [nil, "custom_command_failed: #{stderr.lines.first.to_s.strip}"]
end

def token_from_gcloud(*cmd)
  stdout, stderr, status = Open3.capture3(*cmd)
  return [stdout.strip, cmd.join(" ")] if status.success? && !stdout.strip.empty?
  [nil, "#{cmd.join(" ")} failed: #{stderr.lines.first.to_s.strip}"]
end

def acquire_token
  return [ENV.fetch("PLAY_DEVELOPER_REPORTING_ACCESS_TOKEN"), "env"] if ENV["PLAY_DEVELOPER_REPORTING_ACCESS_TOKEN"].to_s.strip != ""

  token, source = token_from_command(ENV["PLAY_DEVELOPER_REPORTING_ACCESS_TOKEN_CMD"])
  return [token, source] if token

  token, source = token_from_gcloud("gcloud", "auth", "application-default", "print-access-token", "--scopes=#{SCOPE}")
  return [token, source] if token
  adc_error = source

  token, source = token_from_gcloud("gcloud", "auth", "print-access-token", "--scopes=#{SCOPE}")
  return [token, source] if token

  [nil, [adc_error, source].compact.join(" | ")]
end

def http_json(url, token, body)
  uri = URI(url)
  request = Net::HTTP::Post.new(uri)
  request["Authorization"] = "Bearer #{token}"
  request["Accept"] = "application/json"
  request["Content-Type"] = "application/json"
  request.body = JSON.generate(body)
  response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 20, read_timeout: 120) { |http| http.request(request) }
  parsed = JSON.parse(response.body.to_s) rescue { "raw" => response.body.to_s[0, 500] }
  unless response.code.to_i.between?(200, 299)
    message = parsed.dig("error", "message") || parsed["raw"] || response.message
    raise "HTTP #{response.code}: #{message}"
  end
  parsed
end

end_date = Date.today - 1
start_date = end_date - days + 1
timeline = {
  "aggregationPeriod" => "DAILY",
  "startTime" => { "year" => start_date.year, "month" => start_date.month, "day" => start_date.day },
  "endTime" => { "year" => end_date.year, "month" => end_date.month, "day" => end_date.day }
}
metric_sets = {
  "crash_rate" => {
    "path" => "crashRateMetricSet:query",
    "metrics" => ["crashRate", "userPerceivedCrashRate", "distinctUsers"]
  },
  "anr_rate" => {
    "path" => "anrRateMetricSet:query",
    "metrics" => ["anrRate", "userPerceivedAnrRate", "distinctUsers"]
  },
  "slow_start_rate" => {
    "path" => "slowStartRateMetricSet:query",
    "metrics" => ["slowStartRate", "distinctUsers"]
  },
  "error_counts" => {
    "path" => "errorCountMetricSet:query",
    "metrics" => ["errorReportCount"]
  },
  "excessive_wakeup_rate" => {
    "path" => "excessiveWakeupRateMetricSet:query",
    "metrics" => ["excessiveWakeupRate", "distinctUsers"]
  },
  "stuck_background_wakelock_rate" => {
    "path" => "stuckBackgroundWakelockRateMetricSet:query",
    "metrics" => ["stuckBackgroundWakelockRate", "distinctUsers"]
  },
  "slow_rendering_rate" => {
    "path" => "slowRenderingRateMetricSet:query",
    "metrics" => ["slowRenderingRate", "distinctUsers"]
  }
}

token, token_source = acquire_token
unless token
  result = {
    "generated_at" => Time.now.utc.iso8601,
    "status" => "blocked",
    "blockers" => ["play_developer_reporting_auth_unavailable"],
    "auth_error_summary" => token_source,
    "package_name" => package_name,
    "window_days" => days,
    "metric_sets" => metric_sets.keys,
    "required_scope" => SCOPE,
    "secret_handling" => "OAuth tokens, credential paths, cookies, signing keys, service account material, and customer data intentionally omitted."
  }
  FileUtils.mkdir_p(File.dirname(output_path))
  File.write(output_path, JSON.pretty_generate(result) + "\n")
  puts JSON.pretty_generate(result) if output_format == "json"
  warn "[google-play-reporting-snapshot][BLOCKED] play_developer_reporting_auth_unavailable" unless output_format == "json"
  exit 99
end

queries = {}
metric_sets.each do |name, config|
  body = {
    "timelineSpec" => timeline,
    "metrics" => config.fetch("metrics"),
    "dimensions" => ["versionCode"]
  }
  url = "#{BASE}/apps/#{package_name}/#{config.fetch("path")}"
  begin
    response = http_json(url, token, body)
    rows = Array(response["rows"]).first(50)
    queries[name] = {
      "status" => "pass",
      "row_count" => Array(response["rows"]).length,
      "rows_sample" => rows
    }
  rescue StandardError => e
    queries[name] = {
      "status" => "blocked",
      "error" => e.message.lines.first.to_s.strip
    }
  end
end

blocked = queries.select { |_name, value| value["status"] == "blocked" }
result = {
  "generated_at" => Time.now.utc.iso8601,
  "status" => blocked.empty? ? "pass" : "blocked",
  "blocker_keys" => blocked.keys,
  "package_name" => package_name,
  "window" => {
    "days" => days,
    "start_date" => start_date.iso8601,
    "end_date" => end_date.iso8601
  },
  "token_source" => token_source,
  "queries" => queries,
  "required_scope" => SCOPE,
  "secret_handling" => "OAuth tokens, credential paths, cookies, signing keys, service account material, and customer data intentionally omitted."
}

FileUtils.mkdir_p(File.dirname(output_path))
File.write(output_path, JSON.pretty_generate(result) + "\n")

if output_format == "json"
  puts JSON.pretty_generate(result)
else
  puts "[google-play-reporting-snapshot] status=#{result.fetch("status")}"
  blocked.each_key { |key| warn "[google-play-reporting-snapshot][BLOCKED] #{key}" }
  puts "[google-play-reporting-snapshot] evidence=#{output_path.sub(%r{\A#{Regexp.escape(root)}/?}, "")}"
end

exit(result.fetch("status") == "pass" ? 0 : 99)
RUBY
