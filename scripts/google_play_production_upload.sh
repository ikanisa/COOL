#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PACKAGE_NAME="${PACKAGE_NAME:-app.cool.mobile}"
TRACK="${TRACK:-production}"
STATUS="${STATUS:-completed}"
USER_FRACTION="${USER_FRACTION:-}"
AAB_PATH="${AAB_PATH:-build/app/outputs/bundle/productionRelease/app-production-release.aab}"
RELEASE_NAME="${RELEASE_NAME:-Collect 1.2.2 (12)}"
RELEASE_NOTES="${RELEASE_NOTES:-Adds native notification controls and optional receive-only MoMo SMS matching, with stronger permission recovery, accessibility, and security.}"
OUTPUT_PATH="${OUTPUT_PATH:-}"
OUTPUT_FORMAT="text"
SUBMIT="false"
CHANGES_NOT_SENT_FOR_REVIEW="false"

usage() {
  cat <<'USAGE'
Usage: scripts/google_play_production_upload.sh [--submit] [--json]

Uploads the current production AAB to Google Play via the Android Publisher API.
Defaults to dry-run validation. Pass --submit to create, update, and commit a
Play edit.

Environment:
  PACKAGE_NAME                         default: app.cool.mobile
  TRACK                                default: production
  STATUS                               default: completed
  USER_FRACTION                        optional, for staged rollout statuses
  AAB_PATH                             default: build/app/outputs/bundle/productionRelease/app-production-release.aab
  RELEASE_NAME                         default: Collect 1.2.2 (12)
  RELEASE_NOTES                        default release notes
  OUTPUT_PATH                          default: .cache/google_play_optimization/android_publisher_upload_v12.json
  ANDROID_PUBLISHER_ACCESS_TOKEN       optional bearer token; never printed
  ANDROID_PUBLISHER_ACCESS_TOKEN_CMD   optional command that prints a bearer token
  GOOGLE_APPLICATION_CREDENTIALS       service-account JSON is supported directly
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --submit)
      SUBMIT="true"
      shift
      ;;
    --json)
      OUTPUT_FORMAT="json"
      shift
      ;;
    --changes-not-sent-for-review)
      CHANGES_NOT_SENT_FOR_REVIEW="true"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$OUTPUT_PATH" ]]; then
  if [[ "$SUBMIT" == "true" ]]; then
    OUTPUT_PATH=".cache/google_play_optimization/android_publisher_upload_v12.json"
  else
    OUTPUT_PATH=".cache/google_play_optimization/android_publisher_upload_v12_dry_run.json"
  fi
fi

PACKAGE_NAME="$PACKAGE_NAME" \
TRACK="$TRACK" \
STATUS="$STATUS" \
USER_FRACTION="$USER_FRACTION" \
AAB_PATH="$AAB_PATH" \
RELEASE_NAME="$RELEASE_NAME" \
RELEASE_NOTES="$RELEASE_NOTES" \
OUTPUT_PATH="$OUTPUT_PATH" \
OUTPUT_FORMAT="$OUTPUT_FORMAT" \
SUBMIT="$SUBMIT" \
CHANGES_NOT_SENT_FOR_REVIEW="$CHANGES_NOT_SENT_FOR_REVIEW" \
ruby -r json -r net/http -r uri -r open3 -r time -r fileutils -r openssl -r base64 -r digest -r shellwords <<'RUBY'
SCOPE = "https://www.googleapis.com/auth/androidpublisher"
TOKEN_URI = "https://oauth2.googleapis.com/token"

package_name = ENV.fetch("PACKAGE_NAME")
track = ENV.fetch("TRACK")
status = ENV.fetch("STATUS")
user_fraction = ENV.fetch("USER_FRACTION")
aab_path = ENV.fetch("AAB_PATH")
release_name = ENV.fetch("RELEASE_NAME")
release_notes = ENV.fetch("RELEASE_NOTES")
output_path = ENV.fetch("OUTPUT_PATH")
output_format = ENV.fetch("OUTPUT_FORMAT")
submit = ENV.fetch("SUBMIT") == "true"
changes_not_sent_for_review = ENV.fetch("CHANGES_NOT_SENT_FOR_REVIEW") == "true"

def json_out(payload, output_path, output_format)
  FileUtils.mkdir_p(File.dirname(output_path))
  File.write(output_path, JSON.pretty_generate(payload) + "\n")
  if output_format == "json"
    puts JSON.pretty_generate(payload)
  else
    puts "[google-play-production-upload] status=#{payload.fetch("status")}"
    Array(payload["blockers"]).each { |item| warn "[google-play-production-upload][BLOCKED] #{item}" }
    puts "[google-play-production-upload] evidence=#{output_path}"
  end
end

def b64url(value)
  Base64.urlsafe_encode64(value).delete("=")
end

