#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${ADMIN_PWA_BUILD_DIR:-$ROOT_DIR/build/web}"

ruby -r digest -r json - "$BUILD_DIR" <<'RUBY'
build_dir = ARGV.fetch(0)
failures = []

manifest_path = File.join(build_dir, "manifest.json")
index_path = File.join(build_dir, "index.html")
main_js_path = File.join(build_dir, "main.dart.js")
service_worker_path = File.join(build_dir, "custom-sw.js")
bootstrap_path = File.join(build_dir, "flutter_bootstrap.js")
official_icon_path = File.join(build_dir, "icons", "collect-web-512.png")

failures << "missing or empty build/web/main.dart.js" unless File.file?(main_js_path) && File.size?(main_js_path)
failures << "missing build/web/index.html" unless File.exist?(index_path)
failures << "missing build/web/manifest.json" unless File.exist?(manifest_path)
failures << "missing build/web/custom-sw.js" unless File.exist?(service_worker_path)
failures << "missing build/web/flutter_bootstrap.js" unless File.exist?(bootstrap_path)
failures << "missing official Collect PNG icon" unless File.exist?(official_icon_path)
if File.exist?(official_icon_path)
  expected_hash = "cae23ce3562e8aac2e248e7b22f7feed194f4fcfd2b57725ec1026f064bb0ad9"
  failures << "official Collect PNG icon hash differs from the approved platform derivative" unless Digest::SHA256.file(official_icon_path).hexdigest == expected_hash
end

manifest = {}
if File.exist?(manifest_path)
  begin
    manifest = JSON.parse(File.read(manifest_path))
  rescue JSON::ParserError => e
    failures << "manifest.json is not valid JSON: #{e.message}"
  end
end

index = File.exist?(index_path) ? File.read(index_path) : ""
service_worker = File.exist?(service_worker_path) ? File.read(service_worker_path) : ""
bootstrap = File.exist?(bootstrap_path) ? File.read(bootstrap_path) : ""
asset_base = bootstrap[/var adminAssetBase = '(_build\/[0-9a-f]{64}\/)'\s*;/, 1]
failures << "bootstrap must bind a content-versioned asset base" unless asset_base

expected = {
  "name" => "Collect Admin",
  "short_name" => "Collect Admin",
  "display" => "standalone",
  "start_url" => ".",
  "description" => "Collect platform operations console."
}
expected.each do |key, value|
  failures << "manifest #{key} must be #{value.inspect}" unless manifest[key] == value
end

icons = Array(manifest["icons"])
expected_icon = {
  "src" => "#{asset_base}icons/collect-web-512.png",
  "sizes" => "512x512",
  "type" => "image/png",
  "purpose" => "any maskable"
}
failures << "manifest must use exactly the official Collect PNG icon" unless icons == [expected_icon]

failures << "index title must identify Collect Admin" unless index.include?("<title>Collect Admin</title>")
failures << "index description must identify the admin console" unless index.include?("Collect platform operations console.")
failures << "index must use the versioned official Collect PNG favicon" unless asset_base && index.include?("<link rel=\"icon\" href=\"#{asset_base}icons/collect-web-512.png\" type=\"image/png\">")
failures << "index must load flutter_bootstrap.js" unless index.include?("flutter_bootstrap.js")
failures << "index must not register the service worker inline under strict CSP" if index.include?("navigator.serviceWorker.register")
bootstrap_registers_admin_worker =
  bootstrap.include?("var adminServiceWorkerVersion = 'collect-admin-") &&
  bootstrap.include?("navigator.serviceWorker.register('custom-sw.js', { updateViaCache: 'none' })")
failures << "flutter_bootstrap.js must register the Admin PWA service worker" unless bootstrap_registers_admin_worker
failures << "flutter_bootstrap.js must not contain an unreplaced Admin PWA service-worker placeholder" if bootstrap.include?("__COLLECT_ADMIN_SW_VERSION__")
if File.exist?(File.join(build_dir, "flutter_bootstrap.js"))
  bootstrap_invocation = bootstrap.split("_flutter.buildConfig", 2).last || bootstrap
  if bootstrap_invocation.include?("_coolServiceWorkerVersion") || bootstrap_invocation.include?("serviceWorkerUrl:") || bootstrap_invocation.include?("flutter_service_worker.js?v=")
    failures << "Flutter bootstrap must not register the Admin PWA service worker through deprecated settings"
  end
end

