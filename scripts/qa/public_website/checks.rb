# frozen_string_literal: true

require 'json'
require 'time'
require 'uri'
require_relative '../public_capability_contract'

module PublicWebsiteChecks
  STYLESHEET_PATHS = %w[/styles.css /sections.css /revolut.css].freeze
  RETIRED_LANGUAGE_ROUTES = %w[/rw/ /rw/group-savings/ /rw/community-groups/ /fr/].freeze
  RETIRED_PRIVACY_REDIRECTS = {
    "/subprocessors/" => "/privacy/#sharing",
    "/privacy-request/" => "/account-deletion/",
    "/cookies/" => "/privacy/#cookies",
  }.freeze

  PRIVACY_LINKS = {
    "/privacy/#sharing" => "Read about service providers and data sharing",
    "mailto:info@ikanisa.com?subject=Collect+privacy+request" => "Email info@ikanisa.com about a privacy request",
    "/account-deletion/" => "Open the account-deletion page",
    "/privacy/#cookies" => "Read about cookies and website analytics",
  }.freeze

  def privacy_link_evidence(html)
    {
      "missing_links" => PRIVACY_LINKS.reject do |href, name|
        html.match?(%r{<a[^>]+href="#{Regexp.escape(href)}"[^>]*>#{Regexp.escape(name)}</a>})
      end,
      "retired_links" => html.scan(%r{href="/(?:subprocessors|privacy-request|cookies)/?"}),
    }
  end

  def retired_privacy_response?(request_url, response, replacement)
    return true if response.code.to_i == 404
    return false unless response.code.to_i == 302 && response["location"]

    URI.join(request_url, response["location"]) == URI.join(request_url, replacement)
  rescue URI::InvalidURIError
    false
  end

  def stylesheets_served?(stylesheets)
    stylesheets.all? do |page|
      page.fetch(:response).code.to_i == 200 && !page.fetch(:body).empty? &&
        page.fetch(:headers).fetch("content-type", "").start_with?("text/css")
    end
  end

  def mobile_css_ready?(stylesheet)
    stylesheet.match?(/@media\s*\(\s*max-width\s*:\s*720px\s*\)/) &&
      stylesheet.include?(".site-nav.open") &&
      stylesheet.include?(".mobile-menu-actions")
  end

  def home_conversion_evidence(registry, html)
    {
      "whatsapp_link_count" => html.scan(/https:\/\/wa\.me\//).length,
      "capability_action_failures" => PublicCapabilityContract.action_failures(registry, "/", html),
    }
  end

  def home_conversion_ok?(registry, html, evidence)
    download = registry.public_action('group_records').fetch('href')
    evidence.fetch("whatsapp_link_count").positive? && evidence.fetch("capability_action_failures").empty? &&
      html.include?(download) &&
      [
        "WhatsApp support options", "Partner Inquiry", "Privacy or Deletion",
        "WhatsApp for app access", "Ask for app access", 'type="email"', 'name="email"',
      ].none? { |label| html.include?(label) }
  end

  def route_action_failures(registry, pages)
    PublicCapabilityContract::ROUTES.map do |route|
      html = pages.fetch(route, '')
      failures = PublicCapabilityContract.action_failures(registry, route, html)
      if html.empty? || html.include?("faq-section") || html.include?("Questions visitors ask")
        failures << { "reason" => "Missing page or retired redundant sections" }
      end
      { "route" => route, "failures" => failures } unless failures.empty?
    end.compact
  end

  def json_ld_types_for(html)
    scripts = html.scan(%r{<script[^>]+type=["']application/ld\+json["'][^>]*>(.*?)</script>}m).flatten
    types = []
    parse_error = nil
    begin
      scripts.each do |script|
        parsed = JSON.parse(script)
        nodes = parsed.is_a?(Hash) && parsed["@graph"].is_a?(Array) ? parsed["@graph"] : [parsed]
        types.concat(nodes.map { |node| node["@type"] if node.is_a?(Hash) }.compact)
      end
    rescue JSON::ParserError => e
      parse_error = e.message
    end
    [scripts, types, parse_error]
  end

  def check(checks, id, passed, message, details = {})
    checks << {
      "id" => id,
      "status" => passed ? "pass" : "fail",
      "message" => message,
      "details" => details,
    }
  end

  def check_result(checks, context)
    failed = checks.count { |item| item.fetch("status") == "fail" }
    {"status" => failed.zero? ? "pass" : "fail"}.merge(context).merge(
      "checked_at_utc" => Time.now.utc.iso8601,
      "summary" => {
        "total" => checks.length,
        "passed" => checks.length - failed,
        "failed" => failed,
      },
      "checks" => checks,
    )
  end
end