def http_json(method, url, token: nil, body: nil, content_type: "application/json")
  uri = URI(url)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = uri.scheme == "https"
  http.open_timeout = 30
  http.read_timeout = 900
  request = Net::HTTP.const_get(method).new(uri)
  request["Accept"] = "application/json"
  request["Authorization"] = "Bearer #{token}" if token
  if body
    request["Content-Type"] = content_type
    request.body = body
  end
  response = http.request(request)
  parsed = JSON.parse(response.body.to_s) rescue { "raw" => response.body.to_s[0, 500] }
  unless response.code.to_i.between?(200, 299)
    message = parsed.dig("error", "message") || parsed["raw"] || response.message
    raise "HTTP #{response.code} #{method} #{uri.path}: #{message}"
  end
  [response.code.to_i, parsed]
end

def form_post(url, params)
  uri = URI(url)
  response = Net::HTTP.post_form(uri, params)
  parsed = JSON.parse(response.body.to_s) rescue { "raw" => response.body.to_s[0, 500] }
  unless response.code.to_i.between?(200, 299)
    message = parsed.dig("error", "message") || parsed["raw"] || response.message
    raise "HTTP #{response.code} token exchange failed: #{message}"
  end
  parsed
end

def token_from_service_account(path)
  return nil unless path && File.file?(path)
  json = JSON.parse(File.read(path))
  return nil unless json["type"] == "service_account"

  now = Time.now.to_i
  header = b64url(JSON.generate({ alg: "RS256", typ: "JWT" }))
  claim = b64url(JSON.generate({
    iss: json.fetch("client_email"),
    scope: SCOPE,
    aud: json.fetch("token_uri", TOKEN_URI),
    exp: now + 3600,
    iat: now
  }))
  signer = OpenSSL::PKey::RSA.new(json.fetch("private_key"))
  signature = b64url(signer.sign(OpenSSL::Digest::SHA256.new, "#{header}.#{claim}"))
  assertion = "#{header}.#{claim}.#{signature}"
  token = form_post(json.fetch("token_uri", TOKEN_URI), {
    "grant_type" => "urn:ietf:params:oauth:grant-type:jwt-bearer",
    "assertion" => assertion
  })
  [token.fetch("access_token"), "service_account"]
rescue StandardError => e
  [nil, "service_account_failed: #{e.message}"]
end

def token_from_command(command)
  return nil unless command && !command.strip.empty?
  stdout, stderr, status = Open3.capture3(command)
  return [stdout.strip, "custom_command"] if status.success? && !stdout.strip.empty?
  [nil, "custom_command_failed: #{stderr.lines.first.to_s.strip}"]
rescue Errno::ENOENT => e
  [nil, "custom_command_unavailable: #{e.message.lines.first.to_s.strip}"]
end

def token_from_gcloud(*cmd)
  stdout, stderr, status = Open3.capture3(*cmd)
  return [stdout.strip, cmd.join(" ")] if status.success? && !stdout.strip.empty?
  [nil, "#{cmd.join(" ")} failed: #{stderr.lines.first.to_s.strip}"]
rescue Errno::ENOENT
  [nil, "#{cmd.first} unavailable"]
end

def acquire_token
  return [ENV.fetch("ANDROID_PUBLISHER_ACCESS_TOKEN"), "env"] if ENV["ANDROID_PUBLISHER_ACCESS_TOKEN"].to_s.strip != ""

  token, source = token_from_command(ENV["ANDROID_PUBLISHER_ACCESS_TOKEN_CMD"])
  return [token, source] if token

  token, source = token_from_service_account(ENV["GOOGLE_APPLICATION_CREDENTIALS"])
  return [token, source] if token
  service_account_error = source

  token, source = token_from_gcloud("gcloud", "auth", "application-default", "print-access-token", "--scopes=#{SCOPE}")
  return [token, source] if token
  adc_error = source

  token, source = token_from_gcloud("gcloud", "auth", "print-access-token", "--scopes=#{SCOPE}")
  return [token, source] if token

  [nil, [service_account_error, adc_error, source].compact.join(" | ")]
end

def sanitized_release(release)
  {
    "name" => release["name"],
    "status" => release["status"],
    "version_codes" => Array(release["versionCodes"]).map(&:to_s),
    "user_fraction" => release["userFraction"]
  }.compact
end

errors = []
errors << "missing AAB: #{aab_path}" unless File.file?(aab_path)
errors << "unsupported release status: #{status}" unless %w[draft inProgress halted completed].include?(status)
if submit
  packet_path = File.join(Dir.pwd, "docs/release/GOOGLE_PLAY_CONSOLE_AUDIT_PACKET.json")
  packet = JSON.parse(File.read(packet_path)) rescue {}
  declaration_status = packet.dig("app_content", "permissions", "sms_permissions_declaration_status")
  errors << "google_play_sms_permissions_declaration_not_approved" unless declaration_status == "approved"
end
if status == "inProgress"
  fraction = Float(user_fraction) rescue nil
  errors << "USER_FRACTION must be > 0 and < 1 for inProgress releases" unless fraction && fraction.positive? && fraction < 1
