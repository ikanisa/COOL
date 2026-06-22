#!/usr/bin/env ruby
# frozen_string_literal: true

require "cgi"
require "fileutils"
require "json"
require "time"

ROOT = File.expand_path("..", __dir__)
BUILD_DIR = File.expand_path(ENV.fetch("PUBLIC_BUILD_DIR", "build/public_web"), ROOT)
PUBLIC_URL = "https://collect.ikanisa.com"
CONTACT_EMAIL = "info@ikanisa.com"
WHATSAPP_NUMBER = "250795588248"
DISPLAY_PHONE = "+250 795 588 248"
USSD_CODE = "*182*8*1*41258*2000#"
BRAND_ASSET = "assets/brand/generated/collect_visual_group_momentum.png"
MOMO_ASSET = "assets/brand/generated/collect_visual_momo_signal.png"
QR_ASSET = "assets/brand/generated/collect_visual_qr_share.png"
ICON_ASSET = "assets/brand/generated/collect_app_icon_rule.png"
INDEXNOW_KEY = ENV.fetch("PUBLIC_INDEXNOW_KEY", "").strip
INDEXNOW_KEY_PATTERN = /\A[A-Za-z0-9-]{8,128}\z/

PRIMARY_NAV = [
  ["Group savings", "/group-savings/"],
  ["Diaspora", "/diaspora/"],
  ["Credit readiness", "/credit-readiness/"],
  ["Protection", "/protection/"],
  ["Partners", "/partners/"],
  ["Impact", "/impact/"],
  ["Trust", "/trust/"]
].freeze

LANGUAGES = {
  "en" => {
    name: "English",
    path: "/",
    hero_title: "Credit-ready saving for Rwanda's daily economy",
    hero_body: "Collect helps trusted groups turn everyday contributions into clearer records, consent-led credit-readiness files, and protection pathways.",
    primary_cta: "Start a group",
    secondary_cta: "Talk on WhatsApp",
    self_serve_title: "Request group setup",
    self_serve_body: "Share a phone or email contact and the IKANISA team can start the group setup path without losing the web session."
  },
  "rw" => {
    name: "Kinyarwanda",
    path: "/rw/",
    hero_title: "Kuzigama mu itsinda bigahinduka amateka yizewe",
    hero_body: "Collect ifasha amatsinda ya ibimina kubika imisanzu, gukurikirana inyandiko, no gutegura amakuru yafasha mu biganiro by'inguzanyo.",
    primary_cta: "Tangira itsinda",
    secondary_cta: "Vugana natwe kuri WhatsApp",
    self_serve_title: "Saba gufashwa gutangiza itsinda",
    self_serve_body: "Andika telefoni cyangwa email kugira ngo ikipe ya IKANISA igufashe gutangira."
  },
  "fr" => {
    name: "Français",
    path: "/fr/",
    hero_title: "Une épargne de groupe prête pour le crédit",
    hero_body: "Collect aide les groupes d'épargne à transformer les cotisations quotidiennes en dossiers plus clairs, avec consentement et preuves structurées.",
    primary_cta: "Créer un groupe",
    secondary_cta: "Parler sur WhatsApp",
    self_serve_title: "Demander la création d'un groupe",
    self_serve_body: "Laissez un téléphone ou un e-mail pour démarrer le parcours avec IKANISA."
  }
}.freeze

