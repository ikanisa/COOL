#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

FLUTTER="${FLUTTER:-flutter}"

# Admin API credentials are HttpOnly same-origin cookies.
# Public builds consume only declared public runtime settings.
APP_PUBLIC_URL="${APP_PUBLIC_URL:-https://collect.ikanisa.com}"
ADMIN_APP_URL="${ADMIN_APP_URL:-https://platform-admin.collect.ikanisa.com}"
COLLECT_BACKEND="${COLLECT_BACKEND:-supabase}"
export APP_PUBLIC_URL ADMIN_APP_URL COLLECT_BACKEND
if [[ -n "${FLUTTER_ADMIN_WEB_BUILD_ARGS:-}" ]]; then
  echo "FLUTTER_ADMIN_WEB_BUILD_ARGS is not accepted for Admin PWA builds." >&2
  exit 1
fi
DART_DEFINES_FILE="$(mktemp)"
COLLECT_ADMIN_BUILD_METADATA="$(mktemp)"
export COLLECT_ADMIN_BUILD_METADATA
trap 'rm -f "${DART_DEFINES_FILE:-}" "${COLLECT_ADMIN_BUILD_METADATA:-}"' EXIT
BUILD_CONFIG_ARGS=(--defines-output "$DART_DEFINES_FILE" --metadata-output "$COLLECT_ADMIN_BUILD_METADATA")
if [[ "$#" -eq 1 && "${1:-}" == "--qualification" ]]; then
  BUILD_CONFIG_ARGS+=(--qualification)
elif [[ "$#" -ne 0 ]]; then
  printf 'usage: %s [--qualification]\n' "$0" >&2
  exit 2
fi
python3 scripts/supabase/admin_build_config.py "${BUILD_CONFIG_ARGS[@]}"
BUILD_ARGS=(
  --release
  --no-wasm-dry-run
  --no-web-resources-cdn
  --no-pub
  "--dart-define-from-file=$DART_DEFINES_FILE"
)

"$FLUTTER" build web -t lib/main_admin_cloudflare.dart "${BUILD_ARGS[@]}"

if [[ ! -s build/web/main.dart.js ]]; then
  echo "Admin PWA build did not produce a nonempty main.dart.js bundle." >&2
  exit 1
fi
python3 scripts/admin_cloudflare_assets.py build/web --local-engine-fallback
python3 - <<'PY_HEADERS'
from pathlib import Path
import re
headers=Path('web/_headers').read_text().replace('Referrer-Policy: strict-origin-when-cross-origin','Referrer-Policy: no-referrer')
# The shared website policy permits public services. Admin uses its same-origin
# Worker proxy for every API request and bundles its font/engine resources.
headers, count = re.subn(r"connect-src\s+[^;]+;", "connect-src 'self';", headers)
assert count == 1, 'Expected one Admin connection policy'
# Supabase serves the CAPTCHA wrapper through the Admin origin. Preserve the
# reviewed external frame source while admitting that same-origin child page.
def admin_frame_sources(match):
    sources = match.group(1).split()
    if "'self'" not in sources:
        sources.insert(0, "'self'")
    return 'frame-src ' + ' '.join(sources) + ';'
headers, count = re.subn(r"frame-src\s+([^;]+);", admin_frame_sources, headers)
assert count == 1, 'Expected one Admin frame policy'
Path('build/web/_headers').write_text(headers)
PY_HEADERS
cp web/robots.txt build/web/robots.txt

ruby -r digest -r json -r open3 <<'RUBY'
require "fileutils"
# Route the browser's conventional favicon probe to the approved Collect PNG.
# Keep this Admin-only redirect temporary and outside the offline asset inventory.
File.write("build/web/_redirects", "/favicon.ico /icons/collect-web-512.png 302\n")
# Existing assets are served before the Worker. Protect both HTML shell paths
# here as well as in the Worker's HTML fallback response.
headers_path = "build/web/_headers"
html_routes = ["/", "/index.html"]
updated_html_routes = Hash.new(0)
current_route = nil
headers = File.readlines(headers_path).map do |line|
  current_route = line.strip if line.start_with?("/")
  if html_routes.include?(current_route) && line.match?(/\A\s+Cache-Control:/i)
    updated_html_routes[current_route] += 1
    line.sub(/Cache-Control:.*$/i, "Cache-Control: no-store, no-transform")
  else
    line
  end
