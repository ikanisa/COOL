#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

BUILD_DIR="${PUBLIC_BUILD_DIR:-build/public_web}"
OUT_DIR="${PUBLIC_WEBSITE_LIGHTHOUSE_OUT:-output/public_website_evidence/lighthouse}"
TARGET_URL="${PUBLIC_WEBSITE_LIGHTHOUSE_URL:-}"
LIGHTHOUSE_PIN="13.4.0"

for name in mobile.json desktop.json summary.json; do
  if [[ -e "$OUT_DIR/$name" ]]; then
    echo "Refusing to replace retained evidence: $OUT_DIR/$name. Use a new PUBLIC_WEBSITE_LIGHTHOUSE_OUT." >&2
    exit 64
  fi
done

if [[ -n "${LIGHTHOUSE_CLI:-}" ]]; then
  LIGHTHOUSE_COMMAND=("${NODE_BIN:-node}" "$LIGHTHOUSE_CLI")
else
  LIGHTHOUSE_COMMAND=(npx --yes "lighthouse@$LIGHTHOUSE_PIN")
fi
OBSERVED_LIGHTHOUSE_VERSION="$("${LIGHTHOUSE_COMMAND[@]}" --version)"
if [[ "$OBSERVED_LIGHTHOUSE_VERSION" != "$LIGHTHOUSE_PIN" ]]; then
  echo "Expected Lighthouse $LIGHTHOUSE_PIN; found $OBSERVED_LIGHTHOUSE_VERSION" >&2
  exit 65
fi

mkdir -p "$OUT_DIR"

if [[ -z "$TARGET_URL" ]]; then
  PORT="$(ruby -rsocket -e 'server = TCPServer.new("127.0.0.1", 0); puts server.addr[1]; server.close')"
  SERVER_LOG="$OUT_DIR/server.log"

  ruby scripts/public_static_site_build.rb >/dev/null
  python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$BUILD_DIR" >"$SERVER_LOG" 2>&1 &
  SERVER_PID="$!"
  trap 'kill "$SERVER_PID" >/dev/null 2>&1 || true' EXIT

  SERVER_READY=0
  for _ in $(seq 1 80); do
    if curl -fsS "http://127.0.0.1:$PORT/" >/dev/null 2>&1; then
      SERVER_READY=1
      break
    fi
    sleep 0.25
  done
  if [[ "$SERVER_READY" != 1 ]]; then
    echo "Local public build server did not become ready; see $SERVER_LOG" >&2
    exit 1
  fi

  TARGET_URL="http://127.0.0.1:$PORT/"
fi

CHROME_FLAGS="--headless=new --disable-background-networking --disable-component-update --disable-sync"

ruby -r json -r digest - "$OUT_DIR" "$TARGET_URL" "$LIGHTHOUSE_PIN" <<'RUBY'
out_dir, url, version = ARGV
paths = %w[scripts/public_website_lighthouse_qa.sh scripts/public_website_completion_gate.sh scripts/qa/public_lighthouse_evidence.rb]
File.write(File.join(out_dir, 'source-before.json'), JSON.pretty_generate({
  'target_url' => url, 'lighthouse_version' => version,
  'sources' => paths.to_h { |path| [path, Digest::SHA256.file(path).hexdigest] }
}) + "\n")
RUBY

set +e
"${LIGHTHOUSE_COMMAND[@]}" "$TARGET_URL" \
  --quiet \
  --output=json \
  --output-path="$OUT_DIR/mobile.json" \
  --chrome-flags="$CHROME_FLAGS" > "$OUT_DIR/mobile.stdout" 2> "$OUT_DIR/mobile.stderr"
LIGHTHOUSE_MOBILE_RC=$?

"${LIGHTHOUSE_COMMAND[@]}" "$TARGET_URL" \
  --quiet \
  --preset=desktop \
  --output=json \
  --output-path="$OUT_DIR/desktop.json" \
  --chrome-flags="$CHROME_FLAGS" > "$OUT_DIR/desktop.stdout" 2> "$OUT_DIR/desktop.stderr"
LIGHTHOUSE_DESKTOP_RC=$?
set -e

ruby -r json -r time -r digest - "$OUT_DIR" "$TARGET_URL" "$LIGHTHOUSE_MOBILE_RC" "$LIGHTHOUSE_DESKTOP_RC" <<'RUBY'
require File.expand_path('scripts/qa/public_lighthouse_evidence', Dir.pwd)
out_dir, target_url, mobile_rc, desktop_rc = ARGV
reports = %w[mobile desktop].to_h do |profile|
  [profile, PublicLighthouseEvidence.validate_file(File.join(out_dir, "#{profile}.json"), expected_url: target_url, profile: profile)]
end
failures = reports.flat_map do |profile, result|
  result.fetch('issues').map { |issue| { 'profile' => profile, 'issue' => issue } }
end
exit_codes = { 'mobile' => mobile_rc.to_i, 'desktop' => desktop_rc.to_i }
exit_codes.each { |profile, code| failures << { 'profile' => profile, 'exit_code' => code } unless code.zero? }
before = JSON.parse(File.read(File.join(out_dir, 'source-before.json')))
changed = before.fetch('sources').keys.reject { |path| Digest::SHA256.file(path).hexdigest == before.fetch('sources').fetch(path) }
failures << { 'source_changed' => changed } unless changed.empty?
summary = {
  "status" => failures.empty? ? "pass" : "fail",
  "checked_at_utc" => Time.now.utc.iso8601,
  "target_url" => target_url,
  "lighthouse_version" => before.fetch('lighthouse_version'),
  "thresholds" => PublicLighthouseEvidence::THRESHOLDS,
  "scores" => reports.transform_values { |report| report.fetch('scores') },
  "validation" => reports,
  "exit_codes" => exit_codes,
  "source_inputs_unchanged" => changed.empty?,
  "scope" => 'Single Lighthouse lab run per profile; field Core Web Vitals and full-route acceptance remain unverified.',
  "failures" => failures,
}
File.write(File.join(out_dir, "summary.json"), JSON.pretty_generate(summary) + "\n")
puts JSON.pretty_generate(summary)
exit(failures.empty? ? 0 : 1)
RUBY
