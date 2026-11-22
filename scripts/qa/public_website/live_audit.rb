# frozen_string_literal: true

require 'digest'
require 'fileutils'
require_relative 'checks'
require_relative 'http'

class PublicWebsiteLiveAudit
  include PublicWebsiteChecks
  include PublicWebsiteHTTP

  def run(base_url)
    base_url = base_url.delete_suffix("/")
    routes = [
      "/",
      "/privacy/",
      "/terms/",
      "/account-deletion/",
      "/data-deletion/",
      "/our-partners/",
      "/trust/",
      "/security/",
      "/sitemap.xml",
      "/robots.txt",
      *STYLESHEET_PATHS,
      "/site.js",
      "/manifest.json",
      "/icons/collect.png",
    ]
    fetch_audit_route = ->(route) { fetch_page("#{base_url}#{route}", redirects_left: 0) }
    responses = routes.to_h { |route| [route, fetch_audit_route.call(route)] }
    retired_language_responses = RETIRED_LANGUAGE_ROUTES.map(&fetch_audit_route)
    root = responses.fetch("/")
    root_body = text_body(root)
    stylesheets = responses.values_at(*STYLESHEET_PATHS)
    styles_text = stylesheets.map { |page| text_body(page) }.join("\n")
    styles_served = stylesheets_served?(stylesheets)
    privacy_body = text_body(responses.fetch("/privacy/"))
    partners_body = text_body(responses.fetch("/our-partners/"))
    sitemap_body = text_body(responses.fetch("/sitemap.xml"))
    manifest = responses.fetch("/manifest.json")
    collect_icon = responses.fetch("/icons/collect.png")
    site_js = responses.fetch("/site.js")
    root_elapsed_ms = elapsed_ms(root)
    css_bytes = responses.fetch("/styles.css").fetch(:body).bytesize
    js_bytes = site_js.fetch(:body).bytesize
    first_party_critical_bytes = [root, *stylesheets, site_js].sum { |page| page.fetch(:body).bytesize }

    _scripts, json_ld_types, json_ld_parse_error = json_ld_types_for(root_body)
    privacy_links = privacy_link_evidence(privacy_body)

    checks = {
      "http_all_required_routes_200" => responses.values.all? { |page| status_code(page) == 200 && !page.fetch(:body).empty? },
      "root_cacheable_no_noindex" => root.dig(:headers, "cache-control").to_s.include?("public") && !root.dig(:headers, "x-robots-tag").to_s.downcase.include?("noindex"),
      "valid_structured_data" => json_ld_parse_error.nil? && json_ld_types.include?("Organization") && json_ld_types.include?("SoftwareApplication"),
      "seo_metadata" => root_body.include?('rel="canonical"') && root_body.include?('property="og:title"') && root_body.include?('name="twitter:card"'),
      "pre_audit_brand_assets" => status_code(collect_icon) == 200 && Digest::SHA256.hexdigest(collect_icon.fetch(:body)) == "c6942d8bac7e860df1993e977277a47121340666b3f44a4f7cff63e079614209" &&
        root_body.include?('<link rel="icon" href="/icons/collect.png" type="image/png">') &&
        root_body.include?('<img src="/icons/collect.png" alt="" width="42" height="42">') &&
        root_body.include?('<meta property="og:image" content="https://collect.ikanisa.com/icons/collect.png">') &&
        !root_body.include?('class="brand-mark"') &&
        status_code(manifest) == 200 && manifest.fetch(:body).include?('"src": "/icons/collect.png"') && manifest.fetch(:body).include?('"sizes": "512x512"'),
      "no_flutter_or_wasm" => !root_body.match?(/flutter_bootstrap|flutter-view|main\.dart\.js|canvaskit|\.wasm/),
      "static_accessibility_signals" => root_body.include?('<html lang="en">') && root_body.include?('class="skip-link"') && root_body.scan(/<img\b[^>]*>/i).all? { |tag| tag.include?("alt=") } && styles_served && styles_text.include?(":focus-visible"),
      "english_only_language_decision" => root_body.include?('<html lang="en">') &&
        root_body.include?('property="og:locale" content="en_US"') &&
        root_body.include?('hreflang="x-default"') &&
        root_body.include?('hreflang="en"') &&
        !root_body.include?('hreflang="rw"') &&
        !root_body.include?('hreflang="fr"') &&
        !root_body.include?('class="language-switcher"') &&
        retired_language_responses.all? { |page| status_code(page) == 404 } &&
        !sitemap_body.include?("#{base_url}/rw/") &&
        !sitemap_body.include?("#{base_url}/fr/"),
      "privacy_references_are_links" => privacy_links.values.all?(&:empty?),
      "partner_status_disclaimer_absent" => !partners_body.include?("Current public status") &&
        !partners_body.include?("No institution is presented here as a live Collect partner yet.") &&
        !partners_body.include?("No financial institution is presented on this website as a live Collect partner yet.") &&
        !partners_body.include?("Partner names, regulators, and licence references will be published only after") &&
        !partners_body.include?("It is not presented here as a bank, deposit taker, lender or insurer") &&
        !root_body.include?("No financial institution is presented on this website as a live Collect partner until"),
      "redundant_disclaimer_blocks_absent" => [root_body, partners_body].all? { |body|
        !body.include?("Currently available for Android through the official Collect by IKANISA Google Play listing") &&
          !body.include?("iOS availability is not currently advertised") &&
          !body.include?("This website is published in English only") &&
          !body.include?("Fee clarity") &&
          !body.include?("How Collect makes money") &&
          !body.include?("Evidence boundary") &&
          !body.include?("Public evidence and market context") &&
          !body.include?("Current public status") &&
          !body.include?("No institution is presented here as a live Collect partner yet.")
      } && !styles_text.include?(".phone-screen") &&
        !root_body.include?('class="phone-shell"') &&
        !partners_body.include?('class="phone-shell"'),
      "performance_budgets" => root_elapsed_ms <= 1500 && root_body.bytesize <= 20_000 && css_bytes <= 30_000 && js_bytes <= 153_600 && first_party_critical_bytes <= 400_000,
      "mobile_responsive_css" => styles_served && mobile_css_ready?(styles_text),
    }

    {
      "checked_at_utc" => Time.now.utc.iso8601,
      "base_url" => base_url,
      "status" => checks.values.all? ? "pass" : "fail",
      "checks" => checks,
      "metrics" => {
        "root_elapsed_ms" => root_elapsed_ms,
        "root_html_bytes" => root_body.bytesize,
        "css_bytes" => css_bytes,
        "js_bytes" => js_bytes,
        "critical_first_party_bytes" => first_party_critical_bytes,
        "json_ld_types" => json_ld_types,
        "json_ld_parse_error" => json_ld_parse_error,
        "root_cache_control" => root.dig(:headers, "cache-control"),
        "root_cf_cache_status" => root.dig(:headers, "cf-cache-status"),
      },
      "route_matrix" => responses.transform_values { |page| route_metrics(page) },
    }
  end

  private

  def text_body(page)
    page.fetch(:body).dup.force_encoding("UTF-8")
  end

  def status_code(page)
    page.fetch(:response).code.to_i
  end

  def elapsed_ms(page)
    (page.fetch(:elapsed) * 1000).round
  end

  def route_metrics(page)
    {
      "status" => status_code(page),
      "elapsed_ms" => elapsed_ms(page),
      "bytes" => page.fetch(:body).bytesize,
      "content_type" => page.dig(:headers, "content-type"),
      "cache_control" => page.dig(:headers, "cache-control"),
      "cf_cache_status" => page.dig(:headers, "cf-cache-status"),
    }
  end
end

if $PROGRAM_NAME == __FILE__
  base_url = ARGV.fetch(0)
  out_dir = ARGV.fetch(1)
  payload = PublicWebsiteLiveAudit.new.run(base_url)
  FileUtils.mkdir_p(out_dir)
  File.write(File.join(out_dir, "live_audit_evidence.json"), JSON.pretty_generate(payload))
  puts JSON.pretty_generate(payload.reject { |key, _| key == "route_matrix" })
  exit payload.fetch("status") == "pass" ? 0 : 1
end
