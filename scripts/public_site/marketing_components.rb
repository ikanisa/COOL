# frozen_string_literal: true

module CollectPublicSite
  def content_grid_html(page, current_path)
    return "" if current_path == "/" || current_path == "/group-savings/" || page[:legal_key]
    return "" if Array(page[:sections]).empty?

    grid_class = ["content-grid", "content-grid-#{slug_for_path(current_path)}"].join(" ")
    <<~HTML
      <section class="#{grid_class}" aria-label="#{esc(page[:sections_heading] || "Page sections")}">
        #{page[:sections_heading] ? %(<h2 class="content-grid-heading">#{esc(page[:sections_heading])}</h2>) : ""}
        #{sections_html(page[:sections])}
      </section>
    HTML
  end

  def faq_section_html(_current_path)
    ""
  end

  def sections_html(sections)
    sections.each_with_index.map do |section, index|
      title, body, bullets = section
      bullet_html = Array(bullets).empty? ? "" : %(
          <ul class="bullet-list">
            #{list_items_html(Array(bullets))}
          </ul>
      )
      %(
      <article class="section-card">
        <span class="section-number">#{format("%02d", index + 1)}</span>
        <h2>#{esc(title)}</h2>
        <p>#{esc(body)}</p>
        #{bullet_html}
      </article>
    )
    end.join
  end

  def supported_groups_html(page)
    groups = Array(page[:supported_groups]).map { |group| group.to_s.strip }.reject(&:empty?)
    return "" if groups.empty?

    cards = groups.each_with_index.map do |group, index|
      label, body = group.split(":", 2).map { |part| part.to_s.strip }
      body = label if body.to_s.empty?
      label = "Group type" if label.to_s.empty?
      %(
      <article class="supported-group-card">
        <span class="supported-group-index">#{format("%02d", index + 1)}</span>
        <strong>#{esc(label)}</strong>
        <p>#{esc(body)}</p>
      </article>
    )
    end.join

    <<~HTML
      <section class="supported-groups-section" aria-labelledby="supported-groups-heading">
        <div class="supported-groups-copy">
          <h2 id="supported-groups-heading">#{esc(page[:supported_groups_heading] || "Collect supports community groups")}</h2>
        </div>
        <div class="supported-groups-grid">
          #{cards}
        </div>
      </section>
    HTML
  end

  def infographic_html(page)
    infographic = page[:infographic]
    return "" unless infographic

    steps = Array(infographic[:steps])
    body = infographic[:body].to_s.strip
    body_html = body.empty? ? "" : %(<p>#{esc(body)}</p>)
    step_cards = steps.each_with_index.map do |(title, body), index|
      step_body_html = if body.is_a?(Array)
        items = body.map { |item| item.to_s.strip }.reject(&:empty?)
        items.empty? ? "" : %(<ul>#{list_items_html(items)}</ul>)
      else
        step_body = body.to_s.strip
        step_body.empty? ? "" : %(<p>#{esc(step_body)}</p>)
      end
      %(
      <article class="infographic-step">
        <span class="section-number">#{format("%02d", index + 1)}</span>
        <h3>#{esc(title)}</h3>
        #{step_body_html}
      </article>
    )
    end.join

    <<~HTML
      <section class="infographic-band" aria-labelledby="infographic-heading">
        <div class="infographic-copy">
          <h2 id="infographic-heading">#{esc(infographic[:title])}</h2>
          #{body_html}
        </div>
        #{steps.empty? ? "" : %(<div class="infographic-grid">#{step_cards}</div>)}
      </section>
    HTML
  end

  def hero_visual_html(page, public_app_screens: nil)
    photo = {
      "/craas/" => ["banking-together.png", "A financial adviser and business owner reviewing plans together"],
      "/credit-readiness/" => ["banking-together.png", "A financial adviser and business owner reviewing plans together"],
      "/insurance/" => ["shared-goals.png", "Friends discussing their plans together in Kigali"],
      "/protection/" => ["shared-goals.png", "Friends discussing their plans together in Kigali"],
      "/partners/" => ["banking-together.png", "A financial adviser and business owner meeting in Kigali"],
      "/our-partners/" => ["banking-together.png", "A financial adviser and business owner meeting in Kigali"]
    }[page[:path]]
    if photo
      return <<~HTML
        <figure class="service-photo">
          <img src="/assets/marketing/rwanda/#{photo[0]}" alt="#{esc(photo[1])}" width="1536" height="1024" fetchpriority="high">
        </figure>
      HTML
    end

    id = {
      "/" => "home",
      "/group-savings/" => "group-detail",
      "/community-groups/" => "groups",
      "/trust/" => "security",
      "/security/" => "security",
      "/privacy/" => "privacy",
      "/terms/" => "terms",
      "/account-deletion/" => "account-deletion",
      "/data-deletion/" => "account-deletion"
    }.fetch(page[:path])
    screens = public_app_screens || (@public_app_media ||= PublicAppMedia.new(ROOT)).screens
    media = screens.fetch(id)
    <<~HTML
      <figure class="app-capture" data-app-screen="#{esc(id)}">
        <img src="#{esc(media.fetch('url'))}" alt="#{esc(media.fetch('alt'))}" width="#{media.fetch('width')}" height="#{media.fetch('height')}" fetchpriority="high">
        <figcaption>#{media.fetch('capture_kind') == 'browser_flutter_fixture' ? 'Collect interface preview' : 'Collect app'} · Example data</figcaption>
      </figure>
    HTML
  end

  def rwanda_photography_html(current_path)
    if current_path == "/"
      scenes = [
        ["community-savings.png", "A community planning its savings together", "Save together", "/group-savings/"],
        ["everyday-payments.png", "A shop owner and customer using their phones", "Everyday progress", "/community-groups/"],
        ["banking-together.png", "A business owner discussing a financial plan", "Prepare for your next step", "/craas/"]
      ]
      return %(<section class="rwanda-stories" aria-label="Collect in everyday life"><div class="rwanda-story-grid">) + scenes.map do |file, alt, title, link|
        %(<a class="rwanda-story" href="#{link}"><img src="/assets/marketing/rwanda/#{file}" alt="#{esc(alt)}" width="1536" height="1024" loading="lazy" decoding="async"><span>#{esc(title)}<span aria-hidden="true">↗</span></span></a>)
      end.join + "</div></section>"
    end
    scene = case current_path
            when "/group-savings/", "/community-groups/"
              ["community-savings.png", "People planning their community savings together"]
            when "/craas/", "/credit-readiness/", "/our-partners/", "/partners/"
              ["banking-together.png", "A business owner discussing a financial plan"]
            when "/insurance/"
              ["everyday-payments.png", "A shop owner and customer using their phones"]
            end
    return "" unless scene

    %(<figure class="rwanda-editorial"><img src="/assets/marketing/rwanda/#{scene[0]}" alt="#{esc(scene[1])}" width="1536" height="1024" loading="lazy" decoding="async"></figure>)
  end
end
