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
ROUTE_TIMEOUT_MS="${MOBILE_ROUTE_RENDER_ROUTE_TIMEOUT_MS:-90000}"
PROCESS_TIMEOUT_MS="${MOBILE_ROUTE_RENDER_PROCESS_TIMEOUT_MS:-900000}"

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
  "root-redirect|/|entry"
  "auth|/auth|workflow"
  "profile|/settings/profile|workflow"
  "home|/home|primary"
  "offline|/offline|utility"
  "sync|/sync|utility"
  "groups|/groups|primary"
  "group-create|/groups/create|workflow"
  "group-scan|/groups/scan|workflow"
  "group-detail|/groups/col-church|workflow"
  "share|/groups/col-church/share|workflow"
  "invite|/groups/col-church/invite|compatibility"
  "shared-group-link|/c/st-michel-building-fund|entry"
  "app-share-entry|/app|compatibility"
  "app-invite-link|/invite/038491|compatibility"
  "share-invalid|/share/invalid|utility"
  "share-expired|/share/expired|utility"
  "share-expired-request|/share/expired/request|utility"
  "contribution|/groups/col-church/contribute|workflow"
  "ledger|/groups/col-church/ledger|workflow"
  "manage|/groups/col-church/manage|workflow"
  "group-profile|/groups/col-church/profile|workflow"
  "members|/groups/col-church/members|workflow"
  "settings|/settings|primary"
  "account|/settings/account|utility"
  "account-delete|/settings/account/delete|utility"
  "privacy-alias|/settings/privacy|utility"
  "help|/settings/help|utility"
  "legal-privacy|/settings/legal/privacy|utility"
  "legal-terms|/settings/legal/terms|utility"
)

if [[ -n "${MOBILE_ROUTE_RENDER_ROUTE_FILTER:-}" ]]; then
  IFS=',' read -r -a route_filter_names <<<"$MOBILE_ROUTE_RENDER_ROUTE_FILTER"
  filtered_route_specs=()
  for spec in "${route_specs[@]}"; do
    IFS='|' read -r name _route _route_class <<<"$spec"
    for filter_name in "${route_filter_names[@]}"; do
      if [[ "$name" == "$filter_name" ]]; then
        filtered_route_specs+=("$spec")
        break
      fi
    done
  done
  route_specs=("${filtered_route_specs[@]}")
  [[ "${#route_specs[@]}" -gt 0 ]] || fail "MOBILE_ROUTE_RENDER_ROUTE_FILTER did not match any route specs."
fi

captures_json="$EVIDENCE_DIR/captures.jsonl"
: >"$captures_json"

routes_json="$(ruby -r json -e 'puts JSON.generate(ARGV.map { |spec| name, route, route_class = spec.split("|", 3); route_class ||= "workflow"; { "name" => name, "route" => route, "route_class" => route_class, "product_screen" => route_class != "compatibility" } })' "${route_specs[@]}")"
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
      --route-timeout-ms "$ROUTE_TIMEOUT_MS" \
      --process-timeout-ms "$PROCESS_TIMEOUT_MS" \
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
        --command-timeout-ms "$COMMAND_TIMEOUT_MS" \
        --process-timeout-ms "$PROCESS_TIMEOUT_MS" >>"$stdout_log" 2>>"$stderr_log"
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
  IFS='|' read -r name route route_class <<<"$spec"
  capture_route "$name" "$route"
done

ruby -r json -r time -e '
  evidence_dir, build_dir, base_url, viewport, captures_json, routes_json = ARGV
  route_specs = JSON.parse(routes_json)
  metadata_by_name = route_specs.to_h { |item| [item.fetch("name"), item] }
  captures = File.readlines(captures_json, chomp: true).reject(&:empty?).map do |line|
    capture = JSON.parse(line)
    metadata = metadata_by_name.fetch(capture.fetch("name"), {})
    capture.merge(
      "route_class" => metadata.fetch("route_class", "workflow"),
      "product_screen" => metadata.fetch("product_screen", true)
    )
  end
  product_screens = route_specs.select { |item| item.fetch("product_screen") }
  compatibility_routes = route_specs.reject { |item| item.fetch("product_screen") }
  summary = {
    "status" => "pass",
    "generated_at" => Time.now.utc.iso8601,
    "url" => base_url,
    "build_dir" => build_dir,
    "viewport" => viewport,
    "route_count" => captures.length,
    "product_screen_count" => product_screens.length,
    "compatibility_route_count" => compatibility_routes.length,
    "routes" => captures.map { |item| item.fetch("route") },
    "route_specs" => route_specs,
    "product_screens" => product_screens.map { |item| item.fetch("name") },
    "compatibility_routes" => compatibility_routes.map { |item| item.fetch("name") },
    "screenshots" => captures.map { |item| item.fetch("path") },
    "screenshot_checks" => captures.map { |item| "#{item.fetch("path")}.json" },
    "captures" => captures,
    "secret_handling" => "Screenshots must not include secrets, raw SMS bodies, provider tokens, service-role keys, or production customer data."
  }
  File.write(File.join(evidence_dir, "summary.json"), JSON.pretty_generate(summary) + "\n")
' "$EVIDENCE_DIR" "$BUILD_DIR" "$BASE_URL" "$VIEWPORT" "$captures_json" "$routes_json"

printf '[mobile-route-render] pass evidence=%s\n' "$EVIDENCE_DIR"
