source_commit, source_commit_status = Open3.capture2("git", "rev-parse", "HEAD")
source_changes, source_status = Open3.capture2("git", "status", "--porcelain")
version_path = "build/web/version.json"
version = JSON.parse(File.read(version_path))
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
    path.end_with?(
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

cache_urls = (["./"] + cache_paths.map { |path| "./#{path}" }).uniq
index = File.read(index_path)
index = index.gsub(%r{\n\s*<!-- Collect Admin PWA service worker -->.*?</script>}m, "")
File.write(index_path, index)

worker_template = File.read("scripts/templates/admin_pwa_service_worker.js")
%w[__COLLECT_ADMIN_CACHE_NAME__ __COLLECT_ADMIN_CACHE_URLS__].each do |marker|
  abort("Admin service worker must contain exactly one #{marker}") unless worker_template.scan(marker).length == 1
end
# The root shell is cached as ./ because hosting redirects /index.html. Its
# bytes, asset paths and worker policy must still invalidate the cache version.
version_paths = (cache_paths + ["index.html"]).uniq.sort
cache_schema_version = "fresh-install-v3"
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
unless bootstrap.include?("canvasKitBaseUrl: 'canvaskit/'")
  abort("flutter_bootstrap.js must self-host CanvasKit")
end
File.write(bootstrap_path, bootstrap)

File.write(
  service_worker_path,
  worker_template.gsub("__COLLECT_ADMIN_CACHE_NAME__", cache_name.to_json)
    .gsub("__COLLECT_ADMIN_CACHE_URLS__", JSON.pretty_generate(cache_urls))
)

generated_service_worker = File.read(service_worker_path)
abort("custom-sw.js must not precache Cloudflare _headers metadata") if generated_service_worker.include?('"./_headers"')
abort("custom-sw.js must not precache Cloudflare _redirects metadata") if generated_service_worker.include?('"./_redirects"')
abort("custom-sw.js must not precache the redirected /index.html path") if generated_service_worker.include?('"./index.html"')