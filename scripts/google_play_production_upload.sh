#!/usr/bin/env bash
set -euo pipefail
umask 077

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PACKAGE_NAME="${PACKAGE_NAME:-app.cool.mobile}"
TRACK="${TRACK:-production}"
STATUS="${STATUS:-}"
USER_FRACTION="${USER_FRACTION:-}"
AAB_PATH="${AAB_PATH:-build/app/outputs/bundle/productionRelease/app-production-release.aab}"
PACKAGE_VERSION="$(sed -n 's/^version:[[:space:]]*//p' pubspec.yaml | head -n 1)"
[[ "$PACKAGE_VERSION" == *+* ]] || {
  printf '[google-play-production-upload][FAIL] pubspec.yaml version must include a build number.\n' >&2
  exit 2
}
BUILD_NAME="${PACKAGE_VERSION%%+*}"
BUILD_NUMBER="${PACKAGE_VERSION##*+}"
RELEASE_NAME="${RELEASE_NAME:-Collect $BUILD_NAME ($BUILD_NUMBER)}"
CHANGELOG_PATH="fastlane/metadata/android/en-US/changelogs/${BUILD_NUMBER}.txt"
RELEASE_NOTES="${RELEASE_NOTES:-}"
OUTPUT_PATH="${OUTPUT_PATH:-}"
OUTPUT_FORMAT="text"
SUBMIT="false"
PHASE="prepare"
PHASE_EXPLICIT="false"
FULL_ROLLOUT="false"
CHANGES_NOT_SENT_FOR_REVIEW="false"

usage() {
  cat <<'USAGE'
Usage: scripts/google_play_production_upload.sh [--phase prepare|upload|review|rollout] [--submit] [--full-rollout] [--json]

Defaults to local dry-run preparation. Every mutation requires --submit and an
explicit phase, plus the unchanged production preflight and phase readiness gate.
  upload: upload once and commit a draft; never modify testing tracks.
  review: promote the existing draft for review, with captured managed publishing
          enabled so approval cannot automatically publish the candidate.
  rollout: promote the same approved candidate using explicit USER_FRACTION,
           or --full-rollout for completed. Console publication/readback remains
           necessary when managed publishing is enabled. A commit is not proof
           of Google's approval, review state, or production availability.

Environment:
  PACKAGE_NAME                         default: app.cool.mobile
  TRACK                                default: production
  STATUS                               derived from phase; cannot override it
  USER_FRACTION                        required for staged rollout; 0 < value < 1
  AAB_PATH                             default: build/app/outputs/bundle/productionRelease/app-production-release.aab
  RELEASE_NAME                         upload only; default: Collect version/build
  RELEASE_NOTES                        upload only; default: matching Fastlane changelog
  OUTPUT_PATH                          default: .cache/google_play_optimization/android_publisher_upload_v<pubspec build>.json
  ANDROID_PUBLISHER_ACCESS_TOKEN       optional bearer token; never printed
  ANDROID_PUBLISHER_ACCESS_TOKEN_CMD   optional command that prints a bearer token
  GOOGLE_APPLICATION_CREDENTIALS       service-account JSON is supported directly
  GOOGLE_PLAY_SERVICE_ACCOUNT_JSON     optional service-account JSON, kept in memory
  REPLACE_INTERNAL_RESTRICTED_ARTIFACTS retired; true is rejected (separate review required)
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --submit)
      SUBMIT="true"
      shift
      ;;
    --phase)
      [[ $# -gt 1 ]] || { printf 'Missing --phase value.\n' >&2; exit 2; }
      PHASE="$2"
      PHASE_EXPLICIT="true"
      shift 2
      ;;
    --full-rollout)
      FULL_ROLLOUT="true"
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

fail() { printf '[google-play-production-upload][FAIL] %s\n' "$1" >&2; exit 1; }
case "$PHASE" in
  prepare|upload) phase_status="draft" ;;
  review) phase_status="completed" ;;
  rollout)
    if [[ "$FULL_ROLLOUT" == "true" ]]; then phase_status="completed"; else phase_status="inProgress"; fi
    ;;
  *) fail 'Invalid --phase; expected prepare, upload, review or rollout.' ;;
