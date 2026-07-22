#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

BUILD_DIR="${PUBLIC_BUILD_DIR:-build/public_web}"
OUT_DIR="${PUBLIC_WEBSITE_LIGHTHOUSE_OUT:-output/public_website_evidence/lighthouse}"
TARGET_URL="${PUBLIC_WEBSITE_LIGHTHOUSE_URL:-}"

mkdir -p "$OUT_DIR"

if [[ -z "$TARGET_URL" ]]; then
  PORT="$(ruby -rsocket -e 'server = TCPServer.new("127.0.0.1", 0); puts server.addr[1]; server.close')"
  SERVER_LOG="$OUT_DIR/server.log"

  ruby scripts/public_static_site_build.rb >/dev/null
  python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$BUILD_DIR" >"$SERVER_LOG" 2>&1 &
  SERVER_PID="$!"
  trap 'kill "$SERVER_PID" >/dev/null 2>&1 || true' EXIT

  for _ in $(seq 1 80); do
    if curl -fsS "http://127.0.0.1:$PORT/" >/dev/null 2>&1; then
      break
    fi
    sleep 0.25
  done

  TARGET_URL="http://127.0.0.1:$PORT/"
fi

CHROME_FLAGS="--headless=new --no-sandbox --disable-gpu"

npx --yes lighthouse "$TARGET_URL" \
  --quiet \
  --output=json \
  --output-path="$OUT_DIR/mobile.json" \
  --chrome-flags="$CHROME_FLAGS"

npx --yes lighthouse "$TARGET_URL" \
  --quiet \
  --preset=desktop \
  --output=json \
  --output-path="$OUT_DIR/desktop.json" \
  --chrome-flags="$CHROME_FLAGS"

ruby -r json -r time - "$OUT_DIR" <<'RUBY'
out_dir = ARGV.fetch(0)
thresholds = {
  "performance" => 0.9,
  "accessibility" => 0.9,
  "best-practices" => 0.9,
  "seo" => 0.9,
}
reports = {
  "mobile" => JSON.parse(File.read(File.join(out_dir, "mobile.json"))),
  "desktop" => JSON.parse(File.read(File.join(out_dir, "desktop.json"))),
}
scores = reports.transform_values do |report|
  thresholds.keys.to_h { |key| [key, report.fetch("categories").fetch(key).fetch("score")] }
end
failures = scores.flat_map do |profile, items|
  items.each_with_object([]) do |(key, score), profile_failures|
    threshold = thresholds.fetch(key)
    if score < threshold
      profile_failures << {
        "profile" => profile,
        "category" => key,
        "score" => score,
        "threshold" => threshold,
      }
    end
  end
end
summary = {
  "status" => failures.empty? ? "pass" : "fail",
  "checked_at_utc" => Time.now.utc.iso8601,
  "thresholds" => thresholds,
  "scores" => scores,
  "failures" => failures,
}
File.write(File.join(out_dir, "summary.json"), JSON.pretty_generate(summary) + "\n")
puts JSON.pretty_generate(summary)
exit(failures.empty? ? 0 : 1)
RUBY
