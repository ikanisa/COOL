#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

FLUTTER="${FLUTTER:-/Users/jeanbosco/Developer/flutter/bin/flutter}"

# Admin API credentials are HttpOnly same-origin Cloudflare cookies.
# Public builds do not consume Supabase keys or local dotenv secrets.
APP_PUBLIC_URL="${APP_PUBLIC_URL:-https://app-preview.collect.ikanisa.com}"
ADMIN_APP_URL="${ADMIN_APP_URL:-https://admin-preview.collect.ikanisa.com}"
export APP_PUBLIC_URL ADMIN_APP_URL
if [[ -n "${FLUTTER_ADMIN_WEB_BUILD_ARGS:-}" ]]; then
  echo "FLUTTER_ADMIN_WEB_BUILD_ARGS is not accepted for Admin PWA builds." >&2
  exit 1
fi
DART_DEFINES_FILE="$(mktemp)"
trap 'rm -f "${DART_DEFINES_FILE:-}"' EXIT
DART_DEFINES_FILE="$DART_DEFINES_FILE" ruby -r json <<'RUBY'
File.write(
  ENV.fetch("DART_DEFINES_FILE"),
  JSON.generate({
    "APP_PUBLIC_URL" => ENV.fetch("APP_PUBLIC_URL"),
    "ADMIN_APP_URL" => ENV.fetch("ADMIN_APP_URL"),
    "APP_ENVIRONMENT" => "cloudflare-preview",
    "COLLECT_BACKEND_REVISION" => "cloudflare-admin-20261005",
    "ENABLE_ADMIN_PANEL" => "true",
    "COLLECT_PUBLIC_LANDING_HOME" => "false"
  })
)
RUBY
BUILD_ARGS=(
  --release
  --no-wasm-dry-run
  --no-web-resources-cdn
  --no-pub
  "--dart-define-from-file=$DART_DEFINES_FILE"
)

"$FLUTTER" build web -t lib/main_admin_cloudflare.dart "${BUILD_ARGS[@]}"
python3 scripts/admin_cloudflare_assets.py build/web --local-engine-fallback

if [[ ! -s build/web/main.dart.js ]]; then
  echo "Admin PWA build did not produce a nonempty main.dart.js bundle." >&2
  exit 1
fi
python3 - <<'PY_HEADERS'
from pathlib import Path
headers=Path('web/_headers').read_text().replace(' https://*.supabase.co wss://*.supabase.co','').replace('Referrer-Policy: strict-origin-when-cross-origin','Referrer-Policy: no-referrer')
Path('build/web/_headers').write_text(headers)
PY_HEADERS
cp web/robots.txt build/web/robots.txt

ruby -r digest -r json -r open3 <<'RUBY'
require "fileutils"
source_commit, source_commit_status = Open3.capture2("git", "rev-parse", "HEAD")
source_changes, source_status = Open3.capture2("git", "status", "--porcelain")
version_path = "build/web/version.json"
version = JSON.parse(File.read(version_path))
version.update({
  "backend" => "cloudflare", "authentication" => "email", "notifications" => "email",
  "data_strategy" => "fresh_cloudflare", "legacy_data_import_required" => false,
  "minimum_core_schema_migration" => "0012_gateway_receiver_ingress.sql",
  "operating_actions_available" => true, "operational_migration_complete" => false
})
version["source_commit"] = source_commit_status.success? ? source_commit.strip : nil
version["source_dirty"] = !source_status.success? || !source_changes.empty?
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
cache_paths = (cache_paths - runtime_paths + runtime_paths.map { |path| "#{asset_base}#{path}" }).sort
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