esac
if [[ "$PHASE" == "prepare" || "$PHASE" == "upload" ]]; then
  if [[ -z "$RELEASE_NOTES" ]]; then
    [[ -s "$CHANGELOG_PATH" ]] || fail "Missing release notes: $CHANGELOG_PATH"
    RELEASE_NOTES="$(<"$CHANGELOG_PATH")"
  fi
fi
[[ "$FULL_ROLLOUT" == "false" || "$PHASE" == "rollout" ]] || fail '--full-rollout is only valid for the rollout phase.'
[[ -z "$STATUS" || "$STATUS" == "$phase_status" ]] || fail 'STATUS conflicts with the explicit phase and rollout choice.'
STATUS="$phase_status"
if [[ "$STATUS" == "inProgress" ]]; then
  USER_FRACTION="$USER_FRACTION" ruby -e 'n = Float(ENV.fetch("USER_FRACTION")) rescue nil; exit(n && n.finite? && n > 0 && n < 1 ? 0 : 1)' || fail 'Staged rollout requires explicit USER_FRACTION > 0 and < 1.'
else
  [[ -z "$USER_FRACTION" ]] || fail 'USER_FRACTION is only valid for a staged rollout.'
fi
[[ "${REPLACE_INTERNAL_RESTRICTED_ARTIFACTS:-false}" == "false" ]] || fail 'This command cannot replace testing-track artifacts; use a separately reviewed testing-track operation.'
if [[ "$PHASE" == "upload" ]]; then
  CHANGES_NOT_SENT_FOR_REVIEW="true"
elif [[ "$CHANGES_NOT_SENT_FOR_REVIEW" == "true" ]]; then
  fail '--changes-not-sent-for-review is only valid for draft upload.'
fi
if [[ "$SUBMIT" == "true" ]]; then
  [[ "$PHASE_EXPLICIT" == "true" && "$PHASE" != "prepare" ]] || fail '--submit requires explicit --phase upload, review or rollout.'
fi

if [[ -z "$OUTPUT_PATH" ]]; then
  if [[ "$SUBMIT" == "true" ]]; then
    OUTPUT_PATH=".cache/google_play_optimization/android_publisher_${PHASE}_v${BUILD_NUMBER}.json"
  else
    OUTPUT_PATH=".cache/google_play_optimization/android_publisher_${PHASE}_v${BUILD_NUMBER}_dry_run.json"
  fi
fi