end.join
abort("Admin HTML shell requires one cache rule per route") unless
  html_routes.all? { |route| updated_html_routes[route] == 1 }
File.write(headers_path, headers)
source_commit, source_commit_status = Open3.capture2("git", "rev-parse", "HEAD")
source_dirty = !system("git", "diff", "--quiet", "--no-ext-diff", out: File::NULL, err: File::NULL) ||
  !system("git", "diff", "--cached", "--quiet", "--no-ext-diff", out: File::NULL, err: File::NULL)
unless source_dirty
  # A one-byte probe avoids collecting the recovered checkout's full status.
  Open3.popen3("git", "ls-files", "--others", "--exclude-standard", "-z") do |input, output, errors, wait|
    input.close
    source_dirty = !output.read(1).to_s.empty?
    Process.kill("TERM", wait.pid) if source_dirty && wait.alive?
    output.close
    errors.close
    source_dirty = true unless wait.value.success? || source_dirty
  end
end
version_path = "build/web/version.json"
version = JSON.parse(File.read(version_path))
version.update(JSON.parse(File.read(ENV.fetch("COLLECT_ADMIN_BUILD_METADATA"))))
version["source_commit"] = source_commit_status.success? ? source_commit.strip : nil
version["source_dirty"] = source_dirty
%w[COLLECT_SOURCE_MANIFEST_SHA256 COLLECT_PLATFORM_API_SOURCE_ID].each do |name|
  value = ENV[name]
  next if value.to_s.empty?
  abort("Invalid public source identity") unless value.match?(/\A[a-f0-9]{64}\z/)
  version[name == "COLLECT_SOURCE_MANIFEST_SHA256" ? "source_manifest_sha256" : "api_source_id"] = value
end
File.write(version_path, JSON.pretty_generate(version) + "\n")

