#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${ADMIN_PWA_BUILD_DIR:-$ROOT_DIR/build/web}"

ruby -r json - "$BUILD_DIR" <<'RUBY'
build_dir = ARGV.fetch(0)
failures = []

manifest_path = File.join(build_dir, "manifest.json")
index_path = File.join(build_dir, "index.html")
main_js_path = File.join(build_dir, "main.dart.js")
service_worker_path = File.join(build_dir, "custom-sw.js")
bootstrap_path = File.join(build_dir, "flutter_bootstrap.js")

failures << "missing build/web/main.dart.js" unless File.exist?(main_js_path)
failures << "missing build/web/index.html" unless File.exist?(index_path)
failures << "missing build/web/manifest.json" unless File.exist?(manifest_path)
failures << "missing build/web/custom-sw.js" unless File.exist?(service_worker_path)
failures << "missing build/web/flutter_bootstrap.js" unless File.exist?(bootstrap_path)

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
failures << "manifest icons must include at least one icon" if icons.empty?
icons.each do |icon|
  src = icon["src"].to_s
  failures << "manifest icon is missing src" if src.empty?
  next if src.empty?

  icon_path = File.expand_path(src, build_dir)
  failures << "manifest icon #{src} is missing from build/web" unless icon_path.start_with?(File.expand_path(build_dir)) && File.exist?(icon_path)
end

failures << "index title must identify Collect Admin" unless index.include?("<title>Collect Admin</title>")
failures << "index description must identify the admin console" unless index.include?("Collect platform operations console.")
failures << "index must define the Collect Admin favicon" unless index.include?('rel="icon" href="icons/collect-admin.svg"')
failures << "index must load flutter_bootstrap.js" unless index.include?("flutter_bootstrap.js")
failures << "index must not register the service worker inline under strict CSP" if index.include?("navigator.serviceWorker.register")
failures << "flutter_bootstrap.js must register the Admin PWA service worker" unless bootstrap.include?("navigator.serviceWorker.register('custom-sw.js?v=collect-admin-")
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
  "install skip waiting" => "self.skipWaiting()",
  "activate clients claim" => "self.clients.claim()",
  "fetch handler" => "self.addEventListener('fetch'",
  "navigation fallback" => "request.mode === 'navigate'",
  "Admin PWA shell" => "./index.html",
  "Admin PWA bootstrap" => "./flutter_bootstrap.js",
  "Admin PWA bundle" => "./main.dart.js",
  "Admin PWA manifest" => "./manifest.json",
  "Admin PWA icon" => "./icons/collect-admin.svg"
}
service_worker_required.each do |label, marker|
  failures << "custom-sw.js must include #{label}" unless service_worker.include?(marker)
end
if service_worker.match?(/registration\.unregister|unregister\(\)/)
  failures << "custom-sw.js must not unregister itself"
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
