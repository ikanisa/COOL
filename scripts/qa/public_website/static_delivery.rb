# frozen_string_literal: true

require "cgi"

module PublicWebsiteStaticDelivery
  private

  def check_delivery(checks, build_dir, root_html, headers)
    assetlinks_path = File.join(build_dir, ".well-known", "assetlinks.json")
    assetlinks = read(assetlinks_path)
    assetlinks_ok = assetlinks.include?("app.cool.mobile") && assetlinks.include?("sha256_cert_fingerprints")
    check(
      checks,
      "assetlinks",
      assetlinks_ok,
      assetlinks_ok ? "assetlinks.json is present for Android App Links." : "assetlinks.json is missing or incomplete.",
      "path" => assetlinks_path
    )

    flutter_markers = [
      "flutter_bootstrap.js",
      "main.dart.js",
      "flutter-view",
      "_flutter.loader",
    ]
    flutter_in_root = flutter_markers.select { |marker| root_html.include?(marker) }
    flutter_files = Dir.glob(File.join(build_dir, "**", "*")).select do |path|
      File.file?(path) && File.basename(path).match?(/\A(main(\..*)?\.dart\.js|flutter_bootstrap\.js|flutter\.js|flutter_service_worker\.js)\z/)
    end
    canvaskit_files = Dir.glob(File.join(build_dir, "canvaskit", "**", "*")).select { |path| File.file?(path) }
    critical_path_static = flutter_in_root.empty? && flutter_files.empty? && canvaskit_files.empty?
    check(
      checks,
      "no_flutter_public_critical_path",
      critical_path_static,
      critical_path_static ? "Public build has no Flutter/CanvasKit critical-path files." : "Public build still includes Flutter/CanvasKit critical-path files.",
      "root_markers" => flutter_in_root,
      "flutter_files" => flutter_files.map { |path| path.delete_prefix(build_dir + "/") },
      "canvaskit_file_count" => canvaskit_files.length
    )

    js_files = Dir.glob(File.join(build_dir, "**", "*.js")).select { |path| File.file?(path) }
    js_total = js_files.sum { |path| File.size(path) }
    js_budget = Integer(ENV.fetch("PUBLIC_SITE_JS_BUDGET_BYTES", "153600"))
    check(
      checks,
      "js_budget",
      js_total <= js_budget,
      js_total <= js_budget ? "JavaScript budget is within limit." : "JavaScript exceeds public-site budget.",
      "budget_bytes" => js_budget,
      "actual_bytes" => js_total,
      "files" => js_files.map { |path| [path.delete_prefix(build_dir + "/"), File.size(path)] }.to_h
    )

    wasm_files = Dir.glob(File.join(build_dir, "**", "*.wasm")).select { |path| File.file?(path) }
    check(
      checks,
      "no_wasm",
      wasm_files.empty?,
      wasm_files.empty? ? "No WASM files in public build." : "Public build contains WASM files.",
      "files" => wasm_files.map { |path| path.delete_prefix(build_dir + "/") }
    )

    headers_required = {
      "x-frame-options" => "DENY",
      "x-content-type-options" => "nosniff",
      "referrer-policy" => "strict-origin-when-cross-origin",
      "content-security-policy" => "default-src",
    }
    missing_headers = headers_required.reject do |key, value|
      headers.downcase.include?(key) && headers.include?(value)
    end
    check(
      checks,
      "security_headers",
      missing_headers.empty?,
      missing_headers.empty? ? "Security headers are present." : "Security headers are missing or incomplete.",
      "missing" => missing_headers.keys,
      "path" => File.join(build_dir, "_headers")
    )

    bad_cache = headers.include?("Cache-Control: no-store")
    immutable_asset_cache = headers.include?("max-age=31536000") && headers.include?("immutable")
    cache_ok = !bad_cache && immutable_asset_cache
    check(
      checks,
      "cache_policy",
      cache_ok,
      cache_ok ? "Public cache policy avoids no-store and keeps immutable assets." : "Public cache policy is not benchmark-ready.",
      "contains_no_store" => bad_cache,
      "contains_immutable_assets" => immutable_asset_cache
    )
  end

  def check_presentation(checks, build_dir, root_html, stylesheet, sitemap)
    css_vars = css_hex_vars(stylesheet)
    old_public_color_tokens = %w[
      #5f5ce6 #168447 #a7465c #5f67e8 #35d071 #0a8f5b
      #ff6148 #d63b2e #f59bb3 #b4576d #b04b7a
    ]
    old_public_color_hits = old_public_color_tokens.select { |hex| stylesheet.downcase.include?(hex) }
    required_public_roles = %w[web-canvas web-ink web-action web-secondary web-widget web-card-border web-night web-on-night web-focus-outer web-focus-inner]
    css_var_failures = required_public_roles.reject { |role| stylesheet.include?("--#{role}:") }
    legacy_palette = stylesheet.match?(/--(?:periwinkle|mint|rose|orange|g[1-4]):/)
    single_source_color_contract_ok = css_var_failures.empty? && old_public_color_hits.empty? && !legacy_palette
    check(
      checks,
      "single_source_color_contract",
      single_source_color_contract_ok,
      single_source_color_contract_ok ? "Public marketing uses shared semantic roles and no native or logo-derived colour palette." : "Public semantic roles are missing or retired styling remains.",
      "missing_roles" => css_var_failures,
      "legacy_palette" => legacy_palette,
      "old_public_color_hits" => old_public_color_hits
    )

    cta_contrast = {
      "marketing_primary" => contrast_ratio(css_vars.fetch("web-canvas", "#ffffff"), css_vars.fetch("web-action", "#1f1f1f")),
      "marketing_copy" => contrast_ratio(css_vars.fetch("web-secondary", "#505053"), css_vars.fetch("web-canvas", "#ffffff")),
      "marketing_heading" => contrast_ratio(css_vars.fetch("web-ink", "#191c1f"), css_vars.fetch("web-widget", "#f7f7f7")),
    }
    cta_contrast_ok = cta_contrast.values.all? { |ratio| ratio >= 4.5 }
    check(
      checks,
      "cta_white_label_contrast",
      cta_contrast_ok,
      cta_contrast_ok ? "Shared flat marketing colours meet AA contrast; rendered photography and interaction states require separate browser evidence." : "One or more shared marketing colours fails AA contrast.",
      "ratios" => cta_contrast
    )

    legal_layout_routes = ["/privacy/", "/terms/", "/account-deletion/", "/data-deletion/"]
    legal_layout_failures = legal_layout_routes.reject do |route|
      html = read(route_index(build_dir, route))
      has_layout = html.match?(/class="legal-layout(?: no-sidebar)?"/)
      File.file?(route_index(build_dir, route)) &&
        has_layout &&
        html.include?('class="legal-main"') &&
        html.include?('class="legal-priority"')
    end
    legal_css_ok = stylesheet.include?(".legal-layout") &&
      stylesheet.include?(".legal-toc") &&
      stylesheet.include?(".legal-priority") &&
      stylesheet.include?(".legal-hero") &&
      stylesheet.include?(".legal-start-section")
    check(
      checks,
      "legal_task_first_layout",
      legal_layout_failures.empty? && legal_css_ok,
      legal_layout_failures.empty? && legal_css_ok ? "Legal and deletion routes use a calmer task-first layout with navigation aids where sections exist." : "Legal/deletion task-first layout or CSS is missing.",
      "failures" => legal_layout_failures,
      "legal_css_ok" => legal_css_ok
    )

    routes_for_duplicate_check = sitemap.scan(%r{<loc>https://collect\.ikanisa\.com([^<]*)</loc>}).flatten
    route_identity = routes_for_duplicate_check.map do |route|
      route = "/" if route.empty?
      html = read(route_index(build_dir, route))
      {
        "route" => route,
        "title" => tag_text(html, "title"),
        "h1" => tag_text(html, "h1"),
      }
    end
    duplicate_titles = route_identity.group_by { |item| item["title"] }.select { |title, items| !title.empty? && items.length > 1 }
    duplicate_h1s = route_identity.group_by { |item| item["h1"] }.select { |h1, items| !h1.empty? && items.length > 1 }
    alias_identity_ok = duplicate_titles.empty? && duplicate_h1s.empty? &&
      read(route_index(build_dir, "/protection/")).include?("Protection support for daily earners.") &&
      read(route_index(build_dir, "/credit-readiness/")).include?("Credit-readiness support for bank-ready files.") &&
      read(route_index(build_dir, "/partners/")).include?("Partner operating model for Collect.") &&
      read(route_index(build_dir, "/security/")).include?("Security, privacy and trust controls.")
    check(
      checks,
      "alias_route_identity",
      alias_identity_ok,
      alias_identity_ok ? "Alias routes have deliberate unique title/H1 identities." : "Alias routes still duplicate title/H1 identity or lack explicit differentiation.",
      "duplicate_titles" => duplicate_titles.transform_values { |items| items.map { |item| item["route"] } },
      "duplicate_h1s" => duplicate_h1s.transform_values { |items| items.map { |item| item["route"] } }
    )

    mobile_hero_css_ok = stylesheet.match?(/\.app-capture img\{[^}]*height\s*:\s*auto/) &&
      stylesheet.match?(/\.hero-device\{[^}]*max-height\s*:\s*none/) &&
      stylesheet.match?(/\.site-footer a\{[^}]*min-height\s*:\s*44px/) &&
      stylesheet.match?(/@media\s*\(max-width:\s*720px\)/)
    route_class_ok = route_identity.all? do |item|
      read(route_index(build_dir, item["route"])).match?(%r{<body class="[^"]*\broute-[^"\s]+})
    end
    route_variation_ok = root_html.match?(%r{<body class="[^"]*\broute-home\b}) &&
      read(route_index(build_dir, "/craas/")).include?("content-grid-craas") &&
      read(route_index(build_dir, "/community-groups/")).include?("content-grid-community-groups")
    responsive_media_css = stylesheet.gsub(%r{/\*.*?\*/}m, "")
    responsive_components_ok = stylesheet.match?(/grid-template-columns\s*:\s*minmax\(\s*0\s*,\s*1fr\s*\)/) &&
      stylesheet.match?(/overflow-wrap\s*:\s*anywhere/) &&
      responsive_media_css.match?(/@media\s*\(\s*prefers-reduced-motion\s*:\s*reduce\s*\)/) &&
      responsive_media_css.match?(/@media\s*\(\s*forced-colors\s*:\s*active\s*\)/) &&
      stylesheet.include?(".mobile-menu-actions")
    menu_routes = route_identity.map { |item| item["route"] } + ["/c/", "/app/", "/group-link/"]
    menu_failures = menu_routes.reject do |route|
      html = read(route_index(build_dir, route))
      html.include?('aria-controls="site-nav"') && html.include?('id="site-nav"') &&
        html.include?("data-menu-button") && html.include?("data-site-nav")
    end
    check(
      checks,
      "responsive_layout_and_route_variation",
      mobile_hero_css_ok && route_class_ok && route_variation_ok && responsive_components_ok && menu_failures.empty?,
      "Static responsive and menu structure checks only; browser layout, task, contrast and source fidelity remain separate.",
      "mobile_hero_css_ok" => mobile_hero_css_ok,
      "route_class_ok" => route_class_ok,
      "route_variation_ok" => route_variation_ok,
      "responsive_components_ok" => responsive_components_ok,
      "menu_failures" => menu_failures
    )
  end

  def tag_text(html, tag)
    html[%r{<#{tag}\b[^>]*>(.*?)</#{tag}>}m, 1].to_s.gsub(/<[^>]+>/, " ").gsub(/\s+/, " ").strip
  end

  def css_hex_vars(stylesheet)
    stylesheet.scan(/--([a-z0-9-]+):\s*(#[0-9a-fA-F]{6})/).to_h
  end

  def srgb(value)
    value /= 255.0
    value <= 0.03928 ? value / 12.92 : ((value + 0.055) / 1.055)**2.4
  end

  def luminance(hex)
    red, green, blue = hex.delete("#").scan(/../).map { |pair| pair.to_i(16) }
    0.2126 * srgb(red) + 0.7152 * srgb(green) + 0.0722 * srgb(blue)
  end

  def contrast_ratio(foreground, background)
    lighter, darker = [luminance(foreground), luminance(background)].sort.reverse
    ((lighter + 0.05) / (darker + 0.05)).round(2)
  end
end
