#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${ADMIN_PWA_BUILD_DIR:-$ROOT_DIR/build/web}"
EVIDENCE_DIR="${ADMIN_PWA_RENDER_EVIDENCE_DIR:-$ROOT_DIR/.cache/admin_pwa_render_smoke/$(date -u +%Y%m%dT%H%M%SZ)}"
HOST="${ADMIN_PWA_RENDER_HOST:-127.0.0.1}"
PORT="${ADMIN_PWA_RENDER_PORT:-}"

mkdir -p "$EVIDENCE_DIR"

fail() {
  printf '[admin-pwa-render][FAIL] %s\n' "$*" >&2
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
      printf '[admin-pwa-render][FAIL] HTTP server exited before %s was ready.\n' "$url" >&2
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

if [[ ! -d "$BUILD_DIR" ]]; then
  fail "Admin PWA build directory is missing: $BUILD_DIR"
fi

CHROME="$(find_chrome || true)"
if [[ -z "$CHROME" || ! -x "$CHROME" ]]; then
  fail "Chrome/Chromium is required for Admin PWA rendered smoke."
fi

if [[ -z "$PORT" ]]; then
  PORT="$(ruby -rsocket -e 'server = TCPServer.new("127.0.0.1", 0); puts server.addr[1]; server.close')"
fi

python3 -m http.server "$PORT" --bind "$HOST" --directory "$BUILD_DIR" >"$EVIDENCE_DIR/http.log" 2>&1 &
SERVER_PID=$!
trap 'kill "$SERVER_PID" 2>/dev/null || true' EXIT

BASE_URL="http://$HOST:$PORT"

wait_for_http "$BASE_URL/" 60 || fail "HTTP server did not become ready at $BASE_URL/."

curl -fsSI "$BASE_URL/" >"$EVIDENCE_DIR/index.headers" || fail "index.html did not serve over HTTP."
curl -fsSI "$BASE_URL/main.dart.js" >"$EVIDENCE_DIR/main.headers" || fail "main.dart.js did not serve over HTTP."
curl -fsSI "$BASE_URL/custom-sw.js" >"$EVIDENCE_DIR/custom-sw.headers" || fail "custom-sw.js did not serve over HTTP."
curl -fsS "$BASE_URL/manifest.json" >"$EVIDENCE_DIR/manifest.json" || fail "manifest.json did not serve over HTTP."

ADMIN_PWA_CHROME="$CHROME" "$ROOT_DIR/scripts/admin_pwa_runtime_smoke.mjs" "$BASE_URL/" "$EVIDENCE_DIR"

capture() {
  local name="$1"
  local size="$2"
  local png="$EVIDENCE_DIR/${name}.png"
  local profile="$EVIDENCE_DIR/${name}-profile"
  rm -rf "$profile"
  mkdir -p "$profile"

  "$CHROME" \
    --headless \
    --force-device-scale-factor=1 \
    --disable-gpu \
    --disable-background-networking \
    --disable-component-update \
    --disable-sync \
    --disable-dev-shm-usage \
    --no-first-run \
    --no-default-browser-check \
    --user-data-dir="$profile" \
    --window-size="$size" \
    --run-all-compositor-stages-before-draw \
    --virtual-time-budget=8000 \
    --screenshot="$png" \
    "$BASE_URL/" >"$EVIDENCE_DIR/${name}.stdout" 2>"$EVIDENCE_DIR/${name}.stderr" &
  local chrome_pid=$!

  for _ in {1..18}; do
    if [[ -s "$png" ]]; then
      break
    fi
    if ! kill -0 "$chrome_pid" 2>/dev/null; then
      break
    fi
    sleep 1
  done

  if kill -0 "$chrome_pid" 2>/dev/null; then
    kill "$chrome_pid" 2>/dev/null || true
  fi
  wait "$chrome_pid" 2>/dev/null || true

  [[ -s "$png" ]] || fail "$name screenshot was not created."

  ruby -r json -r set -r zlib - "$png" "$size" <<'RUBY'
path, expected_size = ARGV
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
channels = { 0 => 1, 2 => 3, 6 => 4 }.fetch(color_type) do
  abort("unsupported PNG color type #{color_type}")
end
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
    when 0
      [parts[0], parts[0], parts[0], 255]
    when 2
      [parts[0], parts[1], parts[2], 255]
    when 6
      [parts[0], parts[1], parts[2], parts[3]]
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

File.write(
  "#{path}.json",
  JSON.pretty_generate(
    {
      status: "pass",
      path: File.basename(path),
      width: width,
      height: height,
      bytes: size,
      sampled_pixels: sampled_pixels,
      distinct_rgb: distinct_rgb.length,
      non_background_pixels: non_background_pixels
    }
  ) + "\n"
)
RUBY
}

capture "desktop-1440x900" "1440x900"
capture "mobile-390x844" "390x844"

cat >"$EVIDENCE_DIR/summary.json" <<JSON
{
  "status": "pass",
  "url": "$BASE_URL/",
  "build_dir": "$BUILD_DIR",
  "screenshots": [
    "desktop-1440x900.png",
    "mobile-390x844.png"
  ],
  "screenshot_checks": [
    "desktop-1440x900.png.json",
    "mobile-390x844.png.json"
  ],
  "checked_assets": [
    "index.html",
    "main.dart.js",
    "manifest.json",
    "custom-sw.js"
  ],
  "runtime_evidence": "pwa-runtime.json"
}
JSON

printf '[admin-pwa-render] pass evidence=%s\n' "$EVIDENCE_DIR"