manifest_path = "build/web/manifest.json"
index_path = "build/web/index.html"
service_worker_path = "build/web/custom-sw.js"
bootstrap_path = "build/web/flutter_bootstrap.js"
color_source = File.read("lib/app/theme/collect_colors.dart")
collect_color_hex = lambda do |name|
  match = color_source.match(/static const #{Regexp.escape(name)} = Color\(0xFF([0-9A-Fa-f]{6})\);/)
  abort("Collect color token #{name} not found") unless match
  "##{match[1].upcase}"
end

manifest = JSON.parse(File.read(manifest_path))
manifest["name"] = "Collect Admin"
manifest["short_name"] = "Collect Admin"
manifest["description"] = "Collect platform operations console."
manifest["display"] = "standalone"
manifest["start_url"] = "."
manifest["background_color"] = collect_color_hex.call("publicWhite")
manifest["theme_color"] = collect_color_hex.call("referenceChromeBlack")
manifest["orientation"] = "any"
manifest["icons"] = [
  {
    "src" => "icons/collect-web-512.png",
    "sizes" => "512x512",
    "type" => "image/png",
    "purpose" => "any maskable"
  }
]
File.write(manifest_path, JSON.pretty_generate(manifest) + "\n")

index = File.read(index_path)
index = index.sub(%r{<title>.*?</title>}m, "<title>Collect Admin</title>")
index = index.sub(
  %r{<meta name="description" content=".*?">}m,
  '<meta name="description" content="Collect platform operations console.">'
)
File.write(index_path, index)

cache_paths = Dir.glob("build/web/**/*", File::FNM_DOTMATCH)
  .select { |path| File.file?(path) }
  .reject do |path|
    path.split('/').any? { |part| part.start_with?('._') || part == '.DS_Store' } ||
    path.start_with?("build/web/_build/") || path.end_with?(
      ".DS_Store",
      ".last_build_id",
      "_headers",
      "_redirects",
      "index.html",
      "custom-sw.js",
      "flutter_service_worker.js"
    )
  end
  .map { |path| path.sub(%r{\Abuild/web/}, "") }
  .sort

# Keep every physical/versioned file. Optimize only the inspected non-wasm
# bootstrap: its default loader needs both full and Chromium CanvasKit pairs.
# Normalize only the two generated identity values, preserving all executable
# code/configuration. Any SDK, build, invocation or surrounding-code change
# keeps the full inventory until that bootstrap is reviewed separately.
normalized_bootstrap = File.read(bootstrap_path)
  .sub(/^var adminAssetBase = '(?:_build\/[a-f0-9]{64}\/|__COLLECT_ADMIN_ASSET_BASE__)';$/, "var adminAssetBase = '__COLLECT_ADMIN_ASSET_BASE__';")
  .sub(/^  var adminServiceWorkerVersion = '(?:collect-admin-[a-f0-9]{16}|__COLLECT_ADMIN_SW_VERSION__)';$/, "  var adminServiceWorkerVersion = '__COLLECT_ADMIN_SW_VERSION__';")
reviewed_bootstrap_sha256 = "2918e2b191d92b62219c66623bc70a9d6b03bc8881efbcc0fd3cc462c804c09f"
optional_renderer_paths = %w[
  canvaskit/canvaskit.js.symbols canvaskit/chromium/canvaskit.js.symbols
  canvaskit/experimental_webparagraph/canvaskit.js
  canvaskit/experimental_webparagraph/canvaskit.js.symbols
  canvaskit/experimental_webparagraph/canvaskit.wasm
  canvaskit/skwasm.js canvaskit/skwasm.js.symbols canvaskit/skwasm.wasm
  canvaskit/skwasm_heavy.js canvaskit/skwasm_heavy.js.symbols canvaskit/skwasm_heavy.wasm
  canvaskit/wimp.js canvaskit/wimp.js.symbols canvaskit/wimp.wasm
]
precache_paths = if Digest::SHA256.hexdigest(normalized_bootstrap) == reviewed_bootstrap_sha256
  cache_paths - optional_renderer_paths
else
  cache_paths
end

# New entrypoints and assets never use the retired immutable stable URLs.
# Keep root files as revalidating compatibility probes, not runtime references.
control_paths = %w[flutter_bootstrap.js manifest.json version.json robots.txt]
runtime_paths = cache_paths.reject { |path| control_paths.include?(path) || path.start_with?(".well-known/") }
runtime_source = runtime_paths.map do |path|
  "#{path}\0#{Digest::SHA256.file(File.join("build/web", path)).hexdigest}"
end.join("\n")
asset_base = "_build/#{Digest::SHA256.hexdigest(runtime_source)}/"
runtime_paths.each do |path|
  destination = File.join("build/web", asset_base, path)
  FileUtils.mkdir_p(File.dirname(destination))
  FileUtils.cp(File.join("build/web", path), destination)
end
cache_paths = (precache_paths - runtime_paths + (precache_paths & runtime_paths).map { |path| "#{asset_base}#{path}" }).sort
cache_urls = (["./"] + cache_paths.map { |path| "./#{path}" }).uniq
index = File.read(index_path)
index = index.gsub(%r{\n\s*<!-- Collect Admin PWA service worker -->.*?</script>}m, "")
# Normalize a previously postprocessed artifact before applying its current base.
index = index.gsub(%r{_build/[0-9a-f]{64}/}, "")
index = index.gsub('href="icons/', "href=\"#{asset_base}icons/")
index = index.gsub('url("assets/', "url(\"#{asset_base}assets/")
File.write(index_path, index)
manifest["icons"].each { |icon| icon["src"] = "#{asset_base}icons/collect-web-512.png" }
File.write(manifest_path, JSON.pretty_generate(manifest) + "\n")

bootstrap = File.read(bootstrap_path)
bootstrap = bootstrap.gsub(%r{var adminAssetBase = '[^']+';}, "var adminAssetBase = '__COLLECT_ADMIN_ASSET_BASE__';")
bootstrap = bootstrap.gsub(%r{var adminServiceWorkerVersion = '[^']+';}, "var adminServiceWorkerVersion = '__COLLECT_ADMIN_SW_VERSION__';")
abort("flutter_bootstrap.js is missing the versioned asset-base placeholder") unless bootstrap.include?("__COLLECT_ADMIN_ASSET_BASE__")
bootstrap = bootstrap.gsub("__COLLECT_ADMIN_ASSET_BASE__", asset_base)
File.write(bootstrap_path, bootstrap)

worker_template = File.read("scripts/templates/admin_pwa_service_worker.js")
%w[__COLLECT_ADMIN_CACHE_NAME__ __COLLECT_ADMIN_CACHE_URLS__ __COLLECT_ADMIN_CACHE_HASHES__].each do |marker|
  abort("Admin service worker must contain exactly one #{marker}") unless worker_template.scan(marker).length == 1
end
# The root shell is cached as ./ because hosting redirects /index.html. Its
# bytes, asset paths and worker policy must still invalidate the cache version.
version_paths = (cache_paths + ["index.html"]).uniq.sort
cache_schema_version = "natural-wait-integrity-v4"
version_source = ([cache_schema_version, Digest::SHA256.hexdigest(worker_template)] + version_paths.map do |path|
  "#{path}\0#{Digest::SHA256.file(File.join("build/web", path)).hexdigest}"
end).join("\n")
cache_name = "collect-admin-#{Digest::SHA256.hexdigest(version_source)[0, 16]}"

bootstrap = File.read(bootstrap_path)
bootstrap = bootstrap.gsub(
  %r{custom-sw\.js\?v=collect-admin-[0-9a-f]{16}},
  "custom-sw.js?v=__COLLECT_ADMIN_SW_VERSION__"
)
unless bootstrap.include?("__COLLECT_ADMIN_SW_VERSION__")
  abort("flutter_bootstrap.js is missing Collect Admin service worker placeholder")
end
bootstrap = bootstrap.gsub("__COLLECT_ADMIN_SW_VERSION__", cache_name)
unless bootstrap.include?("canvasKitBaseUrl: adminAssetBase + 'canvaskit/'") &&
       bootstrap.include?("entrypointBaseUrl: adminAssetBase") && bootstrap.include?("assetBase: adminAssetBase")
  abort("flutter_bootstrap.js must self-host CanvasKit")
end
File.write(bootstrap_path, bootstrap)

# Bind fetched bytes to the completed build, including the rendered bootstrap.
# A non-atomic publication must fail installation rather than cache a mixture.
cache_hashes = cache_urls.to_h do |url|
  path = url == "./" ? "index.html" : url.delete_prefix("./")
  [url, Digest::SHA256.file(File.join("build/web", path)).hexdigest]
end

File.write(
  service_worker_path,
  worker_template.gsub("__COLLECT_ADMIN_CACHE_NAME__", cache_name.to_json)
    .gsub("__COLLECT_ADMIN_CACHE_URLS__", JSON.pretty_generate(cache_urls))
    .gsub("__COLLECT_ADMIN_CACHE_HASHES__", JSON.pretty_generate(cache_hashes))
)

generated_service_worker = File.read(service_worker_path)
abort("custom-sw.js must not precache Cloudflare _headers metadata") if generated_service_worker.include?('"./_headers"')
abort("custom-sw.js must not precache Cloudflare _redirects metadata") if generated_service_worker.include?('"./_redirects"')
abort("custom-sw.js must not precache the redirected /index.html path") if generated_service_worker.include?('"./index.html"')
RUBY

/bin/bash "$ROOT_DIR/scripts/admin_pwa_manifest_gate.sh"
/bin/bash "$ROOT_DIR/scripts/admin_pwa_hosting_gate.sh"
