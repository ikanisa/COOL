#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

output_format="text"
if [[ "${1:-}" == "--json" ]]; then
  output_format="json"
elif [[ "${1:-}" != "" ]]; then
  printf 'usage: %s [--json]\n' "$0" >&2
  exit 2
fi

set +e
gradle_output="$(
  cd "$ROOT_DIR/android" &&
    ./gradlew -q :app:printReleaseSigningCertificateStatus --console=plain 2>&1
)"
gradle_rc=$?
set -e

OUTPUT_FORMAT="$output_format" GRADLE_OUTPUT="$gradle_output" GRADLE_RC="$gradle_rc" ruby -r json <<'RUBY'
output_format = ENV.fetch("OUTPUT_FORMAT")
gradle_output = ENV.fetch("GRADLE_OUTPUT")
gradle_rc = ENV.fetch("GRADLE_RC").to_i

def parse_json_object(text)
  start_index = text.index("{")
  end_index = text.rindex("}")
  return nil unless start_index && end_index && end_index >= start_index

  JSON.parse(text[start_index..end_index])
rescue JSON::ParserError
  nil
end

summary = parse_json_object(gradle_output)
summary =
  if summary
    summary.merge(
      "gradle_exit_code" => gradle_rc,
      "secret_handling" => "This preflight reports certificate fingerprints and boolean configuration state only; it does not print keystore passwords or key aliases."
    )
  else
    {
      "status" => "blocked",
      "message" => "Unable to read Android signing preflight status from Gradle.",
      "gradle_exit_code" => gradle_rc,
      "gradle_output_tail" => gradle_output.lines.last(20).join,
      "expected_upload_signing_sha256" => nil,
      "matches_expected_upload_certificate" => false,
      "expected_play_signing_sha256" => nil,
      "matches_expected_play_signing_certificate" => false,
      "play_app_signing_certificate_note" => "Google Play App Signing uses the upload key for uploaded bundles and the Play app-signing key for APKs delivered to users.",
      "secret_handling" => "Gradle output tail is included for diagnostics; the Gradle task does not print signing passwords or key aliases."
    }
  end

if output_format == "json"
  puts JSON.pretty_generate(summary)
else
  puts "[android-release-signing-preflight] status=#{summary.fetch("status")}"
  puts "[android-release-signing-preflight] message=#{summary.fetch("message")}"
  if summary["configured_certificate_sha256"]
    puts "[android-release-signing-preflight] configured_certificate_sha256=#{summary["configured_certificate_sha256"]}"
  end
  if summary.key?("expected_upload_signing_sha256")
    puts "[android-release-signing-preflight] expected_upload_signing_sha256=#{summary["expected_upload_signing_sha256"] || "not_configured"}"
  end
  if summary["expected_play_signing_sha256"]
    puts "[android-release-signing-preflight] expected_play_signing_sha256=#{summary["expected_play_signing_sha256"]}"
  end
end

exit(summary.fetch("status") == "pass" ? 0 : 1)
RUBY
