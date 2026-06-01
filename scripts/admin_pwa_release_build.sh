#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

FLUTTER="${FLUTTER:-/Volumes/PRO-G40/flutter_3_44/bin/flutter}"
BUILD_ARGS="${FLUTTER_ADMIN_WEB_BUILD_ARGS:---release --no-wasm-dry-run --no-pub}"

# shellcheck disable=SC2086
"$FLUTTER" build web -t lib/main_admin.dart $BUILD_ARGS

touch build/web/main.dart.js
mkdir -p build/web/icons
cp web/icons/collect-admin.svg build/web/icons/collect-admin.svg
cp web/_headers build/web/_headers
cp web/robots.txt build/web/robots.txt

ruby -r digest -r json <<'RUBY'
manifest_path = "build/web/manifest.json"
index_path = "build/web/index.html"
service_worker_path = "build/web/custom-sw.js"
bootstrap_path = "build/web/flutter_bootstrap.js"

manifest = JSON.parse(File.read(manifest_path))
manifest["name"] = "Collect Admin"
manifest["short_name"] = "Collect Admin"
manifest["description"] = "Collect platform operations console."
manifest["display"] = "standalone"
manifest["start_url"] = "."
manifest["background_color"] = "#f7f8f6"
manifest["theme_color"] = "#101216"
manifest["orientation"] = "any"
manifest["icons"] = [
  {
    "src" => "icons/collect-admin.svg",
    "sizes" => "any",
    "type" => "image/svg+xml",
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
unless index.include?('rel="icon"')
  index = index.sub(
    %r{</head>}m,
    '  <link rel="icon" href="icons/collect-admin.svg" type="image/svg+xml">' + "\n</head>"
  )
end
File.write(index_path, index)

cache_paths = Dir.glob("build/web/**/*", File::FNM_DOTMATCH)
  .select { |path| File.file?(path) }
  .reject { |path| path.end_with?(".DS_Store", ".last_build_id", "custom-sw.js", "flutter_service_worker.js") }
  .map { |path| path.sub(%r{\Abuild/web/}, "") }
  .sort

cache_urls = (["./"] + cache_paths.map { |path| "./#{path}" }).uniq
version_paths = cache_paths.reject { |path| path == "index.html" }
version_source = version_paths.map { |path| Digest::SHA256.file(File.join("build/web", path)).hexdigest }.join("\n")
cache_name = "collect-admin-#{Digest::SHA256.hexdigest(version_source)[0, 16]}"

index = File.read(index_path)
index = index.gsub(%r{\n\s*<!-- Collect Admin PWA service worker -->.*?</script>}m, "")
File.write(index_path, index)

bootstrap = File.read(bootstrap_path)
unless bootstrap.include?("__COLLECT_ADMIN_SW_VERSION__")
  abort("flutter_bootstrap.js is missing Collect Admin service worker placeholder")
end
bootstrap = bootstrap.gsub("__COLLECT_ADMIN_SW_VERSION__", cache_name)
File.write(bootstrap_path, bootstrap)

File.write(
  service_worker_path,
  <<~JAVASCRIPT
    'use strict';

    const CACHE_NAME = #{cache_name.to_json};
    const CACHE_URLS = #{JSON.pretty_generate(cache_urls)};

    self.addEventListener('install', (event) => {
      event.waitUntil(
        caches.open(CACHE_NAME)
          .then((cache) => cache.addAll(CACHE_URLS))
          .then(() => self.skipWaiting())
      );
    });

    self.addEventListener('activate', (event) => {
      event.waitUntil(
        caches.keys()
          .then((keys) => Promise.all(
            keys
              .filter((key) => key.startsWith('collect-admin-') && key !== CACHE_NAME)
              .map((key) => caches.delete(key))
          ))
          .then(() => self.clients.claim())
      );
    });

    async function cacheFirst(request) {
      const cached = await caches.match(request, { ignoreSearch: true });
      if (cached) {
        return cached;
      }

      try {
        const response = await fetch(request);
        if (response && response.ok) {
          const cache = await caches.open(CACHE_NAME);
          await cache.put(request, response.clone());
        }
        return response;
      } catch (error) {
        if (request.mode === 'navigate') {
          const shell = await caches.match('./index.html', { ignoreSearch: true });
          if (shell) {
            return shell;
          }
        }
        throw error;
      }
    }

    self.addEventListener('fetch', (event) => {
      if (event.request.method !== 'GET') {
        return;
      }

      const url = new URL(event.request.url);
      if (url.origin !== self.location.origin) {
        return;
      }

      event.respondWith(cacheFirst(event.request));
    });
  JAVASCRIPT
)
RUBY

"$ROOT_DIR/scripts/admin_pwa_manifest_gate.sh"
"$ROOT_DIR/scripts/admin_pwa_hosting_gate.sh"