end
if errors.any?
  json_out({
    "generated_at" => Time.now.utc.iso8601,
    "status" => "fail",
    "blockers" => errors,
    "package_name" => package_name,
    "track" => track,
    "aab_path" => aab_path,
    "secret_handling" => "No tokens, credential paths, cookies, signing keys, or customer data are printed."
  }, output_path, output_format)
  exit 1
end

artifact = {
  "path" => File.expand_path(aab_path),
  "bytes" => File.size(aab_path),
  "sha256" => Digest::SHA256.file(aab_path).hexdigest
}

unless submit
  json_out({
    "generated_at" => Time.now.utc.iso8601,
    "status" => "dry_run",
    "package_name" => package_name,
    "track" => track,
    "release" => {
      "name" => release_name,
      "status" => status,
      "notes_language" => "en-US",
      "notes_length" => release_notes.length,
      "user_fraction" => user_fraction.empty? ? nil : user_fraction.to_f
    }.compact,
    "bundle" => artifact,
    "submit_required" => "Pass --submit after Android Publisher credentials are available.",
    "secret_handling" => "No tokens, credential paths, cookies, signing keys, or customer data are printed."
  }, output_path, output_format)
  exit 0
end

token, token_source = acquire_token
unless token
  json_out({
    "generated_at" => Time.now.utc.iso8601,
    "status" => "blocked",
    "blockers" => ["android_publisher_auth_unavailable"],
    "auth_error_summary" => token_source,
    "package_name" => package_name,
    "track" => track,
    "bundle" => artifact,
    "secret_handling" => "OAuth tokens, credential paths, cookies, signing keys, and service account material intentionally omitted."
  }, output_path, output_format)
  exit 99
end

base = "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/#{package_name}"
upload_base = "https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/#{package_name}"
observations = []
edit_id = nil

begin
  code, edit = http_json("Post", "#{base}/edits", token: token, body: "{}")
  observations << { "step" => "edits.insert", "code" => code }
  edit_id = edit.fetch("id")

  code, before_track = http_json("Get", "#{base}/edits/#{edit_id}/tracks/#{track}", token: token)
  observations << { "step" => "edits.tracks.get", "code" => code }

  code, upload = http_json(
    "Post",
    "#{upload_base}/edits/#{edit_id}/bundles?uploadType=media",
    token: token,
    body: File.binread(aab_path),
    content_type: "application/octet-stream"
  )
  observations << { "step" => "edits.bundles.upload", "code" => code }
  uploaded_version = upload.fetch("versionCode").to_s

  release = {
    "name" => release_name,
    "versionCodes" => [uploaded_version],
    "status" => status,
    "releaseNotes" => [
      {
        "language" => "en-US",
        "text" => release_notes
      }
    ]
  }
  release["userFraction"] = user_fraction.to_f if status == "inProgress"
  body = JSON.generate({ "track" => track, "releases" => [release] })
  code, updated_track = http_json("Put", "#{base}/edits/#{edit_id}/tracks/#{track}", token: token, body: body)
  observations << { "step" => "edits.tracks.update", "code" => code }

  commit_url = "#{base}/edits/#{edit_id}:commit"
  commit_url += "?changesNotSentForReview=true" if changes_not_sent_for_review
  code, commit = http_json("Post", commit_url, token: token, body: "{}")
  observations << { "step" => "edits.commit", "code" => code }

  json_out({
    "generated_at" => Time.now.utc.iso8601,
    "status" => "submitted",
    "package_name" => package_name,
    "track" => track,
    "bundle" => artifact.merge("version_code" => uploaded_version),
    "production_track_before" => {
      "release_count" => Array(before_track["releases"]).length,
      "version_codes" => Array(before_track["releases"]).flat_map { |release_item| Array(release_item["versionCodes"]) }.map(&:to_s).uniq,
      "statuses" => Array(before_track["releases"]).map { |release_item| release_item["status"] }.compact.uniq
    },
    "submitted_track" => {
      "track" => updated_track["track"],
      "releases" => Array(updated_track["releases"]).map { |release_item| sanitized_release(release_item) }
    },
    "commit_response_keys" => commit.keys.sort,
    "observations" => observations,
    "auth_source" => token_source == "env" ? "env" : token_source.split.first,
    "secret_handling" => "OAuth tokens, credential paths, cookies, signing keys, and service account material intentionally omitted."
  }, output_path, output_format)
rescue StandardError => e
  if edit_id
    begin
      code, = http_json("Delete", "#{base}/edits/#{edit_id}", token: token)
      observations << { "step" => "edits.delete_after_error", "code" => code }
    rescue StandardError => cleanup_error
      observations << { "step" => "edits.delete_after_error", "error" => cleanup_error.message }
    end
  end
  json_out({
    "generated_at" => Time.now.utc.iso8601,
    "status" => "failed",
    "package_name" => package_name,
    "track" => track,
    "bundle" => artifact,
    "error" => e.message,
    "observations" => observations,
    "secret_handling" => "OAuth tokens, credential paths, cookies, signing keys, and service account material intentionally omitted."
  }, output_path, output_format)
  exit 1
end
RUBY
