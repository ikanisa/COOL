#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLUTTER="${FLUTTER:-/Users/jeanbosco/Developer/flutter/bin/flutter}"
NODE="${NODE:-/Users/jeanbosco/.codex/runners/africlub/externals/node20/bin/node}"
BUILD_DIR="${ADMIN_PWA_AUTH_RENDER_BUILD_DIR:-$ROOT_DIR/.cache/admin_pwa_authenticated_render_build}"
EVIDENCE_DIR="${ADMIN_PWA_AUTH_RENDER_EVIDENCE_DIR:-$ROOT_DIR/.cache/admin_pwa_authenticated_render_smoke/$(date -u +%Y%m%dT%H%M%SZ)}"
HOST="${ADMIN_PWA_AUTH_RENDER_HOST:-127.0.0.1}"
PORT="${ADMIN_PWA_AUTH_RENDER_PORT:-}"
VIEWPORT_MOBILE="${ADMIN_PWA_AUTH_RENDER_MOBILE_VIEWPORT:-390x844}"
VIEWPORT_DESKTOP="${ADMIN_PWA_AUTH_RENDER_DESKTOP_VIEWPORT:-1440x900}"
RENDER_WAIT_MS="${ADMIN_PWA_AUTH_RENDER_WAIT_MS:-10000}"
DEVTOOLS_READY_MS="${ADMIN_PWA_AUTH_RENDER_DEVTOOLS_READY_MS:-60000}"
COMMAND_TIMEOUT_MS="${ADMIN_PWA_AUTH_RENDER_COMMAND_TIMEOUT_MS:-60000}"

fail() {
  printf '[admin-pwa-auth-render][FAIL] %s\n' "$*" >&2
  exit 1
}

case "$BUILD_DIR" in
  "$ROOT_DIR"/.cache/*) ;;
  *) fail "Admin evidence build directory must stay under $ROOT_DIR/.cache/." ;;
esac
mkdir -p "$EVIDENCE_DIR" "$BUILD_DIR"

if [[ "$NODE" == */* ]]; then
  [[ -x "$NODE" ]] || fail "Node.js is required for Admin PWA evidence: $NODE"
else
  command -v "$NODE" >/dev/null 2>&1 || fail "Node.js is required for Admin PWA evidence: $NODE"
fi

find_chrome() {
  if [[ -n "${ADMIN_PWA_CHROME:-}" ]]; then
    printf '%s\n' "$ADMIN_PWA_CHROME"
    return 0
  fi
  for candidate in \
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
    "/Applications/Chromium.app/Contents/MacOS/Chromium"; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  for candidate in google-chrome chromium chromium-browser; do
    if command -v "$candidate" >/dev/null 2>&1; then
      command -v "$candidate"
      return 0
    fi
  done
}

wait_for_http() {
  local url="$1"
  local attempts="$2"
  for _ in $(seq 1 "$attempts"); do
    if curl -fsS "$url" >/dev/null 2>&1; then
      return 0
    fi
    if ! kill -0 "$SERVER_PID" 2>/dev/null; then
      sed -n '1,160p' "$EVIDENCE_DIR/http.log" >&2 || true
      fail "HTTP server exited before $url was ready."
    fi
    sleep 0.5
  done
  return 1
}

CHROME="$(find_chrome || true)"
if [[ -z "$CHROME" || ! -x "$CHROME" ]]; then
  fail "Chrome/Chromium is required for authenticated Admin PWA render evidence."
fi

if [[ "${ADMIN_PWA_AUTH_RENDER_SKIP_BUILD:-0}" == "1" ]]; then
  [[ -s "$BUILD_DIR/main.dart.js" ]] ||
    fail "Existing Admin evidence build is missing main.dart.js: $BUILD_DIR"
  if find lib -type f -newer "$BUILD_DIR/main.dart.js" -print -quit |
    grep -q .; then
    fail "Existing Admin evidence build is stale relative to current Dart sources."
  fi
  printf '[admin-pwa-auth-render] reused current evidence build %s\n' "$BUILD_DIR" \
    >"$EVIDENCE_DIR/flutter_build.log"
else
  rm -rf "$BUILD_DIR"
  "$FLUTTER" build web \
    -t lib/main_admin.dart \
    --output="$BUILD_DIR" \
    --release \
    --no-wasm-dry-run \
    --no-web-resources-cdn \
    --no-pub \
    --dart-define=APP_ENVIRONMENT=evidence \
    --dart-define=ENABLE_ADMIN_PANEL=true \
    --dart-define=ADMIN_PWA_EVIDENCE_MODE=true \
    >"$EVIDENCE_DIR/flutter_build.log" 2>&1

  touch "$BUILD_DIR/main.dart.js"
fi

if [[ -z "$PORT" ]]; then
  PORT="$(ruby -rsocket -e 'server = TCPServer.new("127.0.0.1", 0); puts server.addr[1]; server.close')"
fi

"$NODE" "$ROOT_DIR/scripts/static_file_server.mjs" \
  --host "$HOST" \
  --port "$PORT" \
  --dir "$BUILD_DIR" >"$EVIDENCE_DIR/http.log" 2>&1 &
