#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

FLUTTER="${FLUTTER:-/Volumes/PRO-G40/flutter_3_44/bin/flutter}"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  . ./.env
  set +a
fi

SUPABASE_PUBLIC_URL="${SUPABASE_PRODUCTION_URL:-${SUPABASE_URL:-}}"
SUPABASE_PUBLIC_ANON_KEY="${SUPABASE_PRODUCTION_ANON_KEY:-${SUPABASE_ANON_KEY:-}}"
APP_PUBLIC_URL="${APP_PUBLIC_URL:-https://collect.ikanisa.com}"
ADMIN_APP_URL="${ADMIN_APP_URL:-https://admin.collect.ikanisa.com}"
export SUPABASE_PUBLIC_URL SUPABASE_PUBLIC_ANON_KEY APP_PUBLIC_URL ADMIN_APP_URL

if [[ -z "${FLUTTER_ADMIN_WEB_BUILD_ARGS:-}" ]]; then
  if [[ -z "$SUPABASE_PUBLIC_URL" || -z "$SUPABASE_PUBLIC_ANON_KEY" ]]; then
    echo "Missing public Supabase build config: SUPABASE_PRODUCTION_URL/SUPABASE_URL and SUPABASE_PRODUCTION_ANON_KEY/SUPABASE_ANON_KEY are required." >&2
    exit 1
  fi
  DART_DEFINES_FILE="$(mktemp)"
  trap 'rm -f "${DART_DEFINES_FILE:-}"' EXIT
  DART_DEFINES_FILE="$DART_DEFINES_FILE" ruby -r json <<'RUBY'
File.write(
  ENV.fetch("DART_DEFINES_FILE"),
  JSON.generate({
    "SUPABASE_URL" => ENV.fetch("SUPABASE_PUBLIC_URL"),
    "SUPABASE_ANON_KEY" => ENV.fetch("SUPABASE_PUBLIC_ANON_KEY"),
    "APP_PUBLIC_URL" => ENV.fetch("APP_PUBLIC_URL"),
    "ADMIN_APP_URL" => ENV.fetch("ADMIN_APP_URL"),
    "APP_ENVIRONMENT" => "production",
    "ENABLE_ADMIN_PANEL" => "true",
    "COLLECT_PUBLIC_LANDING_HOME" => "true"
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
else
  # shellcheck disable=SC2206
  BUILD_ARGS=($FLUTTER_ADMIN_WEB_BUILD_ARGS)
fi

"$FLUTTER" build web -t lib/main_admin.dart "${BUILD_ARGS[@]}"

touch build/web/main.dart.js
mkdir -p build/web/icons
cp web/icons/collect-admin.png build/web/icons/collect-admin.png
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
manifest["background_color"] = "#FAF8F5"
manifest["theme_color"] = "#8885F0"
manifest["orientation"] = "any"
manifest["icons"] = [
  {
    "src" => "icons/collect-admin.png",
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
index = index.gsub(
  %r{\n\s*<link\s+rel="icon"[^>]*>}i,
  ""
)
unless index.include?('rel="icon" href="icons/collect-admin.png"')
  index = index.sub(
    %r{</head>}m,
    '  <link rel="icon" href="icons/collect-admin.png" type="image/png">' + "\n</head>"
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
bootstrap = bootstrap.gsub(
  %r{custom-sw\.js\?v=collect-admin-[0-9a-f]{16}},
  "custom-sw.js?v=__COLLECT_ADMIN_SW_VERSION__"
)
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