resolved_output_path="$(OUTPUT_PATH="$OUTPUT_PATH" ruby -e 'puts File.expand_path(ENV.fetch("OUTPUT_PATH"))')"
case "$resolved_output_path" in
  "$ROOT_DIR"/.cache/*|"$ROOT_DIR"/output/*) ;;
  *)
    printf '[google-play-production-upload][FAIL] OUTPUT_PATH must stay under repository .cache or output.\n' >&2
    exit 1
    ;;
esac

if [[ "$SUBMIT" == "true" ]]; then
  # The upload path must not be able to bypass the independently pinned
  # production-backend, artifact, SMS-policy, and console-state controls.
  "$ROOT_DIR/scripts/release_go_preflight.sh" >/dev/null
  canonical_aab="$ROOT_DIR/build/app/outputs/bundle/productionRelease/app-production-release.aab"
  [[ "$PACKAGE_NAME" == "app.cool.mobile" ]] || {
    printf '[google-play-production-upload][FAIL] --submit is pinned to app.cool.mobile.\n' >&2
    exit 1
  }
  [[ "$TRACK" == "production" ]] || fail '--submit is pinned to the production track.'
  resolved_aab="$(AAB_PATH="$AAB_PATH" ruby -e 'puts File.expand_path(ENV.fetch("AAB_PATH"))')"
  [[ "$resolved_aab" == "$canonical_aab" && -f "$canonical_aab" && ! -L "$canonical_aab" ]] || {
    printf '[google-play-production-upload][FAIL] --submit requires the canonical, non-symlink production AAB.\n' >&2
    exit 1
  }
  gated_aab_sha256="$(AAB_PATH="$canonical_aab" ruby -r digest -e 'puts Digest::SHA256.file(ENV.fetch("AAB_PATH")).hexdigest')"
  packet_path="$ROOT_DIR/docs/release/GOOGLE_PLAY_CONSOLE_AUDIT_PACKET.json"
  [[ -f "$packet_path" && ! -L "$packet_path" ]] || fail 'Canonical Play packet is missing or symlinked.'
  gated_packet_sha256="$(ruby -r digest -e 'puts Digest::SHA256.file(ARGV.fetch(0)).hexdigest' "$packet_path")"
  # The direct publisher and Fastlane share these packet/privacy/asset checks.
  GOOGLE_PLAY_CONSOLE_AUDIT_PACKET="$packet_path" \
  OUTPUT_PATH="$ROOT_DIR/.cache/google_play_optimization/google_play_console_audit_packet_${PHASE}.json" \
    "$ROOT_DIR/scripts/google_play_console_audit_packet.sh" --phase "$PHASE" --json >/dev/null
  "$ROOT_DIR/scripts/google_play_optimization_gate.sh" --phase "$PHASE" --json >/dev/null
  post_gate_sha256="$(AAB_PATH="$canonical_aab" ruby -r digest -e 'puts Digest::SHA256.file(ENV.fetch("AAB_PATH")).hexdigest')"
  [[ "$post_gate_sha256" == "$gated_aab_sha256" ]] || {
    printf '[google-play-production-upload][FAIL] Production AAB changed after the Play readiness gate.\n' >&2
    exit 1
  }
  [[ "$(ruby -r digest -e 'puts Digest::SHA256.file(ARGV.fetch(0)).hexdigest' "$packet_path")" == "$gated_packet_sha256" ]] || fail 'Play packet changed during the readiness gate.'
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
PHASE="$PHASE" \
BUILD_NUMBER="$BUILD_NUMBER" \
CHANGES_NOT_SENT_FOR_REVIEW="$CHANGES_NOT_SENT_FOR_REVIEW" \
GATED_AAB_SHA256="${gated_aab_sha256:-}" \
GATED_PACKET_SHA256="${gated_packet_sha256:-}" \
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
phase = ENV.fetch("PHASE")
build_number = ENV.fetch("BUILD_NUMBER")
changes_not_sent_for_review = ENV.fetch("CHANGES_NOT_SENT_FOR_REVIEW") == "true"
gated_aab_sha256 = ENV.fetch("GATED_AAB_SHA256", "")

if submit
  abort("Play-gated AAB digest is missing") if gated_aab_sha256.empty?
  abort("Production AAB changed before upload") unless File.file?(aab_path) &&
    Digest::SHA256.file(aab_path).hexdigest == gated_aab_sha256
  packet_path = File.join(Dir.pwd, "docs/release/GOOGLE_PLAY_CONSOLE_AUDIT_PACKET.json")
  abort("Play packet changed after readiness checks") unless
    Digest::SHA256.file(packet_path).hexdigest == ENV.fetch("GATED_PACKET_SHA256")
end

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
    # Provider bodies may echo customer or credential material. Keep only the
    # operation and HTTP status in persisted release evidence.
    raise "HTTP #{response.code} #{method} #{uri.path}"
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

def token_from_service_account(path, data = nil)
  return nil unless data || (path && File.file?(path))
  json = JSON.parse(data || File.read(path))
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
rescue StandardError
  [nil, "service_account_failed"]
end

def token_from_command(command)
  return nil unless command && !command.strip.empty?
  stdout, _stderr, status = Open3.capture3(command)
  return [stdout.strip, "custom_command"] if status.success? && !stdout.strip.empty?
  [nil, "custom_command_failed"]
rescue Errno::ENOENT
  [nil, "custom_command_unavailable"]
end

def token_from_gcloud(*cmd)
  stdout, _stderr, status = Open3.capture3(*cmd)
  return [stdout.strip, cmd.join(" ")] if status.success? && !stdout.strip.empty?
  [nil, "#{cmd.first}_auth_failed"]
rescue Errno::ENOENT
  [nil, "#{cmd.first} unavailable"]
end

def acquire_token
  return [ENV.fetch("ANDROID_PUBLISHER_ACCESS_TOKEN"), "env"] if ENV["ANDROID_PUBLISHER_ACCESS_TOKEN"].to_s.strip != ""

  token, source = token_from_command(ENV["ANDROID_PUBLISHER_ACCESS_TOKEN_CMD"])
  return [token, source] if token

  token, source = token_from_service_account(nil, ENV["GOOGLE_PLAY_SERVICE_ACCOUNT_JSON"])
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
  permissions = Array(packet.dig("app_content", "permissions", "production_permissions"))
  restricted_sms = %w[android.permission.READ_SMS android.permission.RECEIVE_SMS android.permission.SEND_SMS android.permission.BROADCAST_SMS]
  errors << "google_play_sms_permission_scope_mismatch" unless (permissions & restricted_sms) == ["android.permission.RECEIVE_SMS"]
  allowed_declarations = phase == "rollout" ? ["approved_for_core_functionality"] :
    %w[required_pending_play_approval approved_for_core_functionality]
  errors << "google_play_sms_declaration_invalid_for_phase" unless allowed_declarations.include?(declaration_status)
end
if status == "inProgress"
  fraction = Float(user_fraction) rescue nil
  errors << "USER_FRACTION must be > 0 and < 1 for inProgress releases" unless fraction && fraction.positive? && fraction < 1
end
if errors.any?
  json_out({
    "generated_at" => Time.now.utc.iso8601,
    "status" => "fail",
    "phase" => phase,
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
    "phase" => phase,
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
    "submit_required" => "Use --submit with an explicit upload, review or rollout phase after its gates pass.",
    "production_availability_verified" => false,
    "mutates_testing_tracks" => false,
    "secret_handling" => "No tokens, credential paths, cookies, signing keys, or customer data are printed."
  }, output_path, output_format)
  exit 0
end

token, token_source = acquire_token
unless token
  json_out({
    "generated_at" => Time.now.utc.iso8601,
    "status" => "blocked",
    "phase" => phase,
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
commit_attempted = false
commit_succeeded = false

begin
  code, edit = http_json("Post", "#{base}/edits", token: token, body: "{}")
  observations << { "step" => "edits.insert", "code" => code }
  edit_id = edit.fetch("id")

  code, before_track = http_json("Get", "#{base}/edits/#{edit_id}/tracks/#{track}", token: token)
  observations << { "step" => "edits.tracks.get", "code" => code }

  target_releases = Array(before_track["releases"]).select do |item|
    Array(item["versionCodes"]).map(&:to_s).include?(build_number)
  end
  if phase == "upload"
    raise "Candidate is already on the track; reconcile its state instead of re-uploading" if target_releases.any?
    bundle_bytes = File.binread(aab_path)
    raise "Production AAB changed before upload" unless Digest::SHA256.hexdigest(bundle_bytes) == gated_aab_sha256
    code, upload = http_json(
      "Post", "#{upload_base}/edits/#{edit_id}/bundles?uploadType=media",
      token: token, body: bundle_bytes, content_type: "application/octet-stream"
    )
    observations << { "step" => "edits.bundles.upload", "code" => code }
    raise "Uploaded version does not match the gated release" unless upload["versionCode"].to_s == build_number
    raise "Uploaded bundle digest does not match the gated release" unless upload["sha256"].to_s.downcase == gated_aab_sha256
    existing_release = {}
  else
    raise "Exactly one existing candidate release is required; upload and reconcile first" unless target_releases.length == 1 &&
      Array(target_releases.first["versionCodes"]).map(&:to_s) == [build_number]
    existing_release = target_releases.first
    if phase == "review"
      raise "Review requires the existing draft; reconcile a prior review before retrying" unless existing_release["status"] == "draft"
    else
      raise "Rollout requires an existing reviewed candidate" unless %w[completed inProgress halted].include?(existing_release["status"])
    end
    # The same version code must resolve to the accepted bytes in Play, not just
    # to a similarly named release or a stale local receipt.
    code, bundles = http_json("Get", "#{base}/edits/#{edit_id}/bundles", token: token)
    observations << { "step" => "edits.bundles.list", "code" => code }
    remote = Array(bundles["bundles"]).find { |item| item["versionCode"].to_s == build_number }
    raise "Existing Play bundle digest does not match the gated release" unless remote && remote["sha256"].to_s.downcase == gated_aab_sha256
  end
  uploaded_version = build_number

  release = if phase == "upload"
    { "name" => release_name, "versionCodes" => [uploaded_version],
      "releaseNotes" => [{ "language" => "en-US", "text" => release_notes }] }
  else
    # Promotion changes rollout state, never the notes/name already inspected
    # in Console. Environment/changelog edits cannot replace approved metadata.
    existing_release.dup
  end
  release["status"] = status
  release.delete("userFraction")
  release.delete("countryTargeting")
  if status == "inProgress"
    release["userFraction"] = user_fraction.to_f
    release["countryTargeting"] = { "countries" => ["RW"], "includeRestOfWorld" => false }
  end
  # Preserve other releases verbatim, including drafts and staged releases.
  prior_releases = Array(before_track["releases"]).reject do |prior_release|
    Array(prior_release["versionCodes"]).map(&:to_s).include?(uploaded_version)
  end
  body = JSON.generate({ "track" => track, "releases" => prior_releases + [release] })
  code, updated_track = http_json("Put", "#{base}/edits/#{edit_id}/tracks/#{track}", token: token, body: body)
  observations << { "step" => "edits.tracks.update", "code" => code }

  commit_url = "#{base}/edits/#{edit_id}:commit?changesInReviewBehavior=ERROR_IF_IN_REVIEW"
  commit_url += "&changesNotSentForReview=true" if changes_not_sent_for_review
  commit_attempted = true
  code, commit = http_json("Post", commit_url, token: token)
  commit_succeeded = true
  observations << { "step" => "edits.commit", "code" => code }

  json_out({
    "generated_at" => Time.now.utc.iso8601,
    "status" => phase == "upload" ? "draft_committed" : "#{phase}_change_committed",
    "phase" => phase,
    "production_availability_verified" => false,
    "google_review_state_verified" => false,
    "next_action" => phase == "upload" ?
      "Capture candidate Console/pre-launch findings, verify listing/declarations and managed publishing, then qualify review phase." :
      "Read Publishing overview and the production track in Console. Managed publishing may require Publish changes. A successful edit commit does not prove in-review, approved or live availability.",
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
    "mutates_testing_tracks" => false,
    "commit_response_keys" => commit.keys.sort,
    "observations" => observations,
    "auth_source" => token_source == "env" ? "env" : token_source.split.first,
    "secret_handling" => "OAuth tokens, credential paths, cookies, signing keys, and service account material intentionally omitted."
  }, output_path, output_format)
rescue StandardError => e
  # A lost commit response may mean the edit was committed. Never delete/retry
  # blindly; retain an unknown-outcome receipt for live reconciliation first.
  outcome_unknown = commit_attempted && !commit_succeeded
  if edit_id && !commit_attempted
    begin
      code, = http_json("Delete", "#{base}/edits/#{edit_id}", token: token)
      observations << { "step" => "edits.delete_after_error", "code" => code }
    rescue StandardError => cleanup_error
      observations << { "step" => "edits.delete_after_error", "error" => cleanup_error.message }
    end
  end
  json_out({
    "generated_at" => Time.now.utc.iso8601,
    "status" => outcome_unknown ? "commit_outcome_unknown" : "failed",
    "phase" => phase,
    "production_availability_verified" => false,
    "reconcile_before_retry" => outcome_unknown,
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
