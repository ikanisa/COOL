# frozen_string_literal: true

module CollectPublicSite
  def share_landing_page_html(kind:)
    group_link = kind == :group
    canonical_path = group_link ? "/c/" : "/app/"
    title = group_link ? "Open a Collect Group | Collect by IKANISA" : "Open Collect | Collect by IKANISA"
    description = if group_link
      "Open a shared Collect group invitation in the native app, or install Collect to continue securely."
    else
      "Open the native Collect app, or install Collect to organize group contributions in Rwanda."
    end
    heading = group_link ? "Open this Collect group" : "Open Collect"
    intro = if group_link
      "Open this link in Collect. If you need to install the app, return to the original message and open the link again."
    else
      "Continue in the native Collect app. If Collect is not installed, use the official store for this phone."
    end
    native_link = group_link ? nil : "collect://app"
    store_label = group_link ? "Google Play" : "Get Collect"
    navigation = [
      '<a class="nav-link" href="/group-savings/">Group Savings</a>',
      '<a class="nav-link" href="/trust/">Trust &amp; Security</a>'
    ].join("\n      ")
    share_schema = JSON.generate(
      "@context" => "https://schema.org",
      "@graph" => [
        {
          "@type" => "WebPage",
          "name" => title,
          "description" => description,
          "url" => "#{PUBLIC_URL}#{canonical_path}"
        },
        {
          "@type" => "SoftwareApplication",
          "name" => "Collect",
          "applicationCategory" => "FinanceApplication",
          "operatingSystem" => "Android, iOS"
        }
      ]
    )

    <<~HTML
      <!doctype html>
      <html lang="en">
      #{document_head_html(
        title: title, description: description, canonical: "#{PUBLIC_URL}#{canonical_path}",
        schema: share_schema, share_kind: group_link ? :group : :app
      )}
      <body class="revolut-public route-share-link" data-share-landing="#{group_link ? "group" : "app"}">
        <a class="skip-link" href="#content">Skip to content</a>
      #{site_header_html(
        label: "Public website", navigation: navigation,
        mobile_actions: %(<a class="button primary" href="#{GOOGLE_PLAY_URL}" data-collect-store-link>#{store_label}</a>),
        actions: %(<a class="button secondary" href="#{GOOGLE_PLAY_URL}" data-collect-store-link>#{store_label}</a>)
      )}

        <main id="content">
          <section class="hero share-link-hero">
            <div class="hero-copy">
              <p class="hero-eyebrow">Shared Collect link</p>
              <h1 data-share-heading>#{esc(heading)}</h1>
              <p class="hero-intro">#{esc(intro)}</p>
              #{'<p class="share-link-validity">Use the account you intend to join with, and choose Join in the app.</p><noscript><p>Enable JavaScript to open this link in Collect, or install Collect and reopen the original link from the message where you received it.</p></noscript>' if group_link}

              <div class="hero-actions">
                #{group_link ? '<button class="button primary" type="button" data-collect-open-link disabled>Open in Collect</button>' : %(<a class="button primary" href="#{native_link}" data-collect-open-link>Open in Collect</a>)}
                <a class="button ghost" href="#{GOOGLE_PLAY_URL}" data-collect-store-link>#{store_label}</a>
                <button class="button ghost" type="button" data-collect-copy-link#{group_link ? " disabled" : ""}>Copy link</button>
              </div>
              <p class="share-link-store-options">
                <a href="#{APPLE_APP_STORE_URL}" aria-label="Get Collect on the Apple App Store">App Store</a>
                <span aria-hidden="true">&middot;</span>
                <a href="#{GOOGLE_PLAY_URL}" aria-label="Get Collect on Google Play">Google Play</a>
              </p>
              <p class="share-link-status" data-share-status role="status" aria-live="polite">#{group_link ? "If Open in Collect is unavailable, reopen the original link after installing." : ""}</p>
            </div>
            <div class="hero-device">
              <div class="hero-widget share-link-widget" aria-label="Collect shared link preview">
                <img src="/icons/collect.png" alt="" width="72" height="72">
                <span>#{group_link ? "COLLECT GROUP LINK" : "COLLECT APP LINK"}</span>
                <strong>#{group_link ? "Continue in Collect." : "Private details stay in the app."}</strong>
                <p>#{group_link ? "Use your intended account and choose Join in the app." : "Receiver numbers, raw payment messages and member phone numbers are never placed in this public link."}</p>
              </div>
            </div>
          </section>
          <section class="start-section" aria-labelledby="share-link-help-heading">
            <div>
              <h2 id="share-link-help-heading">#{group_link ? "After installing Collect" : "Continue in the Collect app"}</h2>
            </div>
            <div>
              <p>#{group_link ? "Return to the original message and open its link again. Sign in to the account you want to use and choose Join in the app." : "Open Collect if it is installed, or use the store link for this device to install the app. Group invitations are confirmed separately after sign-in."}</p>
              <p>#{group_link ? "Having a link does not join you to a group or confirm a payment." : "Having a link does not expose payment credentials or confirm a payment."}</p>
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
