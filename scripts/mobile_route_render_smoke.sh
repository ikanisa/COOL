#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

FLUTTER="${FLUTTER:-/Volumes/PRO-G40/flutter_3_44/bin/flutter}"
NODE="${NODE:-node}"
BUILD_DIR="${MOBILE_ROUTE_RENDER_BUILD_DIR:-$ROOT_DIR/build/mobile_route_render_web}"
EVIDENCE_DIR="${MOBILE_ROUTE_RENDER_EVIDENCE_DIR:-$ROOT_DIR/.cache/mobile_route_render_smoke/$(date -u +%Y%m%dT%H%M%SZ)}"
HOST="${MOBILE_ROUTE_RENDER_HOST:-127.0.0.1}"
PORT="${MOBILE_ROUTE_RENDER_PORT:-}"
BUILD_ARGS="${MOBILE_ROUTE_RENDER_BUILD_ARGS:---release --no-wasm-dry-run --no-pub --dart-define=COLLECT_MOBILE_EVIDENCE_MODE=true}"
VIEWPORT="${MOBILE_ROUTE_RENDER_VIEWPORT:-390x844}"
RENDER_WAIT_MS="${MOBILE_ROUTE_RENDER_WAIT_MS:-15000}"
DEVTOOLS_READY_MS="${MOBILE_ROUTE_RENDER_DEVTOOLS_READY_MS:-120000}"
COMMAND_TIMEOUT_MS="${MOBILE_ROUTE_RENDER_COMMAND_TIMEOUT_MS:-60000}"

mkdir -p "$EVIDENCE_DIR"

fail() {
  printf '[mobile-route-render][FAIL] %s\n' "$*" >&2
  exit 1
}

wait_for_http() {
  local url="$1"
  local attempts="$2"
  for _ in $(seq 1 "$attempts"); do
    if curl -fsS "$url" >/dev/null 2>&1; then
      return 0
    fi
    if ! kill -0 "$SERVER_PID" 2>/dev/null; then
      printf '[mobile-route-render][FAIL] HTTP server exited before %s was ready.\n' "$url" >&2
      if [[ -s "$EVIDENCE_DIR/http.log" ]]; then
        sed -n '1,120p' "$EVIDENCE_DIR/http.log" >&2
      fi
      exit 1
    fi
    sleep 0.5
  done
  return 1
}

find_chrome() {
  if [[ -n "${MOBILE_ROUTE_RENDER_CHROME:-}" ]]; then
    printf '%s\n' "$MOBILE_ROUTE_RENDER_CHROME"
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

  while IFS= read -r candidate; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done < <(
    find "$HOME/Library/Caches/ms-playwright" "$HOME/.cache/ms-playwright" \
      -type f \( \
        -path '*/chrome-mac*/*/Contents/MacOS/*' \
        -o -name chrome \
        -o -name chrome-headless-shell \
        -o -name headless_shell \
      \) \
      2>/dev/null | sort -r
  )

  for candidate in google-chrome chromium chromium-browser; do
    if command -v "$candidate" >/dev/null 2>&1; then
      command -v "$candidate"
      return 0
    fi
  done
}

CHROME="$(find_chrome || true)"
if [[ -z "$CHROME" || ! -x "$CHROME" ]]; then
  fail "Chrome/Chromium is required for mobile route render smoke."
fi
if ! command -v "$NODE" >/dev/null 2>&1; then
  fail "Node.js is required for mobile route render smoke viewport capture."
fi

rm -rf "$BUILD_DIR"
# shellcheck disable=SC2086
"$FLUTTER" build web -t lib/main.dart --output="$BUILD_DIR" $BUILD_ARGS >"$EVIDENCE_DIR/flutter_build.log" 2>&1

if [[ -z "$PORT" ]]; then
  PORT="$(ruby -rsocket -e 'server = TCPServer.new("127.0.0.1", 0); puts server.addr[1]; server.close')"
fi

"$NODE" "$ROOT_DIR/scripts/static_file_server.mjs" --host "$HOST" --port "$PORT" --dir "$BUILD_DIR" >"$EVIDENCE_DIR/http.log" 2>&1 &
SERVER_PID=$!
cleanup() {
  pkill -P "$SERVER_PID" 2>/dev/null || true
  kill "$SERVER_PID" 2>/dev/null || true
  wait "$SERVER_PID" 2>/dev/null || true
}
trap cleanup EXIT