SERVER_PID=$!
trap 'kill "$SERVER_PID" 2>/dev/null || true' EXIT

BASE_URL="http://$HOST:$PORT"
wait_for_http "$BASE_URL/" 60 || fail "HTTP server did not become ready at $BASE_URL/."
curl -fsSI "$BASE_URL/" >"$EVIDENCE_DIR/index.headers" || fail "index.html did not serve."
curl -fsSI "$BASE_URL/main.dart.js" >"$EVIDENCE_DIR/main.headers" || fail "main.dart.js did not serve."

captures_json="$EVIDENCE_DIR/captures.jsonl"
: >"$captures_json"

capture_route() {
  local name="$1"
  local route="$2"
  local viewport="$3"
  local png="$EVIDENCE_DIR/${name}-${viewport}.png"
  local profile="$EVIDENCE_DIR/${name}-profile"
  local url="$BASE_URL/#$route"

  "$NODE" "$ROOT_DIR/scripts/chrome_cdp_capture.mjs" \
    --chrome "$CHROME" \
    --url "$url" \
    --output "$png" \
    --profile "$profile" \
    --viewport "$viewport" \
    --wait-ms "$RENDER_WAIT_MS" \
    --devtools-ready-ms "$DEVTOOLS_READY_MS" \
    --command-timeout-ms "$COMMAND_TIMEOUT_MS" \
    >"$EVIDENCE_DIR/${name}.stdout" 2>"$EVIDENCE_DIR/${name}.stderr" || {
      sed -n '1,180p' "$EVIDENCE_DIR/${name}.stderr" >&2 || true
      fail "$name screenshot capture failed."
    }

  "$NODE" "$ROOT_DIR/scripts/png_capture_check.mjs" \
    "$png" \
    "$viewport" \
    "$name" \
    "$route" \
    "$url" \
    "$captures_json"
}

capture_route "admin-overview" "/admin" "$VIEWPORT_DESKTOP"
capture_route "admin-groups-list" "/admin/groups" "$VIEWPORT_DESKTOP"
capture_route "admin-payment-events" "/admin/payment-events" "$VIEWPORT_MOBILE"
capture_route "admin-payment-intents" "/admin/payment-intents" "$VIEWPORT_DESKTOP"
capture_route "admin-sms-detail" "/admin/sms/sms-1" "$VIEWPORT_DESKTOP"
capture_route "admin-system-health" "/admin/system-health" "$VIEWPORT_DESKTOP"

browser_qa_dir="$EVIDENCE_DIR/browser-qa"
env -u ADMIN_PWA_BROWSER_QA_ROUTE -u ADMIN_PWA_BROWSER_QA_VIEWPORT \
  "$NODE" "$ROOT_DIR/scripts/admin_pwa_browser_qa.mjs" \
  "$BASE_URL/" \
  "$browser_qa_dir"

ruby -r json -r time -e '
  evidence_dir, build_dir, base_url, captures_json, browser_report_path = ARGV
  captures = File.readlines(captures_json, chomp: true).reject(&:empty?).map { |line| JSON.parse(line) }
  browser_report = JSON.parse(File.read(browser_report_path))
  abort("Admin browser QA did not pass") unless browser_report.fetch("status") == "pass"
  abort("Admin browser QA was not a full release matrix") unless browser_report.fetch("releaseAdmissible") == true
  abort("Admin browser QA route matrix is incomplete") unless browser_report.fetch("routeCount") == 28
  abort("Admin browser QA viewport matrix is incomplete") unless browser_report.fetch("viewportCount") == 3
  abort("Admin browser QA screenshot matrix is incomplete") unless browser_report.fetch("screenshotCount") == 84
  abort("Admin evidence-mode marker was not verified") unless browser_report.fetch("evidenceModeMarkerVerified") == true
  File.write(
    File.join(evidence_dir, "summary.json"),
    JSON.pretty_generate(
      {
        "status" => "pass",
        "generated_at" => Time.now.utc.iso8601,
        "mode" => "admin_pwa_evidence_mode",
        "url" => base_url,
        "build_dir" => build_dir,
        "route_count" => captures.length,
        "routes" => captures.map { |item| item.fetch("route") },
        "screenshots" => captures.map { |item| item.fetch("path") },
        "screenshot_checks" => captures.map { |item| "#{item.fetch("path")}.json" },
        "browser_qa_report" => browser_report_path,
        "browser_qa_route_count" => browser_report.fetch("routeCount"),
        "browser_qa_viewport_count" => browser_report.fetch("viewportCount"),
        "browser_qa_screenshot_count" => browser_report.fetch("screenshotCount"),
        "captures" => captures,
        "privacy" => "Evidence-mode Admin PWA uses masked deterministic test data only; no production Supabase session, service-role key, raw SMS body, OTP, PIN, or real customer phone is present."
      }
    ) + "\n"
  )
' "$EVIDENCE_DIR" "$BUILD_DIR" "$BASE_URL" "$captures_json" "$browser_qa_dir/admin_browser_qa.json"
printf '[admin-pwa-auth-render] pass evidence=%s\n' "$EVIDENCE_DIR"
