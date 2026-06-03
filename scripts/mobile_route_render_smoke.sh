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
BUILD_ARGS="${MOBILE_ROUTE_RENDER_BUILD_ARGS:---release --no-wasm-dry-run --no-pub}"
VIEWPORT="${MOBILE_ROUTE_RENDER_VIEWPORT:-390x844}"
RENDER_WAIT_MS="${MOBILE_ROUTE_RENDER_WAIT_MS:-4500}"

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
trap 'kill "$SERVER_PID" 2>/dev/null || true' EXIT

BASE_URL="http://$HOST:$PORT"

wait_for_http "$BASE_URL/" 120 || fail "HTTP server did not become ready at $BASE_URL/."

curl -fsSI "$BASE_URL/" >"$EVIDENCE_DIR/index.headers" || fail "index.html did not serve over HTTP."
curl -fsSI "$BASE_URL/main.dart.js" >"$EVIDENCE_DIR/main.headers" || fail "main.dart.js did not serve over HTTP."

route_specs=(
  "onboarding|/onboarding"
  "auth|/auth"
  "auth-success|/auth/success"
  "auth-failure|/auth/failure"
  "profile|/settings/profile"
  "profile-readiness|/settings/readiness"
  "sms-permission|/permissions/sms"
  "sms-denied|/permissions/sms-denied"
  "device-permission|/permissions/device"
  "home|/home"
  "groups|/groups"
  "group-create|/groups/create"
  "iphone-create-unavailable|/platform/iphone-create-unavailable"
  "group-detail|/groups/col-church"
  "group-created|/groups/col-church/created"
  "group-joined|/groups/col-church/joined"
  "join|/groups/join"
  "share|/groups/col-church/share"
  "invite|/groups/col-church/invite"
  "share-confirmed|/share/confirmed?message=Link%20copied"
  "share-invalid|/share/invalid"
  "share-expired|/share/expired"
  "contribution|/groups/col-church/contribute"
  "payment-waiting|/groups/col-church/pay/intent-render/waiting"
  "payment-pending|/groups/col-church/pay/intent-render/state/pending"
  "payment-confirmed|/groups/col-church/pay/intent-render/state/confirmed"
  "payment-expired|/groups/col-church/pay/intent-render/state/expired"
  "payment-needs-review|/groups/col-church/pay/intent-render/state/needs-review"
  "ledger|/groups/col-church/ledger"
  "owner|/groups/col-church/owner"
  "owner-sms-health|/groups/col-church/owner/sms-health"
  "owner-receiver|/groups/col-church/owner/receiver"
  "manage|/groups/col-church/manage"
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
    --routes-json "$routes_json" >>"$EVIDENCE_DIR/capture.stdout" 2>>"$EVIDENCE_DIR/capture.stderr"
  matrix_capture_status=$?
  set -e
  [[ "$matrix_capture_status" -eq 0 ]] && break
  sleep "$attempt"
done
if [[ "$matrix_capture_status" -ne 0 ]]; then
  printf '[mobile-route-render] route matrix capture failed; falling back to per-route capture. See %s\n' "$EVIDENCE_DIR/capture.stderr" >&2
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
        --wait-ms "$RENDER_WAIT_MS" >>"$stdout_log" 2>>"$stderr_log"
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

  ruby -r json -r set -r zlib - "$png" "$VIEWPORT" "$name" "$route" "$url" "$captures_json" <<'RUBY'
path, expected_size, name, route, url, captures_json = ARGV
expected_width, expected_height = expected_size.split("x").map(&:to_i)
data = File.binread(path)
abort("not a PNG: #{path}") unless data.start_with?("\x89PNG\r\n\x1a\n".b)
offset = 8
idat = +"".b
width = height = bit_depth = color_type = interlace = nil
while offset < data.bytesize
  length = data[offset, 4].unpack1("N")
  type = data[offset + 4, 4]
  chunk = data[offset + 8, length]
  offset += 12 + length
  case type
  when "IHDR"
    width = chunk[0, 4].unpack1("N")
    height = chunk[4, 4].unpack1("N")
    bit_depth = chunk.getbyte(8)
    color_type = chunk.getbyte(9)
    interlace = chunk.getbyte(12)
  when "IDAT"
    idat << chunk
  when "IEND"
    break
  end
end
size = File.size(path)
abort("unexpected PNG dimensions #{width}x#{height}, expected #{expected_width}x#{expected_height}") unless width == expected_width && height == expected_height
abort("screenshot too small to prove render: #{size} bytes") unless size > 8_000
abort("unsupported PNG bit depth #{bit_depth}") unless bit_depth == 8
abort("interlaced PNG screenshots are not supported") unless interlace == 0
channels = {0 => 1, 2 => 3, 6 => 4}.fetch(color_type) { abort("unsupported PNG color type #{color_type}") }
bpp = channels
row_bytes = width * channels
inflated = Zlib::Inflate.inflate(idat)

def paeth(a, b, c)
  p = a + b - c
  pa = (p - a).abs
  pb = (p - b).abs
  pc = (p - c).abs
  return a if pa <= pb && pa <= pc
  return b if pb <= pc
  c
end

previous = Array.new(row_bytes, 0)
read_offset = 0
sample_target = 20_000
total_pixels = width * height
stride = [total_pixels / sample_target, 1].max
distinct_rgb = Set.new
non_background_pixels = 0
sampled_pixels = 0
pixel_index = 0
height.times do
  filter = inflated.getbyte(read_offset)
  read_offset += 1
  raw = inflated.byteslice(read_offset, row_bytes).bytes
  read_offset += row_bytes
  row = Array.new(row_bytes, 0)
  row_bytes.times do |i|
    left = i >= bpp ? row[i - bpp] : 0
    up = previous[i]
    upper_left = i >= bpp ? previous[i - bpp] : 0
    predictor = case filter
    when 0 then 0
    when 1 then left
    when 2 then up
    when 3 then (left + up) / 2
    when 4 then paeth(left, up, upper_left)
    else abort("unsupported PNG filter #{filter}")
    end
    row[i] = (raw[i] + predictor) & 0xff
  end

  row.each_slice(channels) do |parts|
    if (pixel_index % stride).zero?
      r, g, b, a = case color_type
      when 0 then [parts[0], parts[0], parts[0], 255]
      when 2 then [parts[0], parts[1], parts[2], 255]
      when 6 then [parts[0], parts[1], parts[2], parts[3]]
      end
      sampled_pixels += 1
      distinct_rgb << [r, g, b]
      non_background_pixels += 1 if a.positive? && !(r > 245 && g > 245 && b > 245)
    end
    pixel_index += 1
  end
  previous = row
end

abort("screenshot appears blank: #{distinct_rgb.length} distinct sampled colors") unless distinct_rgb.length >= 8
abort("screenshot lacks visible foreground pixels: #{non_background_pixels}") unless non_background_pixels >= 100

result = {
  "status" => "pass",
  "name" => name,
  "route" => route,
  "url" => url,
  "path" => File.basename(path),
  "width" => width,
  "height" => height,
  "bytes" => size,
  "sampled_pixels" => sampled_pixels,
  "distinct_rgb" => distinct_rgb.length,
  "non_background_pixels" => non_background_pixels
}
File.write("#{path}.json", JSON.pretty_generate(result) + "\n")
File.open(captures_json, "a") { |file| file.puts(JSON.generate(result)) }
RUBY
}

for spec in "${route_specs[@]}"; do
  IFS='|' read -r name route <<<"$spec"
  capture_route "$name" "$route"
done

ruby -r json -r time - "$EVIDENCE_DIR" "$BUILD_DIR" "$BASE_URL" "$VIEWPORT" "$captures_json" <<'RUBY'
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
RUBY

printf '[mobile-route-render] pass evidence=%s\n' "$EVIDENCE_DIR"
