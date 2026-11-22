# frozen_string_literal: true

require_relative "public_site/legal_content"
require_relative "public_site/legal_values"

module CollectPublicLegalRendering
  PUBLIC_WEB_ANALYTICS_PRIVACY_URL = "https://developers.cloudflare.com/speed/observatory/rum-beacon/#privacy-information"

  include Content
  include Values

  LEGAL_PAGES_WITHOUT_SIDEBAR = %i[privacy terms trust].freeze

  # Public-hosting disclosure belongs to this website renderer, not the shared app policy.
  def public_web_analytics_disclosure_html
    <<~HTML
      <p>Collect's public website uses Cloudflare Web Analytics to measure page usage and performance. It sends page and referring-page addresses, a temporary page-load identifier, browser information and performance measurements to Cloudflare.</p>
      <p>Cloudflare states that the analytics script does not read or write cookies or browser storage. This is separate from the authentication and security technologies listed above. <a class="legal-inline-link" href="#{PUBLIC_WEB_ANALYTICS_PRIVACY_URL}">Read Cloudflare's RUM privacy information</a>.</p>
    HTML
  end

  def legal_section_heading_and_anchor(section)
    heading = section["heading"] || section["title"] || legal_label(section["id"])
    anchor = section["id"].to_s.strip
    anchor = heading.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-+\z/, "") if anchor.empty?
    [heading, anchor]
  end

  def legal_page_uses_sidebar?(page)
    !page || !LEGAL_PAGES_WITHOUT_SIDEBAR.include?(page[:legal_key])
  end

  def legal_section_html(section, public_privacy: false)
    return "" unless section.is_a?(Hash)

    heading, anchor = legal_section_heading_and_anchor(section)
    body = section.reject { |key, _| %w[id heading title].include?(key.to_s) }
    seen_contact_values = {}
    body = body.reject do |key, value|
      next false unless legal_contact_key?(key)

      contact_value = value.to_s.strip
      duplicate = seen_contact_values[contact_value]
      seen_contact_values[contact_value] = true
      duplicate
    end
    web_analytics = public_privacy && anchor == "cookies" ? public_web_analytics_disclosure_html : ""
    <<~HTML
      <article class="legal-section" id="#{esc(anchor)}">
        <h2>#{esc(heading)}</h2>
        #{body.map { |key, value| legal_named_value_html(key, value) }.join}#{web_analytics}
      </article>
    HTML
  end

  def legal_toc_html(content, page: nil)
    return "" unless legal_page_uses_sidebar?(page)

    sections = Array(content["sections"]).select { |section| section.is_a?(Hash) }
    links = sections.first(14).map do |section|
      heading, anchor = legal_section_heading_and_anchor(section)
      %(<a href="##{esc(anchor)}">#{esc(heading)}</a>)
    end
    return "" if links.empty?

    <<~HTML
      <nav class="legal-toc" aria-label="#{esc(content["title"] || "Legal page")} sections">
        <strong>On this page</strong>
        #{links.join}
      </nav>
    HTML
  end

  def legal_page_html(page)
    content = legal_content_for(page)
    return "" unless content

    meta = []
    meta << "Effective date: #{content["effective_date"]}" if content["effective_date"]
    meta << "Last updated: #{content["last_updated"]}" if content["last_updated"]
    top_keys = content.reject { |key, _| %w[id slug seo hero title sections effective_date last_updated].include?(key.to_s) || legal_internal_key?(key) }
    toc = legal_toc_html(content, page: page)
    no_sidebar = !legal_page_uses_sidebar?(page)
    sidebar = no_sidebar ? "" : [
      meta.empty? ? "" : %(<p class="legal-meta">#{esc(meta.join(" · "))}</p>),
      toc
    ].reject(&:empty?).join
    layout_class = ["legal-layout", sidebar.empty? ? "no-sidebar" : nil].compact.join(" ")
    <<~HTML
      <section class="legal-content" aria-label="#{esc(content["title"] || page[:h1])}">
        <div class="#{layout_class}">
          #{sidebar.empty? ? "" : %(<aside class="legal-sidebar">#{sidebar}</aside>)}
          <div class="legal-main">
            #{no_sidebar && !meta.empty? ? %(<p class="legal-meta">#{esc(meta.join(" · "))}</p>) : ""}
            #{top_keys.empty? ? "" : %(<div class="legal-priority">#{top_keys.map { |key, value| legal_named_value_html(key, value) }.join}</div>)}
            #{Array(content["sections"]).map { |section| legal_section_html(section, public_privacy: page[:legal_key] == :privacy) }.join}
          </div>
        </div>
      </section>
    HTML
  end
end