service_worker_required = {
  "versioned Collect Admin cache" => "CACHE_NAME",
  "app shell cache manifest" => "CACHE_URLS",
  "precache open" => "caches.open(CACHE_NAME)",
  "credential-free static precache" => "credentials: 'omit'",
  "redirect-rejecting static precache" => "redirect: 'error'",
  "same-URL static response check" => "new URL(response.url).href !== expected.href",
  "precache content binding" => "CACHE_HASHES",
  "precache SHA-256 check" => "crypto.subtle.digest('SHA-256'",
  "failed install waits for writes" => "Promise.allSettled",
  "fetch handler" => "self.addEventListener('fetch'",
  "navigation fallback" => "request.mode === 'navigate'",
  "Admin PWA shell" => "const SHELL_URL = new URL('./', self.location.href).href",
  "static cache boundary" => "ASSET_URLS.has(url.href)",
  "version-specific cache lookup" => "cache.match(key, { ignoreSearch: true })",
  "Admin PWA bootstrap" => "./flutter_bootstrap.js",
  "Admin PWA bundle" => "#{asset_base}main.dart.js",
  "Admin PWA manifest" => "./manifest.json"
}
service_worker_required.each do |label, marker|
  failures << "custom-sw.js must include #{label}" unless service_worker.include?(marker)
end
if service_worker.match?(/registration\.unregister|unregister\(\)/)
  failures << "custom-sw.js must not unregister itself"
end
failures << "custom-sw.js must retain natural update waiting" if service_worker.match?(/\bskipWaiting\s*\(/)
failures << "custom-sw.js must not claim an open operator page" if service_worker.match?(/\bclients\.claim\s*\(/)
if asset_base
  %w[entrypointBaseUrl assetBase].each do |setting|
    failures << "bootstrap must use the versioned #{setting}" unless bootstrap.include?("#{setting}: adminAssetBase")
  end
  failures << "bootstrap must use versioned CanvasKit" unless bootstrap.include?("canvasKitBaseUrl: adminAssetBase + 'canvaskit/'")
  begin
    urls = JSON.parse(service_worker[/const CACHE_URLS = (\[.*?\]);/m, 1].to_s)
    hashes = JSON.parse(service_worker[/const CACHE_HASHES = (\{.*?\});/m, 1].to_s)
    failures << "cache URL and hash inventories must match" unless urls.sort == hashes.keys.sort
    urls.each do |url|
      unless url == "./" || (url.start_with?("./") && !url.include?("..") && !url.include?("\\") && !url.include?("?"))
        failures << "cache manifest has an invalid static path"
        next
      end
      path = File.join(build_dir, url == "./" ? "index.html" : url.delete_prefix("./"))
      failures << "cache manifest bytes differ: #{url}" unless File.file?(path) && !File.symlink?(path) && Digest::SHA256.file(path).hexdigest == hashes[url]
    end
    failures << "runtime bundle must be versioned in the precache" unless urls.include?("./#{asset_base}main.dart.js") && !urls.include?("./main.dart.js")
    versioned_main = File.join(build_dir, asset_base, "main.dart.js")
    failures << "versioned runtime bundle differs from the compiled bundle" unless File.file?(versioned_main) && File.file?(main_js_path) && Digest::SHA256.file(versioned_main).hexdigest == Digest::SHA256.file(main_js_path).hexdigest
  rescue JSON::ParserError, TypeError => error
    failures << "cache manifest must contain parseable URLs and content hashes: #{error.message}"
  end
end

sensitive_matches = []
Dir.glob(File.join(build_dir, "**", "*"), File::FNM_DOTMATCH).each do |path|
  next unless File.file?(path)
  next if File.size(path) > 20 * 1024 * 1024

  text = File.binread(path)
  if text.match?(/service_role|SUPABASE_SERVICE_ROLE|OPENAI_API_KEY|WHATSAPP_TOKEN|provider-live-secret/i)
    sensitive_matches << path.sub(%r{\A#{Regexp.escape(build_dir)}/?}, "")
  end
end
failures << "generated admin web files contain sensitive marker(s): #{sensitive_matches.join(", ")}" unless sensitive_matches.empty?

if failures.empty?
  puts "[admin-pwa-gate] pass build_dir=#{build_dir}"
  exit 0
end

warn "[admin-pwa-gate][FAIL]"
failures.each { |failure| warn "  - #{failure}" }
exit 1
RUBY