BASE_URL="http://$HOST:$PORT"

wait_for_http "$BASE_URL/" 120 || fail "HTTP server did not become ready at $BASE_URL/."

curl -fsSI "$BASE_URL/" >"$EVIDENCE_DIR/index.headers" || fail "index.html did not serve over HTTP."
curl -fsSI "$BASE_URL/main.dart.js" >"$EVIDENCE_DIR/main.headers" || fail "main.dart.js did not serve over HTTP."

route_specs=(
  "root-redirect|/"
  "onboarding|/onboarding"
  "onboarding-legal|/onboarding/legal"
  "auth|/auth"
  "auth-success|/auth/success"
  "auth-failure|/auth/failure"
  "profile|/settings/profile"
  "sms-permission-redirect|/permissions/sms"
  "sms-denied|/permissions/sms-denied"
  "device-permission|/permissions/device"
  "notifications-denied|/permissions/notifications-denied"
  "camera-denied|/permissions/camera-denied"
  "home|/home"
  "groups|/groups"
  "groups-search|/groups/search"
  "join|/groups/join"
  "group-create|/groups/create"
  "group-scan|/groups/scan"
  "iphone-create-unavailable|/platform/iphone-create-unavailable"
  "group-detail|/groups/col-church"
  "group-created|/groups/col-church/created"
  "group-joined|/groups/col-church/joined"
  "owner-redirect|/groups/col-church/owner"
  "owner-sms-health-redirect|/groups/col-church/owner/sms-health"
  "owner-receiver-redirect|/groups/col-church/owner/receiver"
  "share|/groups/col-church/share"
  "invite|/groups/col-church/invite"
  "shared-group-link|/c/st-michel-building-fund"
  "share-invalid|/share/invalid"
  "share-expired|/share/expired"
  "share-expired-request|/share/expired/request"
  "share-confirmed-redirect|/share/confirmed"
  "app-share-entry|/app"
  "app-invite-link|/invite/038491"
  "contribution|/groups/col-church/contribute"
  "payment-handoff-redirect|/groups/col-church/pay/intent-render/handoff"
  "payment-intent|/groups/col-church/pay/intent-render"
  "payment-pending|/groups/col-church/pay/intent-render/state/pending"
  "payment-confirmed|/groups/col-church/pay/intent-render/state/confirmed"
  "payment-expired|/groups/col-church/pay/intent-render/state/expired"
  "payment-needs-review|/groups/col-church/pay/intent-render/state/needs-review"
  "payment-support-review|/groups/col-church/support/payment/intent-render"
  "ledger|/groups/col-church/ledger"
  "manage|/groups/col-church/manage"
  "group-profile|/groups/col-church/profile"
  "members|/groups/col-church/members"
  "settings|/settings"
  "account|/settings/account"
  "account-delete|/settings/account/delete"
  "privacy|/settings/privacy"
  "legal-privacy|/settings/legal/privacy"
  "legal-terms|/settings/legal/terms"
  "help|/settings/help"
  "notifications|/notifications"
  "offline|/offline"
  "sync|/sync"
)

captures_json="$EVIDENCE_DIR/captures.jsonl"
: >"$captures_json"

routes_json="$(ruby -r json -e 'puts JSON.generate(ARGV.map { |spec| name, route = spec.split("|", 2); { "name" => name, "route" => route } })' "${route_specs[@]}")"
matrix_capture_status=1
if [[ "${MOBILE_ROUTE_MATRIX_CAPTURE:-0}" == "1" ]]; then
  for attempt in 1 2 3; do
    rm -rf "$EVIDENCE_DIR/chrome-profile"
    printf '[route-matrix attempt %s]\n' "$attempt" >>"$EVIDENCE_DIR/capture.stdout"
    printf '[route-matrix attempt %s]\n' "$attempt" >>"$EVIDENCE_DIR/capture.stderr"
    set +e
    "$NODE" "$ROOT_DIR/scripts/chrome_cdp_route_matrix.mjs" \
      --chrome "$CHROME" \
      --base-url "$BASE_URL" \
      --output-dir "$EVIDENCE_DIR" \
      --profile "$EVIDENCE_DIR/chrome-profile" \
      --viewport "$VIEWPORT" \
      --wait-ms "$RENDER_WAIT_MS" \
      --devtools-ready-ms "$DEVTOOLS_READY_MS" \
      --command-timeout-ms "$COMMAND_TIMEOUT_MS" \
      --routes-json "$routes_json" >>"$EVIDENCE_DIR/capture.stdout" 2>>"$EVIDENCE_DIR/capture.stderr"
    matrix_capture_status=$?
    set -e
    [[ "$matrix_capture_status" -eq 0 ]] && break
    sleep "$attempt"
  done
  if [[ "$matrix_capture_status" -ne 0 ]]; then
    printf '[mobile-route-render] route matrix capture failed; falling back to per-route capture. See %s\n' "$EVIDENCE_DIR/capture.stderr" >&2
  fi
