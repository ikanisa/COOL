# frozen_string_literal: true

require "uri"
require "digest"
require "json"

module PublicWebsiteStaticRoutes
  private

  def check_routes(checks, build_dir, root_html, expected_public_origin)
    check(
      checks,
      "build_dir_exists",
      Dir.exist?(build_dir),
      Dir.exist?(build_dir) ? "Public build directory exists." : "Missing public build directory.",
      "build_dir" => build_dir
    )

    required_routes = {
      "/" => ["Microsavings and group savings for daily earners", "Collect"],
      "/group-savings/" => ["Group savings"],
      "/privacy/" => ["Privacy Policy", "Account deletion and data deletion"],
      "/terms/" => ["Terms"],
      "/account-deletion/" => ["Account Deletion"],
      "/data-deletion/" => ["Data Deletion"],
    }

    alternative_routes = {
      "credit_readiness" => [["/credit-readiness/", "Credit"], ["/craas/", "Credit"]],
      "protection" => [["/protection/", "Protection"], ["/insurance/", "Insurance"]],
      "partners" => [["/partners/", "Partners"], ["/our-partners/", "Partners"]],
      "trust" => [["/trust/", "Trust"], ["/security/", "Security"]],
    }

    required_routes.each do |route, required_text|
      path = route_index(build_dir, route)
      html = read(path)
      ok = File.file?(path) && required_text.all? { |text| html.include?(text) }
      check(
        checks,
        "route#{route.gsub(%r{[^a-zA-Z0-9]+}, "_")}",
        ok,
        ok ? "#{route} has content-complete HTML." : "#{route} is missing or lacks required content.",
        "path" => path,
        "required_text" => required_text,
        "bytes" => file_size(path)
      )
    end

    group_share_path = File.join(build_dir, "c", "index.html")
    app_share_path = File.join(build_dir, "app", "index.html")
    redirects_path = File.join(build_dir, "_redirects")
    group_share_html = read(group_share_path)
    group_link_share_path = File.join(build_dir, "group-link", "index.html")
    group_link_share_html = read(group_link_share_path)
    app_share_html = read(app_share_path)
    redirects = read(redirects_path)
    # Static structure only: this does not validate hosted redirect query preservation.
    site_script = read(File.join(build_dir, "site.js"))
    start_group = site_script.index("function groupCodeForAddress(")
    end_group = start_group && site_script.index("function bindAppShareLinks(", start_group)
    group_script = start_group && end_group ? site_script[start_group...end_group] : ""
    begin
      group_canonical = group_share_html[/<link rel="canonical" href="([^"]+)" data-share-canonical>/, 1]
      generic_group_canonical = group_canonical == "#{expected_public_origin}/c/" &&
        group_share_html.include?(%(<meta property="og:url" content="#{expected_public_origin}/c/" data-share-og-url>))
      settings = site_script.scan(/^\s*const publicSite = (\{[^\n]*\});$/)
      compiled_origin_matches = settings.length == 1 &&
        JSON.parse(settings.first.first)["publicOrigin"] == expected_public_origin &&
        site_script.include?("if (shareKind === 'group') bindGroupShareLinks(publicSite.publicOrigin);")
    rescue JSON::ParserError
      generic_group_canonical = false
      compiled_origin_matches = false
    end
    share_routes_ok =
      File.file?(group_share_path) && File.file?(group_link_share_path) &&
      group_share_html == group_link_share_html && compiled_origin_matches &&
      group_share_html.include?("Open this Collect group") &&
      group_share_html.include?('data-share-landing="group"') &&
      group_share_html.include?('<button class="button primary" type="button" data-collect-open-link disabled>') &&
      group_share_html.include?('<button class="button ghost" type="button" data-collect-copy-link disabled>') &&
      group_share_html.include?('<meta name="referrer" content="no-referrer">') &&
      group_share_html.include?("<noscript>") && group_share_html.include?("reopen the original link") &&
      !group_share_html.include?("collect://group/shared-group") &&
      !group_share_html.include?("data-share-code") && !group_share_html.include?("app-argument=") &&
      generic_group_canonical &&
      group_script.include?("address.protocol !== 'https:' || address.origin !== expectedOrigin") &&
      group_script.include?("candidate === candidate.trim() && slug.length === 36") &&
      group_script.include?("openLink.addEventListener('click'") &&
      group_script.include?("navigator.clipboard.writeText(canonical)") &&
      group_share_html.include?('name="robots" content="noindex, nofollow"') &&
      app_share_html.include?("Open Collect") &&
      app_share_html.include?('data-share-landing="app"') &&
      app_share_html.include?("collect://app") &&
      app_share_html.include?('data-collect-store-link') &&
      app_share_html.include?('name="apple-itunes-app"') &&
      app_share_html.include?("https://apps.apple.com/app/id6783960331") &&
      app_share_html.include?("https://play.google.com/store/apps/details?id=app.cool.mobile") &&
      redirects.include?("/c/* /group-link/?slug=:splat 302") &&
      redirects.include?("/invite/* /app/?publicId=:splat 302")
    check(
      checks,
      "native_share_link_fallbacks",
      share_routes_ok,
      share_routes_ok ? "Static share templates and actions are present; hosted redirect and device behavior remain unverified." : "Group or app share-link fallback output is incomplete.",
      "group_path" => group_share_path,
      "group_link_path" => group_link_share_path,
      "app_path" => app_share_path,
      "redirects_path" => redirects_path
    )

    retired_routes = ["/impact/", "/rw/", "/rw/group-savings/", "/rw/community-groups/", "/subprocessors/", "/privacy-request/", "/cookies/"]
    retired_route_files = retired_routes.select { |route| File.exist?(route_index(build_dir, route)) }
    check(
      checks,
      "retired_routes_absent",
      retired_route_files.empty?,
      retired_route_files.empty? ? "Retired public routes are absent from the generated build." : "Generated build still contains retired public routes.",
      "retired_present" => retired_route_files
    )

    alternative_routes.each do |id, options|
      matches = options.select do |route, text|
        html = read(route_index(build_dir, route))
        File.file?(route_index(build_dir, route)) && html.include?(text)
      end
      check(
        checks,
        "route_#{id}",
        matches.any?,
        matches.any? ? "#{id} route is present." : "#{id} route is missing.",
        "accepted_routes" => options.map(&:first),
        "matched_routes" => matches.map(&:first)
      )
    end

    rw_route_files = Dir.glob(File.join(build_dir, "rw", "**", "index.html"))
    french_route_files = Dir.glob(File.join(build_dir, "fr", "**", "index.html"))
    english_only_decision_ok = rw_route_files.empty? &&
      french_route_files.empty? &&
      root_html.include?('<html lang="en">') &&
      root_html.include?('property="og:locale" content="en_US"') &&
      root_html.include?('hreflang="x-default"') &&
      root_html.include?('hreflang="en"') &&
      !root_html.include?('hreflang="rw"') &&
      !root_html.include?('hreflang="fr"') &&
      !root_html.include?('class="language-switcher"')
    check(
      checks,
      "english_only_language_decision",
      english_only_decision_ok,
      english_only_decision_ok ? "English is the only published language; no unsupported language route or switcher is emitted." : "The English-only product decision is incomplete or an unsupported language route/switcher remains.",
      "rw_route_files" => rw_route_files,
      "french_route_files" => french_route_files
    )
  end

  def check_discovery(checks, build_dir, root_html, headers, sitemap)
    root_index = route_index(build_dir, "/")
    headers_path = File.join(build_dir, "_headers")
    robots_path = File.join(build_dir, "robots.txt")
    robots = read(robots_path)
    sitemap_path = File.join(build_dir, "sitemap.xml")
    manifest_text = read(File.join(build_dir, "manifest.json"))
    collect_icon_path = File.join(build_dir, "icons", "collect.png")

    raw_html_ok = root_html.include?("<main") &&
      root_html.include?("<h1") &&
      root_html.include?("Collect") &&
      root_html.include?("Microsavings and group savings for daily earners")
    check(
      checks,
      "root_raw_html_content",
      raw_html_ok,
      raw_html_ok ? "Root has meaningful raw HTML content." : "Root raw HTML content is insufficient.",
      "path" => root_index,
      "bytes" => file_size(root_index)
    )

    no_noindex = !headers.downcase.include?("noindex") &&
      !root_html.downcase.include?("noindex")
    check(
      checks,
      "no_public_noindex",
      no_noindex,
      no_noindex ? "No noindex marker found in public headers/root HTML." : "Public output contains noindex.",
      "headers_path" => headers_path
    )

    canonical_ok = root_html.include?('<link rel="canonical" href="https://collect.ikanisa.com/')
    check(
      checks,
      "canonical_root",
      canonical_ok,
      canonical_ok ? "Root canonical URL exists." : "Root canonical URL is missing.",
      "path" => root_index
    )

    og_ok = root_html.include?('property="og:title"') &&
      root_html.include?('property="og:description"') &&
      root_html.include?('name="twitter:card"')
    check(
      checks,
      "social_metadata",
      og_ok,
      og_ok ? "Root social metadata exists." : "Root social metadata is incomplete."
    )

    json_ld_scripts, json_ld_types, json_ld_parse_error = json_ld_types_for(root_html)
    json_ld_ok = json_ld_scripts.any? &&
      json_ld_parse_error.nil? &&
      (json_ld_types.include?("Organization") || json_ld_types.include?("FinancialService")) &&
      json_ld_types.include?("SoftwareApplication")
    check(
      checks,
      "structured_data",
      json_ld_ok,
      json_ld_ok ? "Structured data is valid JSON-LD." : "Missing or invalid Organization/FinancialService and SoftwareApplication JSON-LD.",
      "types" => json_ld_types,
      "parse_error" => json_ld_parse_error
    )

    official_asset_hashes = {
      collect_icon_path => "c6942d8bac7e860df1993e977277a47121340666b3f44a4f7cff63e079614209",
    }
    official_asset_hash_failures = official_asset_hashes.reject do |path, expected_hash|
      File.file?(path) && Digest::SHA256.file(path).hexdigest == expected_hash
    end
    brand_assets_match_baseline = official_asset_hash_failures.empty? &&
      root_html.include?('<link rel="icon" href="/icons/collect.png" type="image/png">') &&
      root_html.include?('<img src="/icons/collect.png" alt="" width="42" height="42">') &&
      root_html.include?('<meta property="og:image" content="https://collect.ikanisa.com/icons/collect.png">') &&
      !root_html.include?('class="brand-mark"') &&
      manifest_text.include?('"src": "/icons/collect.png"') &&
      manifest_text.include?('"sizes": "512x512"') &&
      manifest_text.include?('"type": "image/png"')
    check(
      checks,
      "pre_audit_brand_assets",
      brand_assets_match_baseline,
      brand_assets_match_baseline ? "Official header logo, PNG favicon, social image, and manifest icon match the governed immutable asset hash." : "A governed website brand asset differs from its immutable hash.",
      "path" => collect_icon_path,
      "bytes" => file_size(collect_icon_path),
      "hash_failures" => official_asset_hash_failures
    )

    robots_ok = robots.include?("User-agent: *") &&
      robots.include?("Allow: /") &&
      !robots.include?("Disallow: /")
    check(
      checks,
      "robots_allow",
      robots_ok,
      robots_ok ? "robots.txt allows public crawling." : "robots.txt does not clearly allow crawling.",
      "path" => robots_path
    )

    required_sitemap_paths = ["/", "/group-savings", "/privacy", "/terms", "/account-deletion", "/data-deletion"]
    missing_sitemap = required_sitemap_paths.reject { |path| sitemap.include?("https://collect.ikanisa.com#{path}") }
    retired_sitemap_paths = ["/impact", "/diaspora", "/rw/", "/rw/group-savings", "/rw/community-groups", "/subprocessors", "/privacy-request", "/cookies"]
    retired_sitemap = retired_sitemap_paths.select { |path| sitemap.include?("https://collect.ikanisa.com#{path}") }
    check(
      checks,
      "sitemap_routes",
      missing_sitemap.empty? && retired_sitemap.empty?,
      missing_sitemap.empty? && retired_sitemap.empty? ? "Sitemap includes required public routes and excludes retired routes." : "Sitemap is missing required routes or still includes retired routes.",
      "missing" => missing_sitemap,
      "retired_present" => retired_sitemap,
      "path" => sitemap_path
    )

    sitemap_url_count = sitemap.scan(%r{<url>}).length
    sitemap_lastmod_values = sitemap.scan(%r{<lastmod>([^<]+)</lastmod>}).flatten
    sitemap_lastmod_ok = sitemap_url_count.positive? &&
      sitemap_lastmod_values.length == sitemap_url_count &&
      sitemap_lastmod_values.all? { |value| value.match?(/\A\d{4}-\d{2}-\d{2}\z/) }
    check(
      checks,
      "sitemap_lastmod",
      sitemap_lastmod_ok,
      sitemap_lastmod_ok ? "Sitemap includes ISO date lastmod for every URL." : "Sitemap is missing valid lastmod dates.",
      "url_count" => sitemap_url_count,
      "lastmod_count" => sitemap_lastmod_values.length,
      "lastmod_values" => sitemap_lastmod_values.uniq,
      "path" => sitemap_path
    )

    sitemap_route_failures = []
    sitemap.scan(%r{<loc>([^<]+)</loc>}).flatten.each do |url|
      begin
        uri = URI(url)
      rescue URI::InvalidURIError
        sitemap_route_failures << { "url" => url, "failure" => "invalid_uri" }
        next
      end

      route = uri.path.empty? ? "/" : uri.path
      unless uri.scheme == "https" && uri.host == "collect.ikanisa.com"
        sitemap_route_failures << { "url" => url, "route" => route, "failure" => "wrong_host_or_scheme" }
        next
      end
      unless route == "/" || route.end_with?("/")
        sitemap_route_failures << { "url" => url, "route" => route, "failure" => "non_canonical_no_slash_route" }
        next
      end

      path = route_index(build_dir, route)
      html = read(path)
      scripts, types, parse_error = json_ld_types_for(html)
      route_ok = File.file?(path) &&
        html.bytesize.positive? &&
        !html.downcase.include?("noindex") &&
        html.include?(%(<link rel="canonical" href="#{url}">)) &&
        html.include?('property="og:title"') &&
        html.include?('property="og:description"') &&
        html.include?('name="twitter:card"') &&
        scripts.any? &&
        parse_error.nil? &&
        types.include?("Organization") &&
        types.include?("SoftwareApplication")

      next if route_ok

      sitemap_route_failures << {
        "url" => url,
        "route" => route,
        "path" => path,
        "file_exists" => File.file?(path),
        "bytes" => html.bytesize,
        "json_ld_types" => types,
        "json_ld_parse_error" => parse_error,
      }
    end
    check(
      checks,
      "sitemap_route_metadata",
      sitemap_route_failures.empty?,
      sitemap_route_failures.empty? ? "Every sitemap route has local non-redirecting metadata-complete HTML." : "One or more sitemap routes lacks complete local metadata.",
      "failures" => sitemap_route_failures
    )
  end
end