PAGES = [
  {
    path: "/",
    title: "Collect by IKANISA",
    description: "Group savings, MoMo-first contributions, credit-readiness records, and protection pathways for Rwanda's daily economy.",
    h1: "Credit-ready saving for Rwanda's daily economy",
    intro: "Collect helps trusted groups turn everyday contributions into clearer records, consent-led credit-readiness files, and protection pathways.",
    asset: BRAND_ASSET,
    sections: [
      ["Group savings", "Run ibimina and savings groups with cleaner contribution records, member roles, and shareable group progress."],
      ["Credit readiness", "Turn consistent saving behavior into organized records that providers can review with group or member consent."],
      ["Protection pathway", "Connect saving and repayment discipline to clearer insurance and resilience support when approved products are available."]
    ]
  },
  {
    path: "/group-savings/",
    title: "Group Savings | Collect by IKANISA",
    description: "Cleaner records for ibimina, savings groups, treasurers, and members building financial proof together.",
    h1: "Group savings that become credit evidence",
    intro: "Collect gives group leaders and members one place to follow contributions, roles, activity, and meeting-ready records.",
    asset: BRAND_ASSET,
    sections: [
      ["Run the group clearly", "Track members, roles, rules, and contribution activity without exposing private payment details."],
      ["Invite without friction", "Use QR, links, and familiar chat channels to bring members into the right group."],
      ["Prepare records", "Keep histories organized so future credit or provider conversations start with cleaner evidence."]
    ]
  },
  {
    path: "/diaspora/",
    title: "Diaspora Savings | Collect by IKANISA",
    description: "Structured diaspora group saving for Rwanda investment pathways, custody records, and collateral rules.",
    h1: "Diaspora savings with custody and collateral rules",
    intro: "Collect supports groups saving across borders for Rwanda-focused commitments, with clearer rules and records before money is committed.",
    asset: QR_ASSET,
    sections: [
      ["Shared saving structure", "Keep member balances, commitments, and rules visible to the group."],
      ["Custody records", "Separate free savings from locked commitments and collateral rules."],
      ["Rwanda pathway", "Prepare cleaner records for property, SME, agriculture, and family investment discussions."]
    ]
  },
  {
    path: "/credit-readiness/",
    aliases: ["/craas/"],
    title: "Credit Readiness | Collect by IKANISA",
    description: "How Collect turns saving discipline into clearer credit-readiness records without promising loan approval.",
    h1: "Credit-readiness records before the credit conversation",
    intro: "Collect organizes group and member saving behavior into a clearer file. Providers still make their own credit decisions.",
    asset: MOMO_ASSET,
    sections: [
      ["Save consistently", "Groups build contribution history through familiar payment and group workflows."],
      ["Create a verified ledger", "Collect organizes contribution activity, member roles, and group progress into a readable record."],
      ["Share with consent", "Group or member consent controls what is shared with a provider, insurer, cooperative, or support team."],
      ["Provider decision", "Collect prepares the evidence; final credit decisions remain with the chosen provider."]
    ]
  },
  {
    path: "/protection/",
    aliases: ["/insurance/"],
    title: "Protection | Collect by IKANISA",
    description: "Saving-linked protection and repayment resilience pathways for Collect groups and members.",
    h1: "Protection connected to saving discipline",
    intro: "Collect prepares clearer records for insurance and repayment resilience support where approved products and providers are available.",
    asset: MOMO_ASSET,
    sections: [
      ["Group income protection", "Support group resilience when verified income disruption affects earning ability."],
      ["Credit life context", "Keep repayment and contribution records ready for approved protection products."],
      ["Clear support records", "Keep customer support, consent, and product context attached to the member journey."]
    ]
  },
  {
    path: "/partners/",
    aliases: ["/our-partners/"],
    title: "Partners | Collect by IKANISA",
    description: "A public-data-backed opportunity for banks, insurers, cooperatives, and mobile-money partners.",
    h1: "Partner with savings behavior that already exists",
    intro: "Collect helps institutions see organized saving discipline, group context, and consent-led customer records.",
    asset: BRAND_ASSET,
    sections: [
      ["Banks and SACCOs", "Review clearer saving records and group context before a credit conversation."],
      ["Insurers", "Connect protection design to real contribution and repayment behavior."],
      ["Cooperatives and groups", "Use trusted community structures as a better distribution and support surface."]
    ]
  },
  {
    path: "/impact/",
    title: "Impact | Collect by IKANISA",
    description: "Public market data behind Rwanda's savings, payment, insurance, and group-economy opportunity.",
    h1: "Impact for Rwanda's daily economy",
    intro: "Collect is built around existing savings behavior, familiar payment rails, and the need for clearer records.",
    asset: BRAND_ASSET,
    metrics: [
      ["96%", "financial inclusion"],
      ["52%", "adults participating in ibimina"],
      ["US$0.5B+", "diaspora remittance opportunity"],
      ["RWF 19,807B", "2024 payment value referenced in public market work"]
    ],
    sections: [
      ["Payment rails already operate at scale", "Rwanda has broad everyday payment familiarity and reachable mobile-money behavior."],
      ["Informal saving is mainstream", "Ibimina and savings groups already help households organize discipline and trust."],
      ["Records unlock conversations", "Cleaner histories can support credit-readiness, protection, and partner review."]
    ]
  },
  {
    path: "/trust/",
    aliases: ["/security/"],
    title: "Trust and Security | Collect by IKANISA",
    description: "How Collect handles records, privacy, deletion, support, and careful fintech claims.",
    h1: "Trust starts with clear records and careful claims",
    intro: "Collect keeps contribution records, support paths, and data-handling boundaries visible. Product, partner, regulator, credit, and insurance claims are made only when approved.",
    asset: QR_ASSET,
    sections: [
      ["Data minimization", "Collect uses identity, contact, Collect ID, group, contribution, payment reference, consent, and support data only for the service and requested workflows."],
      ["Deletion and correction", "Customers can request account deletion, data deletion, or correction through the app, email, or WhatsApp after ownership verification."],
      ["Dispute and support path", "IKANISA support can review account, group, contribution, and payment-reference questions through approved support channels."],
      ["No approval promise", "Collect prepares records. Credit, insurance, and provider decisions remain with the relevant provider under their own rules."]
    ]
  },
  {
    path: "/privacy/",
    title: "Privacy Policy and Data Deletion | Collect by IKANISA",
    description: "How Collect handles customer information, account deletion requests, and data deletion requests.",
    h1: "Privacy Policy and Data Deletion",
    intro: "Customers can request account deletion and associated data deletion in the app, by email, or by WhatsApp without reinstalling the app.",
    asset: MOMO_ASSET,
    sections: [
      ["What Collect collects", "Collect may collect identity, contact, Collect ID and account details, group membership, roles, rules, contribution activity, payout records, payment references, support messages, consent choices, and service notifications. Camera or image inputs are used only when a customer chooses QR, support, or evidence features."],
      ["How Collect uses information", "Information is used to operate the app, WhatsApp, support, and group workflows; maintain group records; prepare savings, contribution, credit-readiness, and insurance support records requested by customers; protect accounts; prevent misuse; investigate disputes; and improve reliability and support."],
      ["Sharing and service providers", "Collect does not sell customer personal data. Information may be shared with payment, messaging, hosting, analytics, security, and support service providers; with banks, insurers, cooperatives, group leaders, or partners only when required for a customer-requested workflow; or with authorities, auditors, or dispute handlers where legally required."],
      ["Security and retention", "Collect uses access controls, transport security, and operational safeguards. Records are kept only as long as needed for the service, customer support, security, fraud prevention, audit, dispute, payment reconciliation, tax, legal, or regulatory reasons."],
      ["Account deletion request", "Customers can request deletion of their Collect account and associated data from inside the app through Settings, or from this public web resource without reinstalling the app. Email info@ikanisa.com or message WhatsApp +250 795 588 248 with the phone number or Collect ID connected to the account. IKANISA may verify account ownership before processing the request."],
      ["Data deletion and correction request", "Customers can ask IKANISA to delete or correct personal data that is no longer needed for Collect. When an app account is deleted, associated user data is deleted unless limited retention is required for legitimate security, fraud-prevention, ledger, dispute, payment, audit, tax, legal, or regulatory reasons."]
    ]
  },
  {
    path: "/terms/",
    title: "Terms of Service | Collect by IKANISA",
    description: "How customers use Collect services.",
    h1: "Terms of Service",
    intro: "Collect supports group savings records, contribution visibility, credit-readiness preparation, and customer support. It does not guarantee credit, insurance, or provider approval.",
    asset: QR_ASSET,
    sections: [
      ["Customer responsibility", "Customers and group leaders must provide accurate information and use Collect only for lawful group and support workflows."],
      ["Provider decisions", "Credit, insurance, banking, and partner decisions remain with the relevant provider."],
      ["Support", "Questions can be sent to info@ikanisa.com or WhatsApp +250 795 588 248."]
    ]
  },
  {
    path: "/account-deletion/",
    title: "Account Deletion | Collect by IKANISA",
    description: "Request account deletion from Collect.",
    h1: "Account Deletion",
    intro: "You can request deletion of your Collect account from inside the app or through IKANISA support without reinstalling the app.",
    asset: MOMO_ASSET,
    sections: [
      ["How to request deletion", "Email info@ikanisa.com or message WhatsApp +250 795 588 248 with the phone number or Collect ID connected to the account."],
      ["Verification", "IKANISA may verify account ownership before processing the request."],
      ["Retention", "Some ledger, security, dispute, payment reconciliation, audit, tax, legal, or regulatory records may be retained where required."]
    ]
  },
  {
    path: "/data-deletion/",
    title: "Data Deletion | Collect by IKANISA",
    description: "Ask IKANISA to delete or correct Collect personal data that is no longer needed for the service.",
    h1: "Data Deletion",
    intro: "Customers can ask IKANISA to delete or correct personal data that is no longer needed for Collect.",
    asset: MOMO_ASSET,
    sections: [
      ["Request data deletion", "Email info@ikanisa.com or message WhatsApp +250 795 588 248 with the phone number or Collect ID connected to the account."],
      ["Correction", "Customers can also ask IKANISA to correct inaccurate account or support data."],
      ["Retention boundaries", "Deletion may exclude records retained for legitimate security, fraud-prevention, ledger, dispute, payment, audit, tax, legal, or regulatory reasons."]
    ]
  }
].freeze

