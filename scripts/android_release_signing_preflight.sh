#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

output_format="text"
public_defines=""
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --json) output_format="json"; shift ;;
    --public-defines)
      [[ "$#" -ge 2 && -n "$2" && -z "$public_defines" ]] || { printf 'A single public defines file is required.\n' >&2; exit 2; }
      public_defines="$2"; shift 2 ;;
    *) printf 'usage: %s [--json] [--public-defines PATH]\n' "$0" >&2; exit 2 ;;
  esac
done
umask 077
defines_dir=""
cleanup() {
  if [[ -n "$defines_dir" ]]; then
    rm -f "$defines_dir/defines.json"
    rmdir "$defines_dir" 2>/dev/null || true
  fi
}
trap cleanup EXIT
if [[ -z "$public_defines" ]]; then
  defines_dir="$(mktemp -d "${TMPDIR:-/tmp}/collect-signing-public-defines.XXXXXX")"
  public_defines="$defines_dir/defines.json"
  python3 scripts/qa/native_build_config.py android --defines-output "$public_defines"
fi
# Validate the exact caller profile rather than rebuilding it from another env.
python3 scripts/qa/native_build_config.py android --validate-defines "$public_defines"
public_gradle_defines="$(ruby -r json -r base64 -e 'puts JSON.parse(File.read(ARGV.fetch(0))).sort.map { |key, value| Base64.strict_encode64("#{key}=#{value}") }.join(",")' "$public_defines")"

set +e
gradle_output="$(
  cd "$ROOT_DIR/android" &&
    ./gradlew -q "-Pdart-defines=$public_gradle_defines" :app:printReleaseSigningCertificateStatus --console=plain 2>&1
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
