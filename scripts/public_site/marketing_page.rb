# frozen_string_literal: true

module CollectPublicSite
  def json_ld(page)
    JSON.generate({
      "@context" => "https://schema.org",
      "@graph" => [
        {
          "@type" => "Organization",
          "name" => "IKANISA Ltd.",
          "url" => PUBLIC_URL,
          "contactPoint" => {
            "@type" => "ContactPoint",
            "contactType" => "customer support",
            "telephone" => DISPLAY_PHONE,
            "areaServed" => "RW"
          }
        },
        {
          "@type" => "SoftwareApplication",
          "name" => "Collect by IKANISA",
          "applicationCategory" => "FinanceApplication",
          "operatingSystem" => "Android, Web",
          "url" => page_url(page[:path]),
          "description" => page[:description]
        }
      ]
    })
  end

  def page_html(page, current_path: page[:path], public_app_screens: nil)
    hero_actions = cta_links_html(current_path, page, surface: :hero)
    <<~HTML
      <!doctype html>
      <html lang="en">
      #{document_head_html(
        title: page[:title], description: page[:description], canonical: page_url(current_path),
        schema: json_ld(page), current_path: current_path
      )}
      <body class="#{esc(page_classes(page, current_path))}">
        <a class="skip-link" href="#content">Skip to content</a>
      #{site_header_html(
        label: "Main navigation", navigation: nav_html(current_path),
        mobile_actions: hero_actions,
        actions: cta_links_html(current_path, page, surface: :header)
      )}

        <main id="content">
          <section class="hero #{page[:legal_key] ? "legal-hero" : ""}">
            <div class="hero-copy">
              #{page[:eyebrow] ? %(<p class="hero-eyebrow">#{esc(page[:eyebrow])}</p>) : ""}
              <h1>#{esc(page[:h1])}</h1>
              <p class="hero-intro">#{esc(page[:intro])}</p>
              <div class="hero-actions">
                #{hero_actions}
              </div>
            </div>
            #{current_path == "/" ? '<img class="hero-editorial" src="/assets/marketing/rwanda/kigali-woman-hero.png" alt="" width="1672" height="941" fetchpriority="high">' : "<div class=\"hero-device\">#{hero_visual_html(page, public_app_screens: public_app_screens)}</div>"}
          </section>

          #{rwanda_photography_html(current_path)}

          #{current_path == "/" ? "" : infographic_html(page)}

          #{current_path == "/" ? home_credit_readiness_html : ""}

          #{current_path == "/group-savings/" ? group_savings_page_html : ""}

          #{legal_page_html(page)}

          #{content_grid_html(page, current_path)}

          #{supported_groups_html(page)}

          #{current_path == "/our-partners/" || current_path == "/partners/" ? partner_page_html : ""}

          #{current_path == "/craas/" || current_path == "/credit-readiness/" ? craas_page_html : ""}

          #{current_path == "/insurance/" ? insurance_page_html : ""}

          #{current_path == "/" ? original_home_sections_html : ""}

          #{faq_section_html(current_path)}

          <section id="start" class="start-section #{page[:legal_key] ? "legal-start-section" : ""}" aria-labelledby="start-heading">
            <div>
              <h2 id="start-heading">#{page[:start_heading] ? esc(page[:start_heading]) : "Download <span class=\"brand-word\">Collect</span> or Get in Touch"}</h2>
              <div class="start-actions">
                #{cta_links_html(current_path, page, surface: :start)}
              </div>
            </div>
          </section>

        </main>

        #{site_footer_html}
        <script src="/site.js?v=#{ASSET_VERSION}" defer></script>
      </body>
      </html>
    HTML
  end
end