def esc(value)
  CGI.escapeHTML(value.to_s)
end

def whatsapp_url(message)
  "https://wa.me/#{WHATSAPP_NUMBER}?text=#{CGI.escape(message)}"
end

def page_url(path)
  normalized_path = path == "/" ? "/" : "#{path.delete_suffix("/")}/"
  "#{PUBLIC_URL}#{normalized_path}"
end

def write_file(path, body)
  FileUtils.mkdir_p(File.dirname(path))
  File.write(path, body)
end

def route_file(path)
  return File.join(BUILD_DIR, "index.html") if path == "/"
  File.join(BUILD_DIR, path.delete_prefix("/").delete_suffix("/"), "index.html")
end

def nav_html(current_path)
  PRIMARY_NAV.map do |label, href|
    active = current_path == href || (href == "/credit-readiness/" && current_path == "/craas/") || (href == "/protection/" && current_path == "/insurance/") || (href == "/partners/" && current_path == "/our-partners/")
    %(<a class="nav-link#{active ? " active" : ""}" href="#{href}">#{esc(label)}</a>)
  end.join
end

def language_links(current_path)
  localized_home_paths = LANGUAGES.values.map { |data| data[:path] }
  LANGUAGES.map do |code, data|
    href = if localized_home_paths.include?(current_path)
             data[:path]
           elsif code == "en"
             current_path
           else
             data[:path]
           end
    %(<a href="#{href}" lang="#{code}">#{esc(data[:name])}</a>)
  end.join
end

def localized_home_path?(path)
  LANGUAGES.values.map { |data| data[:path] }.include?(path)
end

def alternate_links(current_path)
  return "" unless localized_home_path?(current_path)

  links = LANGUAGES.map do |code, data|
    %(<link rel="alternate" hreflang="#{code}" href="#{page_url(data[:path])}">)
  end
  links << %(<link rel="alternate" hreflang="x-default" href="#{page_url("/")}">)
  links.join("\n  ")
end

def og_locale_for(code)
  {
    "en" => "en_US",
    "rw" => "rw_RW",
    "fr" => "fr_FR"
  }.fetch(code, "en_US")
end

def json_ld(page)
  JSON.generate({
    "@context" => "https://schema.org",
    "@graph" => [
      {
        "@type" => "Organization",
        "name" => "IKANISA Ltd.",
        "url" => PUBLIC_URL,
        "email" => CONTACT_EMAIL,
        "contactPoint" => {
          "@type" => "ContactPoint",
          "contactType" => "customer support",
          "telephone" => DISPLAY_PHONE,
          "email" => CONTACT_EMAIL,
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

def metric_grid(metrics)
  return "" unless metrics

  <<~HTML
    <div class="metric-grid" aria-label="Public market proof">
      #{metrics.map { |value, label| %(<div class="metric"><strong>#{esc(value)}</strong><span>#{esc(label)}</span></div>) }.join}
    </div>
  HTML
end

def sections_html(sections)
  sections.each_with_index.map do |(title, body), index|
    %(
      <article class="section-card">
        <span class="section-number">#{format("%02d", index + 1)}</span>
        <h2>#{esc(title)}</h2>
        <p>#{esc(body)}</p>
      </article>
    )
  end.join
end

def contact_form
  <<~HTML
    <form class="lead-form" action="mailto:#{CONTACT_EMAIL}" method="post" enctype="text/plain">
      <label>
        <span>Phone or email</span>
        <input name="email" type="email" placeholder="you@example.com" autocomplete="email">
      </label>
      <label>
        <span>What do you need?</span>
        <select name="intent">
          <option>Group setup</option>
          <option>App access</option>
          <option>Partner inquiry</option>
          <option>Privacy or deletion request</option>
        </select>
      </label>
      <button type="submit">Request group setup</button>
    </form>
  HTML
end

def page_html(page, current_path: page[:path], localized: nil)
  title = localized ? localized[:hero_title] : page[:h1]
  intro = localized ? localized[:hero_body] : page[:intro]
  primary_cta = localized ? localized[:primary_cta] : "Start a group"
  secondary_cta = localized ? localized[:secondary_cta] : "Talk on WhatsApp"
  lang_code = localized ? localized[:code] : "en"

  <<~HTML
    <!doctype html>
    <html lang="#{lang_code}">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>#{esc(page[:title])}</title>
      <meta name="description" content="#{esc(page[:description])}">
      <meta name="theme-color" content="#8885F0">
      <link rel="canonical" href="#{page_url(current_path)}">
      #{alternate_links(current_path)}
      <link rel="icon" href="/icons/collect.png" type="image/png">
      <link rel="manifest" href="/manifest.json">
      <meta property="og:type" content="website">
      <meta property="og:locale" content="#{og_locale_for(lang_code)}">
      <meta property="og:url" content="#{page_url(current_path)}">
      <meta property="og:title" content="#{esc(page[:title])}">
      <meta property="og:description" content="#{esc(page[:description])}">
      <meta property="og:image" content="#{PUBLIC_URL}/assets/brand/generated/collect_visual_group_momentum.png">
      <meta name="twitter:card" content="summary_large_image">
      <meta name="twitter:title" content="#{esc(page[:title])}">
      <meta name="twitter:description" content="#{esc(page[:description])}">
      <link rel="stylesheet" href="/styles.css">
      <script type="application/ld+json">#{json_ld(page)}</script>
    </head>
    <body>
      <a class="skip-link" href="#content">Skip to content</a>
      <header class="site-header">
        <a class="brand" href="/" aria-label="Collect home">
          <img src="/icons/collect.png" alt="" width="42" height="42">
          <span><strong>Collect</strong><small>by IKANISA</small></span>
        </a>
        <button class="menu-button" type="button" data-menu-button aria-expanded="false" aria-controls="site-nav">Menu</button>
        <nav id="site-nav" class="site-nav" data-site-nav aria-label="Main navigation">
          #{nav_html(current_path)}
        </nav>
        <div class="header-actions">
          <a class="button secondary" href="#start">#{esc(primary_cta)}</a>
          <a class="button ghost" href="#{whatsapp_url("Hello IKANISA, I want help with Collect.")}">#{esc(secondary_cta)}</a>
        </div>
      </header>

      <main id="content">
        <section class="hero">
          <div class="hero-copy">
            <p class="trust-line">MoMo-first group savings. Consent-led records. No credit approval promise.</p>
            <h1>#{esc(title)}</h1>
            <p class="hero-intro">#{esc(intro)}</p>
            <div class="hero-actions">
              <a class="button primary" href="#start">#{esc(primary_cta)}</a>
              <a class="button ghost" href="#{whatsapp_url("Hello IKANISA, I want to create a Collect group.")}">#{esc(secondary_cta)}</a>
            </div>
          </div>
          <div class="hero-device" aria-label="Collect product preview">
            <img src="/#{page[:asset]}" alt="Collect product visual">
            <div class="phone-panel">
              <span>Group ledger</span>
              <strong>250,000 RWF</strong>
              <p>Saved across verified member contributions</p>
              <div class="progress"><span class="progress-value"></span></div>
            </div>
          </div>
        </section>

        #{metric_grid(page[:metrics])}

        <section class="explain-band" aria-labelledby="credit-readiness-heading">
          <div>
            <p class="section-kicker">How credit-readiness works</p>
            <h2 id="credit-readiness-heading">From saving discipline to review-ready records</h2>
          </div>
          <ol class="step-list">
            <li><strong>Save consistently</strong><span>Groups contribute through familiar MoMo and app-supported workflows.</span></li>
            <li><strong>Build a ledger</strong><span>Collect organizes contribution history, roles, and progress into readable records.</span></li>
            <li><strong>Share with consent</strong><span>Members or groups control what can be shared for support or provider review.</span></li>
            <li><strong>Provider decides</strong><span>Collect prepares evidence. Final credit decisions remain with the provider, and protection decisions remain with the relevant approved provider.</span></li>
          </ol>
        </section>

        <section class="content-grid" aria-label="Page sections">
          #{sections_html(page[:sections])}
        </section>

        <section id="start" class="start-section" aria-labelledby="start-heading">
          <div>
            <p class="section-kicker">Start with Collect</p>
            <h2 id="start-heading">A self-serve path, with WhatsApp still available</h2>
            <p>Use the form to start a group, request app access, ask a partner question, or handle a privacy request. WhatsApp remains available for human support.</p>
          </div>
          #{contact_form}
        </section>

        <section class="policy-fallback" aria-labelledby="policy-heading">
          <h2 id="policy-heading">Privacy Policy and Data Deletion</h2>
          <p>The official policy route is <a href="/privacy/">https://collect.ikanisa.com/privacy/</a>. The legacy Play URL <a href="/#/privacy">https://collect.ikanisa.com/#/privacy</a> redirects users to the same policy content when JavaScript is available.</p>
          <p>Customers can request account deletion or data deletion through the app, by emailing <a href="mailto:#{CONTACT_EMAIL}">#{CONTACT_EMAIL}</a>, or by messaging WhatsApp <a href="https://wa.me/#{WHATSAPP_NUMBER}">#{DISPLAY_PHONE}</a>.</p>
        </section>
      </main>

      <footer class="site-footer">
        <div>
          <strong>Collect by IKANISA</strong>
          <p>Credit-ready saving for Rwanda's daily economy. Final credit, insurance, and provider decisions remain with the relevant provider.</p>
        </div>
        <nav aria-label="Footer navigation">
          <a href="/privacy/">Privacy</a>
          <a href="/terms/">Terms</a>
          <a href="/account-deletion/">Account deletion</a>
          <a href="/data-deletion/">Data deletion</a>
          <a href="/trust/">Trust</a>
          #{language_links(current_path)}
        </nav>
      </footer>
      <script src="/site.js" defer></script>
    </body>
    </html>
  HTML
end

def stylesheet
  <<~CSS
    :root {
      color-scheme: dark light;
      --paper: #faf8f5;
      --ink: #252044;
      --muted: #5f5a76;
      --night: #050510;
      --panel: #12111c;
      --line: rgba(250, 248, 245, .14);
      --periwinkle: #8885f0;
      --mint: #3cd070;
      --rose: #d38b96;
      --orange: #ff5e43;
      --white: #fffdfb;
      --focus: #a7a2ff;
      font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    }
    * { box-sizing: border-box; }
    html { scroll-behavior: smooth; }
    body { margin: 0; background: var(--night); color: var(--paper); letter-spacing: 0; }
    a { color: inherit; }
    a:focus-visible, button:focus-visible, input:focus-visible, select:focus-visible { outline: 3px solid var(--focus); outline-offset: 4px; }
    .skip-link { position: absolute; left: 16px; top: -80px; z-index: 10; background: var(--paper); color: var(--ink); padding: 10px 12px; border-radius: 8px; }
    .skip-link:focus { top: 16px; }
    .site-header { min-height: 72px; display: flex; align-items: center; gap: 20px; padding: 18px clamp(20px, 5vw, 64px); position: sticky; top: 0; z-index: 5; background: rgba(5, 5, 16, .86); backdrop-filter: blur(18px); border-bottom: 1px solid rgba(250,248,245,.08); }
    .brand { display: inline-flex; align-items: center; gap: 10px; text-decoration: none; min-width: max-content; }
    .brand img { border-radius: 10px; }
    .brand strong, .brand small { display: block; line-height: 1; }
    .brand strong { font-size: 19px; font-weight: 900; }
    .brand small { color: rgba(250,248,245,.7); font-weight: 800; margin-top: 3px; }
    .site-nav { display: flex; gap: 6px; align-items: center; flex: 1; justify-content: center; }
    .nav-link { text-decoration: none; font-size: 13px; font-weight: 850; color: rgba(250,248,245,.72); padding: 10px 12px; border-radius: 10px; white-space: nowrap; }
    .nav-link:hover, .nav-link.active { color: var(--paper); background: rgba(250,248,245,.09); }
    .header-actions, .hero-actions { display: flex; gap: 10px; flex-wrap: wrap; }
    .button, button { min-height: 44px; border: 1px solid rgba(250,248,245,.18); border-radius: 12px; display: inline-flex; align-items: center; justify-content: center; padding: 12px 18px; text-decoration: none; font-size: 14px; font-weight: 900; cursor: pointer; }
    .button.primary, .button.secondary, .lead-form button { background: var(--periwinkle); color: white; border-color: var(--periwinkle); box-shadow: 0 14px 34px rgba(136,133,240,.24); }
    .button.ghost { background: transparent; color: var(--paper); }
    .menu-button { display: none; background: rgba(250,248,245,.08); color: var(--paper); }
    .hero { min-height: calc(100svh - 72px); display: grid; grid-template-columns: minmax(0, 1.02fr) minmax(320px, .78fr); gap: clamp(28px, 5vw, 72px); align-items: center; padding: clamp(48px, 8vw, 104px) clamp(20px, 5vw, 64px) 64px; background: radial-gradient(circle at 72% 18%, rgba(136,133,240,.28), transparent 32%), radial-gradient(circle at 18% 80%, rgba(60,208,112,.16), transparent 32%), #050510; }
    .trust-line, .section-kicker { color: var(--mint); font-size: 13px; font-weight: 900; text-transform: uppercase; letter-spacing: .08em; margin: 0 0 18px; }
    h1 { font-size: clamp(44px, 8vw, 96px); line-height: .94; margin: 0; max-width: 920px; font-weight: 950; }
    .hero-intro { color: rgba(250,248,245,.74); font-size: clamp(19px, 2.1vw, 25px); line-height: 1.38; max-width: 760px; margin: 26px 0 30px; }
    .hero-device { position: relative; min-height: 520px; display: grid; place-items: center; }
    .hero-device > img { width: min(92%, 440px); aspect-ratio: 4 / 5; object-fit: cover; border-radius: 34px; opacity: .72; box-shadow: 0 34px 90px rgba(0,0,0,.42); }
    .phone-panel { position: absolute; width: min(82%, 330px); right: 0; bottom: 36px; background: rgba(17,16,24,.92); border: 1px solid var(--line); border-radius: 24px; padding: 22px; box-shadow: 0 24px 80px rgba(0,0,0,.5); }
    .phone-panel span { color: rgba(250,248,245,.64); font-weight: 850; }
    .phone-panel strong { display: block; font-size: 34px; margin: 10px 0 6px; }
    .phone-panel p { margin: 0 0 16px; color: rgba(250,248,245,.64); line-height: 1.35; }
    .progress { height: 8px; border-radius: 999px; overflow: hidden; background: rgba(250,248,245,.1); }
    .progress span { display: block; height: 100%; background: linear-gradient(90deg, var(--mint), var(--periwinkle)); }
    .progress-value { width: 72%; }
    .metric-grid { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 1px; background: rgba(250,248,245,.12); border-top: 1px solid rgba(250,248,245,.12); border-bottom: 1px solid rgba(250,248,245,.12); }
    .metric { padding: 28px clamp(18px, 3vw, 34px); background: #0b0a14; }
    .metric strong { display: block; font-size: clamp(26px, 4vw, 48px); }
    .metric span { color: rgba(250,248,245,.68); font-weight: 750; }
    .explain-band, .start-section, .policy-fallback { display: grid; grid-template-columns: minmax(0, .72fr) minmax(0, 1fr); gap: clamp(24px, 5vw, 72px); padding: clamp(56px, 8vw, 96px) clamp(20px, 5vw, 64px); background: var(--paper); color: var(--ink); }
    .explain-band h2, .start-section h2, .policy-fallback h2 { font-size: clamp(34px, 5vw, 64px); line-height: 1; margin: 0; }
    .step-list { display: grid; gap: 12px; margin: 0; padding: 0; list-style: none; }
    .step-list li, .section-card, .lead-form { border: 1px solid #e5deef; border-radius: 16px; padding: 18px; background: #fffdfb; }
    .step-list strong, .step-list span { display: block; }
    .step-list span { color: var(--muted); margin-top: 4px; line-height: 1.45; }
    .content-grid { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 18px; padding: clamp(56px, 8vw, 96px) clamp(20px, 5vw, 64px); background: #fffdfb; color: var(--ink); }
    .section-number { color: var(--periwinkle); font-weight: 950; }
    .section-card h2 { margin: 18px 0 10px; font-size: 24px; line-height: 1.12; }
    .section-card p, .start-section p, .policy-fallback p { color: var(--muted); line-height: 1.55; }
    .lead-form { display: grid; gap: 14px; }
    .lead-form label span { display: block; font-weight: 900; margin-bottom: 8px; }
    .lead-form input, .lead-form select { width: 100%; min-height: 46px; border-radius: 10px; border: 1px solid #ded8ea; padding: 0 12px; font: inherit; color: var(--ink); background: white; }
    .policy-fallback { grid-template-columns: 1fr; background: #0b0a14; color: var(--paper); }
    .policy-fallback p { color: rgba(250,248,245,.72); max-width: 960px; }
    .site-footer { display: grid; grid-template-columns: minmax(0, 1fr) minmax(280px, .8fr); gap: 28px; padding: 36px clamp(20px, 5vw, 64px); border-top: 1px solid rgba(250,248,245,.12); background: #050510; }
    .site-footer p { color: rgba(250,248,245,.65); max-width: 680px; line-height: 1.45; }
    .site-footer nav { display: flex; flex-wrap: wrap; justify-content: flex-end; align-content: start; gap: 12px 18px; }
    .site-footer a { color: rgba(250,248,245,.82); font-weight: 800; }
    @media (max-width: 980px) {
      .site-header { flex-wrap: nowrap; }
      .menu-button { display: inline-flex; margin-left: auto; }
      .site-nav { display: none; position: absolute; top: 100%; left: 0; right: 0; padding: 12px clamp(20px, 5vw, 64px) 18px; justify-content: flex-start; overflow: visible; flex-wrap: wrap; background: #050510; border-bottom: 1px solid rgba(250,248,245,.1); box-shadow: 0 24px 60px rgba(0,0,0,.35); }
      .site-nav.open { display: flex; }
      .header-actions { display: none; }
      .hero { min-height: auto; grid-template-columns: 1fr; padding-top: 40px; }
      .hero-device { min-height: 360px; }
      .hero-device > img { width: min(100%, 360px); }
      .phone-panel { left: 50%; right: auto; transform: translateX(-50%); bottom: 0; }
      .metric-grid, .content-grid { grid-template-columns: 1fr 1fr; }
      .explain-band, .start-section { grid-template-columns: 1fr; }
    }
    @media (max-width: 560px) {
      .site-header { padding: 14px 20px; gap: 12px; }
      .brand strong { font-size: 18px; }
      .hero { padding: 28px 20px 44px; gap: 18px; }
      h1 { font-size: clamp(38px, 11.4vw, 50px); line-height: .96; }
      .hero-intro { font-size: 17px; margin: 18px 0 20px; }
      .hero-actions { display: grid; grid-template-columns: 1fr; }
      .button { width: 100%; }
      .hero-device { min-height: 275px; }
      .hero-device > img { width: min(100%, 310px); opacity: .58; }
      .phone-panel { width: 94%; padding: 18px; }
      .phone-panel strong { font-size: 27px; }
      .metric-grid, .content-grid { grid-template-columns: 1fr; }
      .explain-band, .start-section, .policy-fallback, .content-grid { padding: 48px 20px; }
      .site-footer { grid-template-columns: 1fr; }
      .site-footer nav { justify-content: flex-start; }
    }
  CSS
end

def site_js
  <<~JS
    const nav = document.querySelector('[data-site-nav]');
    const button = document.querySelector('[data-menu-button]');
    if (button && nav) {
      button.addEventListener('click', () => {
        const open = nav.classList.toggle('open');
        button.setAttribute('aria-expanded', String(open));
      });
    }
    if (window.location.hash === '#/privacy') {
      window.location.replace('/privacy/');
    }
  JS
end

def headers
  <<~HEADERS
    /*
      X-Frame-Options: DENY
      X-Content-Type-Options: nosniff
      Referrer-Policy: strict-origin-when-cross-origin
      Permissions-Policy: camera=(), microphone=(), geolocation=(), payment=(), usb=(), fullscreen=(self)
      Content-Security-Policy: default-src 'self'; script-src 'self' 'unsafe-inline' https://static.cloudflareinsights.com; style-src 'self'; img-src 'self' data:; font-src 'self' data:; connect-src 'self' https://cloudflareinsights.com https://*.cloudflareinsights.com; manifest-src 'self'; object-src 'none'; base-uri 'self'; frame-ancestors 'none'; form-action 'self' mailto:; upgrade-insecure-requests

    /index.html
      Cache-Control: public, max-age=300, must-revalidate

    /
      Cache-Control: public, max-age=300, must-revalidate

    /*.html
      Cache-Control: public, max-age=300, must-revalidate

    /styles.css
      Cache-Control: public, max-age=31536000, immutable

    /site.js
      Cache-Control: public, max-age=31536000, immutable

    /manifest.json
      Cache-Control: public, max-age=3600, must-revalidate

    /assets/*
      Cache-Control: public, max-age=31536000, immutable

    /icons/*
      Cache-Control: public, max-age=31536000, immutable
  HEADERS
end

FileUtils.rm_rf(BUILD_DIR)
FileUtils.mkdir_p(BUILD_DIR)
build_lastmod = Time.now.utc.strftime("%Y-%m-%d")

unless INDEXNOW_KEY.empty? || INDEXNOW_KEY.match?(INDEXNOW_KEY_PATTERN)
  abort("PUBLIC_INDEXNOW_KEY must be 8-128 characters using A-Z, a-z, 0-9, or dashes only")
end

write_file(File.join(BUILD_DIR, "styles.css"), stylesheet)
write_file(File.join(BUILD_DIR, "site.js"), site_js)
write_file(File.join(BUILD_DIR, "_headers"), headers)
write_file(File.join(BUILD_DIR, "robots.txt"), "User-agent: *\nAllow: /\nSitemap: #{PUBLIC_URL}/sitemap.xml\n")
write_file(File.join(BUILD_DIR, "#{INDEXNOW_KEY}.txt"), "#{INDEXNOW_KEY}\n") unless INDEXNOW_KEY.empty?

assets = [
  BRAND_ASSET,
  MOMO_ASSET,
  QR_ASSET,
  ICON_ASSET
]
assets.each do |asset|
  source = File.join(ROOT, asset)
  next unless File.file?(source)

  target = File.join(BUILD_DIR, asset)
  FileUtils.mkdir_p(File.dirname(target))
  FileUtils.cp(source, target)
end

FileUtils.mkdir_p(File.join(BUILD_DIR, "icons"))
FileUtils.cp(File.join(ROOT, ICON_ASSET), File.join(BUILD_DIR, "icons", "collect.png"))

assetlinks_source = File.join(ROOT, "web", ".well-known", "assetlinks.json")
if File.file?(assetlinks_source)
  FileUtils.mkdir_p(File.join(BUILD_DIR, ".well-known"))
  FileUtils.cp(assetlinks_source, File.join(BUILD_DIR, ".well-known", "assetlinks.json"))
end

manifest = {
  "name" => "Collect by IKANISA",
  "short_name" => "Collect",
  "description" => "Credit-ready saving for Rwanda's daily economy.",
  "start_url" => "/",
  "display" => "standalone",
  "background_color" => "#050510",
  "theme_color" => "#8885F0",
  "icons" => [
    {
      "src" => "/icons/collect.png",
      "sizes" => "512x512",
      "type" => "image/png",
      "purpose" => "any maskable"
    }
  ]
}
write_file(File.join(BUILD_DIR, "manifest.json"), JSON.pretty_generate(manifest) + "\n")

all_paths = []
PAGES.each do |page|
  html = page_html(page)
  write_file(route_file(page[:path]), html)
  all_paths << page[:path]
  Array(page[:aliases]).each do |alias_path|
    alias_page = page.merge(path: alias_path)
    write_file(route_file(alias_path), page_html(alias_page, current_path: alias_path))
    all_paths << alias_path
  end
end

home_page = PAGES.first
LANGUAGES.each do |code, data|
  next if code == "en"

  localized_page = home_page.merge(
    path: data[:path],
    title: "#{data[:hero_title]} | Collect by IKANISA",
    description: data[:hero_body]
  )
  localized_data = data.merge(code: code)
  write_file(route_file(data[:path]), page_html(localized_page, current_path: data[:path], localized: localized_data))
  all_paths << data[:path]
end

sitemap_urls = all_paths.uniq.sort.map do |path|
  "  <url><loc>#{page_url(path)}</loc><lastmod>#{build_lastmod}</lastmod></url>"
end.join("\n")
write_file(
  File.join(BUILD_DIR, "sitemap.xml"),
  "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">\n#{sitemap_urls}\n</urlset>\n"
)

write_file(
  File.join(BUILD_DIR, "version.json"),
  JSON.pretty_generate(
    "name" => "collect-public-static",
    "generated_at" => Time.now.utc.iso8601,
    "routes" => all_paths.uniq.sort,
    "indexnow_key_file" => INDEXNOW_KEY.empty? ? nil : "#{INDEXNOW_KEY}.txt"
  ) + "\n"
)

puts "Prepared static public website build: #{BUILD_DIR}"