else
  printf '[mobile-route-render] route matrix capture skipped; using isolated per-route capture. Set MOBILE_ROUTE_MATRIX_CAPTURE=1 to opt in.\n' >>"$EVIDENCE_DIR/capture.stdout"
fi

capture_route() {
  local name="$1"
  local route="$2"
  local url="$BASE_URL/#$route"
  local png="$EVIDENCE_DIR/${name}-${VIEWPORT}.png"

  if [[ ! -s "$png" ]]; then
    local profile="$EVIDENCE_DIR/${name}-profile"
    local stdout_log="$EVIDENCE_DIR/${name}.stdout"
    local stderr_log="$EVIDENCE_DIR/${name}.stderr"

    : >"$stdout_log"
    : >"$stderr_log"
    local route_capture_status=1
    for attempt in 1 2 3 4; do
      rm -rf "$profile"
      mkdir -p "$profile"
      rm -f "$png"

      printf '[attempt %s]\n' "$attempt" >>"$stdout_log"
      printf '[attempt %s]\n' "$attempt" >>"$stderr_log"
      set +e
      "$NODE" "$ROOT_DIR/scripts/chrome_cdp_screenshot.mjs" \
        --chrome "$CHROME" \
        --url "$url" \
        --output "$png" \
        --profile "$profile" \
        --viewport "$VIEWPORT" \
        --wait-ms "$RENDER_WAIT_MS" \
        --devtools-ready-ms "$DEVTOOLS_READY_MS" \
        --command-timeout-ms "$COMMAND_TIMEOUT_MS" >>"$stdout_log" 2>>"$stderr_log"
      route_capture_status=$?
      set -e
      if [[ "$route_capture_status" -eq 0 && -s "$png" ]]; then
        local png_bytes
        png_bytes="$(wc -c <"$png" | tr -d ' ')"
        if [[ "$png_bytes" -gt 8000 ]]; then
          break
        fi
        printf 'screenshot too small on attempt %s: %s bytes\n' "$attempt" "$png_bytes" >>"$stderr_log"
        route_capture_status=1
      fi
      sleep "$attempt"
    done

    if [[ "$route_capture_status" -ne 0 ]]; then
      fail "$name screenshot capture failed after retries. See $stderr_log"
    fi
  fi

  [[ -s "$png" ]] || fail "$name screenshot was not created."

  "$NODE" "$ROOT_DIR/scripts/png_capture_check.mjs" "$png" "$VIEWPORT" "$name" "$route" "$url" "$captures_json"
}

for spec in "${route_specs[@]}"; do
  IFS='|' read -r name route <<<"$spec"
  capture_route "$name" "$route"
done

ruby -r json -r time -e '
  evidence_dir, build_dir, base_url, viewport, captures_json = ARGV
  captures = File.readlines(captures_json, chomp: true).reject(&:empty?).map { |line| JSON.parse(line) }
  summary = {
    "status" => "pass",
    "generated_at" => Time.now.utc.iso8601,
    "url" => base_url,
    "build_dir" => build_dir,
    "viewport" => viewport,
    "route_count" => captures.length,
    "routes" => captures.map { |item| item.fetch("route") },
    "screenshots" => captures.map { |item| item.fetch("path") },
    "screenshot_checks" => captures.map { |item| "#{item.fetch("path")}.json" },
    "captures" => captures,
    "secret_handling" => "Screenshots must not include secrets, raw SMS bodies, provider tokens, service-role keys, or production customer data."
  }
  File.write(File.join(evidence_dir, "summary.json"), JSON.pretty_generate(summary) + "\n")
' "$EVIDENCE_DIR" "$BUILD_DIR" "$BASE_URL" "$VIEWPORT" "$captures_json"

printf '[mobile-route-render] pass evidence=%s\n' "$EVIDENCE_DIR"
