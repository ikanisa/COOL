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

mkdir -p "$EVIDENCE_DIR"

fail() {
  printf '[mobile-route-render][FAIL] %s\n' "$*" >&2
  exit 1
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

python3 -m http.server "$PORT" --bind "$HOST" --directory "$BUILD_DIR" >"$EVIDENCE_DIR/http.log" 2>&1 &
SERVER_PID=$!
trap 'kill "$SERVER_PID" 2>/dev/null || true' EXIT

BASE_URL="http://$HOST:$PORT"

for _ in {1..40}; do
  if curl -fsS "$BASE_URL/" >/dev/null 2>&1; then
    break
  fi
  sleep 0.25
done

curl -fsSI "$BASE_URL/" >"$EVIDENCE_DIR/index.headers" || fail "index.html did not serve over HTTP."
curl -fsSI "$BASE_URL/main.dart.js" >"$EVIDENCE_DIR/main.headers" || fail "main.dart.js did not serve over HTTP."

route_specs=(
  "onboarding|/onboarding"
  "auth|/auth"
  "profile|/settings/profile"
  "home|/home"
  "groups|/groups"
  "group-detail|/groups/col-church"
  "join|/groups/join"
  "share|/groups/col-church/share"
  "contribution|/groups/col-church/contribute"
  "payment-handoff|/groups/col-church/pay/intent-render/handoff"
  "payment-waiting|/groups/col-church/pay/intent-render/waiting"
  "payment-confirmed|/groups/col-church/pay/intent-render/state/confirmed"
  "ledger|/groups/col-church/ledger"
  "owner|/groups/col-church/owner"
  "members|/groups/col-church/members"
  "settings|/settings"
  "privacy|/settings/privacy"
  "help|/settings/help"
  "notifications|/notifications"
  "offline|/offline"
  "sync|/sync"
)

captures_json="$EVIDENCE_DIR/captures.jsonl"
: >"$captures_json"

capture_route() {
  local name="$1"
  local route="$2"
  local url="$BASE_URL/#$route"
  local png="$EVIDENCE_DIR/${name}-${VIEWPORT}.png"
  local profile="$EVIDENCE_DIR/${name}-profile"

  rm -rf "$profile"
  mkdir -p "$profile"

  "$NODE" "$ROOT_DIR/scripts/chrome_cdp_screenshot.mjs" \
    --chrome "$CHROME" \
    --url "$url" \
    --output "$png" \
    --profile "$profile" \
    --viewport "$VIEWPORT" \
    --wait-ms 9000 >"$EVIDENCE_DIR/${name}.stdout" 2>"$EVIDENCE_DIR/${name}.stderr"

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
pixels = []
read_offset = 0
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
  pixels.concat(row.each_slice(channels).map do |parts|
    case color_type
    when 0 then [parts[0], parts[0], parts[0], 255]
    when 2 then [parts[0], parts[1], parts[2], 255]
    when 6 then [parts[0], parts[1], parts[2], parts[3]]
    end
  end)
  previous = row
end

sample_target = 20_000
stride = [pixels.length / sample_target, 1].max
distinct_rgb = Set.new
non_background_pixels = 0
sampled_pixels = 0
pixels.each_with_index do |(r, g, b, a), index|
  next unless (index % stride).zero?
  sampled_pixels += 1
  distinct_rgb << [r, g, b]
  non_background_pixels += 1 if a.positive? && !(r > 245 && g > 245 && b > 245)
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
