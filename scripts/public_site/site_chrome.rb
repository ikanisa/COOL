# frozen_string_literal: true

module CollectPublicSite
  def esc(value)
    CGI.escapeHTML(value.to_s)
  end

  def whatsapp_url(message)
    "https://wa.me/#{WHATSAPP_NUMBER}?text=#{CGI.escape(message)}"
  end

  def account_deletion_portal_url
    ACCOUNT_DELETION_PORTAL_URL
  end

  def support_email
    SUPPORT_EMAIL
  end

  def mailto_url(subject)
    "mailto:#{support_email}?subject=#{CGI.escape(subject)}"
  end

  def page_url(path)
    normalized_path = path == "/" ? "/" : "#{path.delete_suffix("/")}/"
    "#{PUBLIC_URL}#{normalized_path}"
  end

  def nav_html(current_path)
    PRIMARY_NAV.map do |label, href|
      active = current_path == href ||
        (href == "/craas/" && current_path == "/credit-readiness/") ||
        (href == "/insurance/" && current_path == "/protection/") ||
        (href == "/our-partners/" && current_path == "/partners/")
      %(<a class="nav-link#{active ? " active" : ""}" href="#{href}"#{active ? ' aria-current="page"' : ""}>#{esc(label)}</a>)
    end.join
  end

  def policy_path?(page)
    page[:legal_key]
  end

  def slug_for_path(path)
    normalized = path == "/" ? "home" : path.delete_prefix("/").delete_suffix("/").tr("/", "-")
    normalized.empty? ? "home" : normalized
  end

  def page_classes(page, current_path)
    classes = ["revolut-public", "route-#{slug_for_path(current_path)}"]
    classes << "legal-page" if policy_path?(page)
    classes << "alias-page" if page[:canonical_path]
    classes.join(" ")
  end

  def cta_links_html(_current_path, page, surface:)
    capability_id = page.fetch(:capability_id, "group_records")
    action = PRODUCT_CAPABILITIES.public_action(capability_id)
    app_class = surface == :header ? "button secondary cta-app" : "button primary cta-app"
    secondary_class = surface == :start ? "button ghost on-light" : "button ghost"
    items = [%(<a class="#{app_class}" href="#{esc(action.fetch('href'))}">#{esc(action.fetch('label'))}</a>)]
    if %w[group_records private_group_creation].include?(capability_id)
      group = PRODUCT_CAPABILITIES.source_action("private_group_creation", region: "RW", platform: "android")
      unless group == action
        items << %(<a class="#{secondary_class} cta-group" href="#{esc(group.fetch('href'))}">#{esc(group.fetch('label'))}</a>)
      end
    end
    support = PRODUCT_CAPABILITIES.public_action("support")
    items << %(<a class="#{secondary_class} cta-touch" href="#{esc(support.fetch('href'))}">#{esc(support.fetch('label'))}</a>)
    (surface == :header ? [items.first] : items).join("\n")
  end

  def site_footer_html
    footer_whatsapp_message = "Hello IKANISA, I am contacting you from the Collect website."
    <<~HTML
      <footer class="site-footer">
        <div class="footer-identity">
          <strong>Collect by IKANISA</strong>
          <p>#{esc(REGISTERED_ENTITY)}</p>
          <p>#{esc(REGULATORY_FOOTER_NOTE)}</p>
          <p class="footer-support">Support: <a href="#{mailto_url("Collect support")}">#{esc(support_email)}</a> <span aria-hidden="true">·</span> <a class="whatsapp-contact" href="#{whatsapp_url(footer_whatsapp_message)}"><span class="sr-only">WhatsApp</span><span>#{esc(DISPLAY_PHONE)}</span></a></p>
          <p>© #{Time.now.utc.year} #{esc(REGISTERED_ENTITY)}. All rights reserved.</p>
        </div>
        <nav aria-label="Footer navigation">
          <a href="/privacy/">Privacy</a>
          <a href="/terms/">Terms</a>
          <a href="/account-deletion/">Account deletion</a>
          <a href="/data-deletion/">Data deletion</a>
          <a href="/trust/">Trust</a>
        </nav>
      </footer>
    HTML
  end

  def alternate_links(current_path)
    [
      %(<link rel="alternate" hreflang="x-default" href="#{page_url(current_path)}">),
      %(<link rel="alternate" hreflang="en" href="#{page_url(current_path)}">),
    ].join("\n")
  end

  def document_head_html(title:, description:, canonical:, schema:, current_path: nil, share_kind: nil)
    escaped_title = esc(title)
    escaped_description = esc(description)
    tags = [
      "<head>",
      '  <meta charset="utf-8">',
      '  <meta name="viewport" content="width=device-width, initial-scale=1">',
      "  <title>#{escaped_title}</title>",
      %(  <meta name="description" content="#{escaped_description}">)
    ]
    tags << '  <meta name="robots" content="noindex, nofollow">' if share_kind
    tags << %(  <meta name="theme-color" content="#{BRAND_BLACK}">)
    case share_kind
    when :group
      tags << '  <meta name="referrer" content="no-referrer">'
    when :app
      tags << %(  <meta name="apple-itunes-app" content="app-id=#{APPLE_APP_STORE_ID}, app-argument=#{canonical}" data-share-smart-banner>)
    end

    tags << %(  <link rel="canonical" href="#{canonical}"#{' data-share-canonical' if share_kind}>)
    tags << "  #{alternate_links(current_path)}" if current_path
    tags.concat([
      '  <link rel="icon" href="/icons/collect.png" type="image/png">',
      '  <link rel="manifest" href="/manifest.json">',
      '  <meta property="og:type" content="website">',
      '  <meta property="og:locale" content="en_US">',
      %(  <meta property="og:url" content="#{canonical}"#{' data-share-og-url' if share_kind}>),
      %(  <meta property="og:title" content="#{escaped_title}">),
      %(  <meta property="og:description" content="#{escaped_description}">),
      %(  <meta property="og:image" content="#{PUBLIC_URL}/icons/collect.png">),
      '  <meta name="twitter:card" content="summary_large_image">'
    ])
    unless share_kind
      tags << %(  <meta name="twitter:title" content="#{escaped_title}">)
      tags << %(  <meta name="twitter:description" content="#{escaped_description}">)
    end
    %w[styles sections revolut].each do |name|
      tags << %(  <link rel="stylesheet" href="/#{name}.css?v=#{ASSET_VERSION}">)
    end
    tags << %(  <script type="application/ld+json">#{schema}</script>)
    tags << "</head>"
    tags.join("\n")
  end

  def site_header_html(label:, navigation:, mobile_actions:, actions:)
    [
      '  <header class="site-header">',
      '    <a class="brand" href="/">',
      '      <img src="/icons/collect.png" alt="" width="42" height="42">',
      '      <span><strong>Collect</strong><small>by IKANISA</small></span>',
      '    </a>',
      '    <button class="menu-button" type="button" data-menu-button aria-expanded="false" aria-controls="site-nav">Menu</button>',
      %(    <nav id="site-nav" class="site-nav" data-site-nav aria-label="#{esc(label)}">),
      "      #{navigation}",
      %(      <div class="mobile-menu-actions">#{mobile_actions}</div>),
      "    </nav>",
      '    <div class="header-actions">',
      "      #{actions}",
      "    </div>",
      "  </header>"
    ].join("\n")
  end

  def list_items_html(items)
    items.map { |item| %(<li>#{esc(item)}</li>) }.join
  end
end
