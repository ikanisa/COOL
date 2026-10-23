#!/usr/bin/env ruby
# frozen_string_literal: true

require "cgi"
require "fileutils"
require "json"
require "open3"
require "time"
require "yaml"
require_relative "public_app_media"
require_relative "public_photography"
require_relative "product_capabilities"
require_relative "qa/bounded_git_metadata"

ROOT = File.expand_path("..", __dir__)
PRODUCT_CAPABILITIES = CollectProductCapabilities.new(ROOT)
BUILD_DIR = File.expand_path(ENV.fetch("PUBLIC_BUILD_DIR", "build/public_web"), ROOT)
PUBLIC_URL = "https://collect.ikanisa.com"
ASSET_VERSION = PublicPhotography.asset_version(ROOT)
GOOGLE_PLAY_URL = "https://play.google.com/store/apps/details?id=app.cool.mobile"
APPLE_APP_STORE_ID = "6783960331"
APPLE_APP_STORE_URL = "https://apps.apple.com/app/id#{APPLE_APP_STORE_ID}"
APP_DOWNLOAD_URL = GOOGLE_PLAY_URL
WHATSAPP_NUMBER = "250795588248"
DISPLAY_PHONE = "+250 795 588 248"
USSD_CODE = "*182**8*1*41258*2000#"
SUPPORT_EMAIL = "info@ikanisa.com"
ACCOUNT_DELETION_PORTAL_URL = "https://api.collect.ikanisa.com/privacy/account-deletion"
PUBLIC_WEB_ANALYTICS_PRIVACY_URL = "https://developers.cloudflare.com/speed/observatory/rum-beacon/#privacy-information"
REGISTERED_ENTITY = "IKANISA Ltd."
REGULATORY_FOOTER_NOTE = PRODUCT_CAPABILITIES.copy("regulatory_footer")
ICON_ASSET = "assets/brand/collect_runtime/app_icons/app-icon-rule.png"
TYPEFACE_ASSETS = %w[
  assets/typefaces/Inter-Variable.ttf
].freeze
TYPEFACE_LICENSE = "assets/typefaces/OFL-Inter.txt"
MEDIA_GROUP = "group"
MEDIA_PAYMENT = "payment"
MEDIA_SHARE = "share"
INDEXNOW_KEY = ENV.fetch("PUBLIC_INDEXNOW_KEY", "").strip
INDEXNOW_KEY_PATTERN = /\A[A-Za-z0-9-]{8,128}\z/
LEGAL_CONTENT_DIR = File.join(ROOT, "content/legal")
LEGAL_BUNDLE = YAML.load_file(File.join(LEGAL_CONTENT_DIR, "collect_legal_pages_bundle.yaml"))
LEGAL_PRIVACY = YAML.load_file(File.join(LEGAL_CONTENT_DIR, "collect_privacy_policy.yaml")).fetch("page")
LEGAL_TERMS = YAML.load_file(File.join(LEGAL_CONTENT_DIR, "collect_terms_of_use.yaml")).fetch("page")
LEGAL_DELETE_ACCOUNT = YAML.load_file(File.join(LEGAL_CONTENT_DIR, "collect_delete_account.yaml")).fetch("page")
# September 2026 public marketing roles; native screen families stay in Flutter.
# These identity metadata colours follow the same public cohort as revolut.css.
BRAND_BLACK = "#000000"
BRAND_PAPER = "#ffffff"
BRAND_INK = "#191c1f"


PUBLIC_FAQS = PRODUCT_CAPABILITIES.faqs.freeze

PAGES = [
  {
    path: "/",
    capability_id: "group_records",
    title: "Collect by IKANISA | Microsavings and Group Savings",
    description: PRODUCT_CAPABILITIES.page("/", :description),
    h1: PRODUCT_CAPABILITIES.page("/", :h1),
    intro: PRODUCT_CAPABILITIES.page("/", :intro),
    media: MEDIA_GROUP,
    metrics: [
      ["96%", "Rwandan adults financially included"],
      ["85%", "Adults saved formally or informally"],
      ["24%", "Adults using formal borrowing"]
    ],
    sections: PRODUCT_CAPABILITIES.page("/", :sections),
  },
  {
    path: "/group-savings/",
    capability_id: "group_records",
    title: "Group Savings | Collect by IKANISA",
    description: PRODUCT_CAPABILITIES.page("/group-savings/", :description),
    h1: "Your group already has trust. Collect adds structure.",
    intro: PRODUCT_CAPABILITIES.page("/group-savings/", :intro),
    start_heading: "Give every contribution a clear purpose and a trusted record.",
    media: MEDIA_GROUP,
    nav_label: "Group Savings",
    sections: []
  },
  {
    path: "/insurance/",
    capability_id: "insurance",
    aliases: ["/protection/"],
    title: "Insurance | Collect by IKANISA",
    description: PRODUCT_CAPABILITIES.page("/insurance/", :description),
    h1: PRODUCT_CAPABILITIES.page("/insurance/", :h1),
    intro: PRODUCT_CAPABILITIES.page("/insurance/", :intro),
    media: MEDIA_PAYMENT,
    nav_label: "Insurance",
    summary_label: PRODUCT_CAPABILITIES.page("/insurance/", :summary_label),
    metrics: [
      ["Records", "Customer support"],
      ["Providers", "Final decisions"]
    ],
    infographic: {
      title: "Why current insurance misses informal earners",
      body: "Annual risks cannot always be funded with one large annual payment. Informal earners may understand the need for insurance but struggle with premiums and processes designed around regular monthly salaries. Insurers also face high costs when collecting many small payments and servicing customers outside traditional channels.",
      steps: [
        ["Premiums do not match daily cash flow", ""],
        ["Policies are difficult to understand", ""],
        ["Insurance access is concentrated in formal channels", ""],
        ["Small payments are costly to collect", ""],
        ["Claims processes can weaken trust", ""],
        ["Credit is exposed when income stops", ""]
      ]
    },
    sections_heading: PRODUCT_CAPABILITIES.page("/insurance/", :sections_heading),
    sections: PRODUCT_CAPABILITIES.page("/insurance/", :sections),
  },
  {
    path: "/craas/",
    capability_id: "credit_readiness",
    aliases: ["/credit-readiness/"],
    title: "CRaaS | Collect by IKANISA",
    description: PRODUCT_CAPABILITIES.page("/craas/", :description),
    h1: PRODUCT_CAPABILITIES.page("/craas/", :h1),
    intro: PRODUCT_CAPABILITIES.page("/craas/", :intro),
    media: MEDIA_PAYMENT,
    nav_label: "CRaaS",
    summary_label: PRODUCT_CAPABILITIES.page("/craas/", :summary_label),
    metrics: [
      ["Readiness", "File support"],
      ["Provider", "Final decision"]
    ],
    infographic: {
      title: "Payment access is widespread. Loan preparation support is not.",
      body: "Small businesses often need finance but do not know exactly what a bank requires. Many lack structured records, cash-flow forecasts, collateral evidence or the corporate documentation needed to complete a strong loan file. Preparation services are fragmented.",
      steps: [
        ["What businesses face", [
          "Unclear lender and product requirements",
          "Missing or expired documents",
          "Weak business and cash-flow records",
          "Expensive professional preparation services",
          "Rejection before full credit analysis begins"
        ]],
        ["What banks face", [
          "Incomplete files",
          "Inconsistent applicant quality",
          "Manual document checking",
          "Delayed analyst review",
          "High cost of small-business origination"
        ]]
      ]
    },
    sections_heading: PRODUCT_CAPABILITIES.page("/craas/", :sections_heading),
    sections: PRODUCT_CAPABILITIES.page("/craas/", :sections),
  },
  {
    path: "/community-groups/",
    capability_id: "group_records",
    title: "Community Groups | Collect by IKANISA",
    description: "Collect equips trusted groups with digital tools while preserving the relationships, leadership and governance that already make them work.",
    h1: "Finance works better when communities lead.",
    intro: PRODUCT_CAPABILITIES.page("/community-groups/", :intro),
    media: MEDIA_GROUP,
    nav_label: "Community Groups",
    summary_label: "Mobile group operations",
    metrics: [
      ["Group", "Member records"],
      ["Mobile app", "Group operations"]
    ],
    infographic: PRODUCT_CAPABILITIES.page("/community-groups/", :infographic),
    sections_heading: "Community use cases",
    sections: PRODUCT_CAPABILITIES.page("/community-groups/", :sections),
    supported_groups_heading: "Collect supports community groups",
    supported_groups: [
      "Community & faith: Ibimina, religious and neighbourhood associations, family savings groups",
      "Economic: Cooperatives, trade and business associations, agricultural groups, employer and professional groups",
      "Demographic: Women-led groups and youth savings groups"
    ]
  },
  {
    path: "/our-partners/",
    capability_id: "loans",
    aliases: ["/partners/"],
    title: "Our Partners | Collect by IKANISA",
    description: PRODUCT_CAPABILITIES.page("/our-partners/", :description),
    h1: "The banking opportunity in Rwanda's informal economy.",
    intro: PRODUCT_CAPABILITIES.page("/our-partners/", :intro),
    media: MEDIA_PAYMENT,
    nav_label: "Our Partners",
    summary_label: PRODUCT_CAPABILITIES.page("/our-partners/", :summary_label),
    metrics: [
      ["RWF 288B+", "Annual ibimina savings flow"],
      ["4.8M", "Informal and group savers"]
    ],
    infographic: PRODUCT_CAPABILITIES.page("/our-partners/", :infographic),
    sections: []
  },
  {
    path: "/trust/",
    aliases: ["/security/"],
    title: "Trust and Security | Collect by IKANISA",
    description: "How Collect protects personal data, supports privacy rights, and explains data, AI, partner and deletion boundaries.",
    h1: "Security and trust",
    intro: "Collect uses safeguards designed to protect personal data and gives customers clear routes to access, correct and delete eligible data.",
    media: MEDIA_SHARE,
    legal_key: :trust,
    sections: []
  },
  {
    path: "/privacy/",
    title: LEGAL_PRIVACY.dig("seo", "title"),
    description: LEGAL_PRIVACY.dig("seo", "description"),
    eyebrow: LEGAL_PRIVACY.dig("hero", "eyebrow"),
    h1: LEGAL_PRIVACY.dig("hero", "headline"),
    intro: LEGAL_PRIVACY.dig("hero", "supporting_copy"),
    media: MEDIA_SHARE,
    nav_label: LEGAL_PRIVACY.fetch("title"),
    summary_label: "Customer information",
    metrics: [
      ["Choice", "Customer control"],
      ["Delete", "Request path"]
    ],
    legal_key: :privacy,
    sections: []
  },
  {
    path: "/terms/",
    title: LEGAL_TERMS.dig("seo", "title"),
    description: LEGAL_TERMS.dig("seo", "description"),
    eyebrow: LEGAL_TERMS.dig("hero", "eyebrow"),
    h1: LEGAL_TERMS.dig("hero", "headline"),
    intro: LEGAL_TERMS.dig("hero", "supporting_copy"),
    media: MEDIA_GROUP,
    nav_label: LEGAL_TERMS.fetch("title"),
    summary_label: "Service terms",
    metrics: [
      ["Customer", "Service terms"],
      ["Clear", "Group rules"]
    ],
    legal_key: :terms,
    sections: []
  },
  {
    path: "/account-deletion/",
    title: LEGAL_DELETE_ACCOUNT.dig("seo", "title"),
    description: LEGAL_DELETE_ACCOUNT.dig("seo", "description"),
    eyebrow: LEGAL_DELETE_ACCOUNT.dig("hero", "eyebrow"),
    h1: LEGAL_DELETE_ACCOUNT.dig("hero", "headline"),
    intro: LEGAL_DELETE_ACCOUNT.dig("hero", "supporting_copy"),
    media: MEDIA_SHARE,
    nav_label: "Account deletion",
    summary_label: "Account deletion",
    metrics: [
      ["Request", "Customer control"],
      ["Review", "Required records"]
    ],
    legal_key: :account_deletion,
    sections: []
  },
  {
    path: "/data-deletion/",
    title: "Data Deletion | Collect by IKANISA",
    description: "Request deletion or anonymisation of eligible Collect personal data and understand what records may be retained.",
    eyebrow: "ACCOUNT AND DATA DELETION",
    h1: "Data deletion and retention",
    intro: "You may request deletion of eligible personal data. Some records may be retained where required by law or necessary for security, fraud prevention, disputes, regulatory compliance, or ledger integrity.",
    media: MEDIA_GROUP,
    nav_label: "Data Deletion",
    summary_label: "Data deletion",
    metrics: [
      ["Data", "Deletion request"],
      ["Support", "Customer review"]
    ],
    legal_key: :data_deletion,
    sections: []
  }
].freeze

ALIAS_PAGE_OVERRIDES = {
  "/protection/" => {
    title: "Protection | Collect by IKANISA",
    description: "Protection support pages for Collect users and groups.",
    h1: "Protection support for daily earners.",
    nav_label: "Protection"
  },
  "/credit-readiness/" => {
    title: "Credit Readiness | Collect by IKANISA",
    description: "Credit-readiness support for preparing complete, bank-review-ready files.",
    h1: "Credit-readiness support for bank-ready files.",
    nav_label: "Credit Readiness",
    sections_heading: "How credit readiness works"
  },
  "/partners/" => {
    title: "Partners | Collect by IKANISA",
    description: "A partner operating model for institutions working with Collect.",
    h1: "Partner operating model for Collect.",
    nav_label: "Partners"
  },
  "/security/" => {
    title: "Security | Collect by IKANISA",
    description: "Security, privacy, and trust controls for Collect customers and partners.",
    h1: "Security, privacy and trust controls.",
    nav_label: "Security"
  }
}.freeze

def alias_page_for(page, alias_path)
  page.merge(ALIAS_PAGE_OVERRIDES.fetch(alias_path, {})).merge(
    path: alias_path,
    canonical_path: page[:path]
  )
end

PRIMARY_NAV = [
  ["Group Savings", "/group-savings/"],
  ["Insurance", "/insurance/"],
  ["CRaaS", "/craas/"],
  ["Community Groups", "/community-groups/"],
  ["Our Partners", "/our-partners/"],
  ["Trust & Security", "/trust/"]
].freeze

def esc(value)
  CGI.escapeHTML(value.to_s)
end

def whatsapp_url(message)
  "https://wa.me/#{WHATSAPP_NUMBER}?text=#{CGI.escape(message)}"
end

def mailto_url(subject)
  "mailto:#{SUPPORT_EMAIL}?subject=#{CGI.escape(subject)}"
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
    active = current_path == href ||
      (href == "/craas/" && current_path == "/credit-readiness/") ||
      (href == "/insurance/" && current_path == "/protection/") ||
      (href == "/our-partners/" && current_path == "/partners/")
    %(<a class="nav-link#{active ? " active" : ""}" href="#{href}"#{active ? ' aria-current="page"' : ""}>#{esc(label)}</a>)
  end.join
end

def institutional_path?(path)
  ["/craas/", "/credit-readiness/", "/our-partners/", "/partners/"].include?(path)
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

def site_footer_html
  footer_whatsapp_message = "Hello IKANISA, I am contacting you from the Collect website."
  <<~HTML
    <footer class="site-footer">
      <div class="footer-identity">
        <strong>Collect by IKANISA</strong>
        <p>#{esc(REGISTERED_ENTITY)}</p>
        <p>#{esc(REGULATORY_FOOTER_NOTE)}</p>
        <p class="footer-support">Support: <a href="#{mailto_url("Collect support")}">#{esc(SUPPORT_EMAIL)}</a> <span aria-hidden="true">·</span> <a class="whatsapp-contact" href="#{whatsapp_url(footer_whatsapp_message)}"><span class="sr-only">WhatsApp</span><span>#{esc(DISPLAY_PHONE)}</span></a></p>
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

def sections_html(sections)
  sections.each_with_index.map do |section, index|
    title, body, bullets = section
    bullet_html = Array(bullets).empty? ? "" : %(
        <ul class="bullet-list">
          #{Array(bullets).map { |item| %(<li>#{esc(item)}</li>) }.join}
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

def legal_content_for(page)
  case page[:legal_key]
  when :privacy
    LEGAL_PRIVACY.merge("sections" => Array(LEGAL_PRIVACY["sections"]).map { |section| current_deletion_section(section) })
  when :terms
    LEGAL_TERMS.merge("sections" => Array(LEGAL_TERMS["sections"]).map { |section| current_deletion_terms_section(section) })
  when :account_deletion
    LEGAL_DELETE_ACCOUNT.merge(
      "delete_in_app" => current_deletion_app_content(LEGAL_DELETE_ACCOUNT["delete_in_app"]),
      "delete_without_app" => current_deletion_support_content(LEGAL_DELETE_ACCOUNT["delete_without_app"])
    )
  when :data_deletion
    {
      "title" => "Data Deletion",
      "important_notice" => LEGAL_DELETE_ACCOUNT["important_notice"],
      "sections" => [
        privacy_section("account-and-data-deletion"),
        keyed_section("What happens next", LEGAL_DELETE_ACCOUNT["what_happens_next"]),
        keyed_section("Data we may retain", LEGAL_DELETE_ACCOUNT["data_we_may_retain"]).merge("id" => "retained-data-summary"),
        keyed_section("Products provided by partners", LEGAL_DELETE_ACCOUNT["partner_products"]),
        keyed_section("Need help?", LEGAL_DELETE_ACCOUNT["contact"])
      ].compact
    }
  when :trust
    {
      "title" => "Trust and Security",
      "sections" => [
        {
          "heading" => "How Collect protects customer information",
          "body" => [
            "Collect limits access to customer data by role and reason, protects data in transit, keeps operational audit trails, and minimises raw sensitive records where possible."
          ],
          "trust_commitments" => [
            "Personal data is not sold.",
            "Customer funds are not held on Collect's own balance sheet.",
            "Banks and insurers make their own regulated decisions.",
            "Customer deletion and correction routes are available through app and support channels."
          ]
        },
        {
          "heading" => "What Collect will not do",
          "body" => [
            "Collect does not make final loan, pricing, policy or claim decisions for regulated providers, and it does not expose private credit-readiness documents to group members."
          ],
          "trust_commitments" => [
            "No public training of private customer financial documents.",
            "No sale of personal data.",
            "No public promise of automatic credit, insurance or payout approval.",
            "No unrestricted access to sensitive support records."
          ]
        },
        {
          "heading" => "Partner and regulated-product boundary",
          "body" => [
            "Collect supports records, preparation, communication and customer-requested workflows. Licensed banks, insurers or approved providers remain responsible for their own KYC, AML/CFT, eligibility, pricing, approval, disbursement, claim and regulatory obligations."
          ],
          "trust_commitments" => [
            "Provider review remains separate from Collect public marketing copy.",
            "Funds are handled through regulated financial-service partners where approved arrangements apply.",
            "Partner handoff requires an appropriate legal basis and customer workflow."
          ]
        },
        {
          "heading" => "Customer rights and deletion support",
          "body" => [
            "Customers can request access, correction, account deletion or data deletion. Some ledger, security, dispute, payment, tax, audit, legal or regulatory records may need limited retention."
          ],
          "trust_commitments" => [
            "Use the in-app account deletion request where available.",
            "Contact WhatsApp support at +250 795 588 248.",
            "Email info@ikanisa.com for privacy or deletion questions.",
            "Support can confirm request status and explain retained record categories."
          ]
        }
      ].compact
    }
  end
end

def privacy_section(id)
  current_deletion_section(Array(LEGAL_PRIVACY["sections"]).find { |section| section["id"] == id })
end

def current_deletion_app_content(content)
  canonical = LEGAL_DELETE_ACCOUNT.fetch("delete_in_app")
  content.merge(
    "path" => canonical.fetch("path"),
    "steps" => canonical.fetch("steps")
  )
end

def current_deletion_support_content(content)
  canonical = LEGAL_DELETE_ACCOUNT.fetch("delete_without_app")
  content.merge(
    "copy" => canonical.fetch("copy"),
    "email" => canonical.fetch("email")
  )
end

def current_deletion_terms_section(section)
  return section unless section.is_a?(Hash) && section["id"] == "closing-or-deleting"

  section.merge("request_channels" => Array(section["request_channels"]).map do |channel|
    channel.start_with?("In the app under ") ? "In the app under #{LEGAL_DELETE_ACCOUNT.fetch("delete_in_app").fetch("path")}" : channel
  end)
end

def current_deletion_section(section)
  return section unless section.is_a?(Hash) && section["id"] == "account-and-data-deletion"

  section.merge("subsections" => Array(section["subsections"]).map do |subsection|
    case subsection["heading"]
    when "Delete your account in the Collect app"
      current_deletion_app_content(subsection)
    when "Request deletion without the app"
      support = current_deletion_support_content(subsection)
      support.merge(
        "id" => subsection.fetch("id"),
        "body" => support["copy"]
      ).reject { |key, _| key == "copy" }
    else
      subsection
    end
  end)
end

def keyed_section(heading, content)
  return nil unless content.is_a?(Hash)

  content.merge("heading" => heading)
end

def legal_label(key)
  key.to_s.tr("_", " ").split.map(&:capitalize).join(" ")
end

def legal_value_html(value)
  case value
  when String, Numeric
    text = value.to_s.strip
    return "" if text.empty?

    %(<p>#{esc(text)}</p>)
  when Array
    legal_array_html(value)
  when Hash
    legal_hash_html(value)
  else
    ""
  end
end

def legal_array_html(items)
  items = Array(items).compact
  return "" if items.empty?

  if items.all? { |item| item.is_a?(String) || item.is_a?(Numeric) }
    %(<ul class="bullet-list">#{items.map { |item| %(<li>#{esc(item)}</li>) }.join}</ul>)
  else
    %(<div class="legal-card-grid">#{items.map { |item| legal_hash_card_html(item) }.join}</div>)
  end
end

def legal_hash_card_html(item)
  return %(<article class="legal-card">#{legal_value_html(item)}</article>) unless item.is_a?(Hash)

  title = item["title"] || item["heading"] || item["label"] || item["name"]
  body_parts = item.reject { |key, _| %w[id title heading label name type required options].include?(key.to_s) }
  <<~HTML
    <article class="legal-card">
      #{title ? %(<h3>#{esc(title)}</h3>) : ""}
      #{body_parts.map { |key, value| legal_named_value_html(key, value) }.join}
    </article>
  HTML
end

def legal_hash_html(hash)
  heading = hash["heading"] || hash["title"]
  body = hash.reject { |key, _| %w[heading title].include?(key.to_s) || legal_internal_key?(key) }
  seen_contacts = {}
  body = body.reject do |key, value|
    next false unless legal_contact_key?(key) && value.is_a?(String)

    duplicate = seen_contacts[value.strip]
    seen_contacts[value.strip] = true
    duplicate
  end
  <<~HTML
    #{heading ? %(<h3>#{esc(heading)}</h3>) : ""}
    #{body.map { |key, value| legal_named_value_html(key, value) }.join}
  HTML
end

def legal_details_html(details)
  seen = {}
  rows = details.reject { |key, value| legal_internal_key?(key) || %w[heading title].include?(key.to_s) || value.to_s.strip.empty? }.map do |key, value|
    label = legal_contact_key?(key) ? "Email" : key.to_s == "privacy_request" ? "Privacy requests" : legal_label(key)
    dedupe_key = [label, value.to_s.strip]
    next if seen[dedupe_key]

    seen[dedupe_key] = true
    href = %w[subprocessor_link privacy_request link cookie_policy_link].include?(key.to_s) ? normalized_legal_href(value) : nil
    content = if legal_contact_key?(key)
      legal_email_html(value)
    elsif href
      %(<a class="legal-inline-link" href="#{esc(href)}">#{esc(legal_inline_link_label(key, href))}</a>)
    else
      esc(value)
    end
    %(<dt>#{esc(label)}</dt><dd>#{content}</dd>)
  end.compact
  return "" if rows.empty?

  %(<dl class="legal-details">#{rows.join}</dl>)
end

def legal_contact_key?(key)
  %w[email privacy_email support_email general_support privacy complaints partnerships].include?(key.to_s)
end

def legal_email_html(value)
  %(<a class="legal-inline-link" href="mailto:#{esc(value)}">#{esc(value)}</a>)
end

def legal_named_value_html(key, value)
  return "" if legal_internal_key?(key) || value.nil? || value.respond_to?(:empty?) && value.empty?
  return %(<p><strong>Email:</strong> #{legal_email_html(value)}</p>) if legal_contact_key?(key) && !value.is_a?(Hash) && !value.is_a?(Array)

  case key.to_s
  when "heading"
    ""
  when "body"
    Array(value).map { |item| %(<p>#{esc(item)}</p>) }.join
  when "intro", "closing", "risk_statement", "trust_statement", "important_notice",
       "service_target", "copy", "clarification", "zero_fee_clarification",
       "non_exclusion", "priority_rule"
    %(<p>#{esc(value)}</p>)
  when "details"
    legal_details_html(value)
  when "delete_without_app"
    heading = value["heading"] || value["title"]
    body = legal_hash_html(value)
    original = %(<h3>#{esc(heading)}</h3>)
    raise "Expected one outside-app deletion heading" unless heading && body.scan(original).length == 1

    linked = %(<h3><a class="legal-inline-link" href="#{ACCOUNT_DELETION_PORTAL_URL}">#{esc(heading)}</a></h3>)
    %(<div>#{body.sub(original, linked)}</div>)
  when "contact"
    heading = value["heading"] || value["title"]
    %(<div>#{heading ? %(<h3>#{esc(heading)}</h3>) : ""}#{legal_details_html(value)}</div>)
  when "bullets", "steps", "uses", "not_final_decision_for", "additional_terms_may_include",
       "availability_may_be_limited_by", "collect_does_not_guarantee",
       "member_obligations", "group_leader_obligations", "transaction_may_remain_subject_to",
       "collect_may_support", "credit_readiness_is_not", "providers_may_include",
       "pre_acceptance_information", "partner_lender_controls", "insurer_controls",
       "where_available", "fees_may_include", "acceptable_use", "may_apply_to",
       "request_channels", "before_deletion_you_may_need_to", "deletion_does_not_cancel",
       "availability_may_be_affected_by", "not_constitute",
       "to_extent_permitted_collect_not_responsible_for", "updates_may_reflect",
       "trust_commitments"
    legal_array_html(value)
  when "subsections"
    Array(value).map { |section| legal_section_html(section) }.join
  when "links"
    legal_links_html(value)
  when "subprocessor_link", "link", "cookie_policy_link", "privacy_request"
    legal_inline_link_html(key, value)
  when "support_information"
    %(<h3>#{esc(value.fetch("heading"))}</h3><p>#{esc(value.fetch("copy"))}</p>#{legal_form_fields_html(value.fetch("fields"))})
  when "path"
    %(<p><span class="legal-path">#{esc(value)}</span></p>)
  when "fields"
    legal_form_fields_html(value)
  else
    if value.is_a?(Array)
      %(<h3>#{esc(legal_label(key))}</h3>#{legal_array_html(value)})
    elsif value.is_a?(Hash)
      %(<div>#{value["heading"] || value["title"] ? "" : %(<h3>#{esc(legal_label(key))}</h3>)}#{legal_hash_html(value)}</div>)
    else
      %(<p><strong>#{esc(legal_label(key))}:</strong> #{esc(value)}</p>)
    end
  end
end

def normalized_legal_href(value)
  href = value.to_s.strip
  return href if href == mailto_url("Collect privacy request")
  return nil unless href.start_with?("/") && !href.start_with?("//")

  path, fragment = href.split("#", 2)
  path = "#{path}/" unless path.end_with?("/")
  fragment ? "#{path}##{fragment}" : path
end

def legal_inline_link_html(key, value)
  href = normalized_legal_href(value)
  return %(<p><strong>#{esc(legal_label(key))}:</strong> #{esc(value)}</p>) unless href

  label = legal_inline_link_label(key, href)
  %(<p><a class="legal-inline-link" href="#{esc(href)}">#{esc(label)}</a></p>)
end

def legal_inline_link_label(key, href)
  case key.to_s
  when "subprocessor_link" then "Read about service providers and data sharing"
  when "privacy_request" then "Email #{SUPPORT_EMAIL} about a privacy request"
  when "cookie_policy_link" then "Read the cookie and website technology notice"
  when "link"
    if href.start_with?("/account-deletion/")
      "Open the account-deletion page"
    elsif href == "/privacy/#cookies"
      "Read about cookies and website analytics"
    else
      "Open the referenced page"
    end
  else
    "Open the referenced page"
  end
end

def legal_internal_key?(key)
  %w[id slug seo hero legal_review_note must_be_finalised_for].include?(key.to_s)
end

def legal_links_html(links)
  items = links.map do |label, href|
    href_display = normalized_legal_href(href)
    content = href_display ? %(<a href="#{esc(href_display)}">#{esc(legal_label(label))}</a>) : esc(legal_label(label))
    %(<li>#{content}</li>)
  end
  %(<ul class="bullet-list">#{items.join}</ul>)
end

def legal_form_fields_html(fields)
  cards = Array(fields).map do |field|
    label = field["label"] || legal_label(field["name"])
    required = case field["required"]
    when true then "Required"
    when false then "Optional"
    end
    options = Array(field["options"])
    <<~HTML
      <article class="legal-card">
        <h3>#{esc(label)}</h3>
        #{required ? %(<p>#{esc(required)} field.</p>) : ""}
        #{options.empty? ? "" : legal_array_html(options)}
      </article>
    HTML
  end.join
  %(<div class="legal-card-grid">#{cards}</div>)
end

# Public-hosting disclosure belongs to this website renderer, not the shared app policy.
def public_web_analytics_disclosure_html
  <<~HTML
    <p>Collect's public website uses Cloudflare Web Analytics to measure page usage and performance. It sends page and referring-page addresses, a temporary page-load identifier, browser information and performance measurements to Cloudflare.</p>
    <p>Cloudflare states that the analytics script does not read or write cookies or browser storage. This is separate from the authentication and security technologies listed above. <a class="legal-inline-link" href="#{PUBLIC_WEB_ANALYTICS_PRIVACY_URL}">Read Cloudflare's RUM privacy information</a>.</p>
  HTML
end

def legal_section_html(section, public_privacy: false)
  return "" unless section.is_a?(Hash)

  heading = section["heading"] || section["title"] || legal_label(section["id"])
  anchor = section["id"].to_s.strip
  anchor = heading.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-+\z/, "") if anchor.empty?
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
  return "" if page && [:privacy, :terms, :trust].include?(page[:legal_key])

  sections = Array(content["sections"]).select { |section| section.is_a?(Hash) }
  links = sections.first(14).map do |section|
    heading = section["heading"] || section["title"] || legal_label(section["id"])
    anchor = section["id"].to_s.strip
    anchor = heading.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-+\z/, "") if anchor.empty?
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
  no_sidebar = page && [:privacy, :terms, :trust].include?(page[:legal_key])
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
      items.empty? ? "" : %(<ul>#{items.map { |item| %(<li>#{esc(item)}</li>) }.join}</ul>)
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

def home_credit_readiness_html
  <<~HTML
    <section class="market-context" aria-labelledby="market-context-heading">
      <div>
        <p class="section-kicker">Finance built around real income</p>
        <h2 id="market-context-heading">People earn daily. Finance still works monthly.</h2>
        <p>Around 90% of employment in Rwanda is informal. Many people earn small, irregular amounts each day, while conventional savings, credit and insurance products are structured around monthly salaries, larger deposits and lump-sum repayments.</p>
      </div>
      <div class="market-grid" aria-label="Source-backed Rwanda financial inclusion context">
        <article><strong>96%</strong><span>Rwandan adults financially included</span></article>
        <article><strong>85%</strong><span>Adults saved formally or informally</span></article>
        <article><strong>72%</strong><span>Adults using informal mechanisms</span></article>
        <article><strong>24%</strong><span>Adults using formal borrowing</span></article>
      </div>
    </section>
  HTML
end

def original_home_sections_html
  <<~HTML
    <section class="original-story home-journey" aria-labelledby="daily-rhythm-heading">
      <div class="story-copy">
        <h2 id="daily-rhythm-heading">#{esc(PRODUCT_CAPABILITIES.detail("home_journey_heading"))}</h2>
      </div>
      <div class="journey-rail" aria-label="Collect contribution journey">
        #{PRODUCT_CAPABILITIES.detail("home_journey").each_with_index.map { |(title, body), index| %(<article><span>#{format("%02d", index + 1)}</span><strong>#{esc(title)}</strong><p>#{esc(body)}</p></article>) }.join}
      </div>
    </section>

    <section class="original-story" aria-labelledby="ibimina-heading">
      <div class="story-copy">
        <h2 id="ibimina-heading">Everything Collect brings together</h2>
      </div>
      <div class="story-grid four home-product-grid">
        #{PRODUCT_CAPABILITIES.detail("home_products").map { |title, body, href, label| %(<article><strong>#{esc(title)}</strong><span>#{esc(body)}</span><a href="#{esc(href)}">#{esc(label)}</a></article>) }.join}
      </div>
    </section>

    <section class="original-story" aria-labelledby="rwanda-community-heading">
      <div class="story-copy">
        <h2 id="rwanda-community-heading">Built for people who earn, save, and borrow differently</h2>
      </div>
      <div class="story-grid four">
        <article><strong>Ibimina</strong><span>Rotating and accumulating groups that need readable activity records.</span></article>
        <article><strong>Daily earners</strong><span>People saving in small amounts around daily or irregular income.</span></article>
        <article><strong>MSMEs</strong><span>#{esc(PRODUCT_CAPABILITIES.detail("msme_summary"))}</span></article>
      </div>
    </section>

    <section class="original-story" aria-labelledby="credit-boundary-heading">
      <div class="story-copy">
        <h2 id="credit-boundary-heading">Payments work. Financial progress still does not.</h2>
      </div>
      <div class="story-grid problem-grid">
        <article><strong>Daily-income mismatch</strong><span>90% of employment is informal, yet finance is designed around monthly salaries and lump-sum payments.</span></article>
        <article><strong>Invisible group savings</strong><span>52% of adults save through ibimina, but many records remain manual and cannot support formal credit.</span></article>
        <article><strong>Credit-readiness gap</strong><span>Rwanda has extensive payment agents, but no scalable last-mile service helping MSMEs prepare complete, bank-ready loan files.</span></article>
        <article><strong>Microinsurance gap</strong><span>Premiums and claims processes rarely match small, irregular daily incomes.</span></article>
      </div>
    </section>
  HTML
end

def group_savings_page_html
  how_steps = PRODUCT_CAPABILITIES.detail("group_how_steps")
  features = PRODUCT_CAPABILITIES.detail("group_features")
  use_cases = [
    "Business working-capital readiness",
    "Insurance and compliance savings",
    "School-fee and family goals",
    "Agricultural inputs and equipment",
    "Property and construction",
    "Moto-taxi insurance and licensing",
    "Green mobility and productive assets",
    "Emergency and resilience funds"
  ]

  <<~HTML
    <section class="group-problem-section" aria-labelledby="group-problems-heading">
      <div class="story-copy">
        <h2 id="group-problems-heading">Trusted savings should not remain invisible.</h2>
        <p>Many groups still depend on cash, notebooks, spreadsheets, WhatsApp messages or one person's mobile-money account. This makes reconciliation difficult, weakens transparency and prevents years of savings discipline from becoming a recognised financial record.</p>
      </div>
      <div class="problem-list compact" aria-label="What groups struggle with today">
        <article>Manual contribution tracking</article>
        <article>Missing or disputed records</article>
        <article>Cash-handling and fraud risk</article>
        <article>No independent member statements</article>
        <article>Capital repeatedly distributed rather than accumulated</article>
        <article>Limited visibility for banks and other partners</article>
      </div>
    </section>

    <section class="group-workflow-section" aria-labelledby="group-workflow-heading">
      <div class="story-copy">
        <h2 id="group-workflow-heading">How Collect works</h2>
      </div>
      <div class="journey-rail group-journey" aria-label="Group savings workflow">
        #{how_steps.each_with_index.map { |(title, body), index| %(<article><span>#{format("%02d", index + 1)}</span><strong>#{esc(title)}</strong><p>#{esc(body)}</p></article>) }.join}
      </div>
    </section>

    <section class="group-feature-section" aria-labelledby="group-features-heading">
      <div class="story-copy">
        <h2 id="group-features-heading">Features for groups that save together</h2>
      </div>
      <div class="story-grid four group-feature-grid">
        #{features.map { |(title, body)| %(<article><strong>#{esc(title)}</strong><span>#{esc(body)}</span></article>) }.join}
      </div>
    </section>

    <section class="group-accumulation-section" aria-labelledby="group-accumulation-heading">
      <div class="story-copy">
        <h2 id="group-accumulation-heading">From rotation to accumulation - keep the trust, grow the capital.</h2>
      </div>
      <div class="accumulation-panel">
        <p>#{esc(PRODUCT_CAPABILITIES.detail("accumulation_summary"))}</p>
        <strong>Each group chooses its rules.</strong>
        <span>Collect does not force groups to abandon their existing culture or governance.</span>
      </div>
    </section>

    <section class="group-use-section" aria-labelledby="group-use-heading">
      <div class="story-copy">
        <h2 id="group-use-heading">Do more with your group savings.</h2>
      </div>
      <div class="use-case-grid" aria-label="Group savings use cases">
        #{use_cases.map { |item| %(<article>#{esc(item)}</article>) }.join}
      </div>
    </section>
  HTML
end

def insurance_page_html
  how_steps = PRODUCT_CAPABILITIES.detail("insurance_how_steps")

  <<~HTML
    <section class="insurance-work-section" aria-labelledby="insurance-work-heading">
      <div class="story-copy">
        <h2 id="insurance-work-heading">Proposed journey, not an available service</h2>
      </div>
      <div class="insurance-step-grid" aria-label="Insurance product journey">
        #{how_steps.each_with_index.map { |body, index| %(<article><span>#{format("%02d", index + 1)}</span><p>#{esc(body)}</p></article>) }.join}
      </div>
    </section>

    <section class="insurance-finance-section" aria-labelledby="insurance-finance-heading">
      <div class="story-copy">
        <p class="section-kicker">Premium finance</p>
        <h2 id="insurance-finance-heading">Protection should not lapse because today's balance is short.</h2>
      </div>
      <div class="premium-finance-panel">
        <p>#{esc(PRODUCT_CAPABILITIES.detail("premium_finance"))}</p>
      </div>
    </section>
  HTML
end

def craas_page_html
  specialist_services = [
    "Accounting",
    "Business plan",
    "Tax advisory",
    "Notaries",
    "Legal services",
    "Insurers",
    "Collateral documents",
    "Property valuation"
  ]

  bank_receives = [
    "Business profile summary",
    "Loan request summary",
    "Product-specific checklist",
    "Indexed document folder",
    "Financial evidence summary",
    "Repayment and cash-flow notes",
    "KYC/KYB support file",
    "Identified gaps and next steps",
    "Readiness review",
    "Draft credit memo and working note"
  ]

  business_benefits = [
    "Clearer requirements",
    "Less confusion",
    "Fewer unnecessary visits",
    "Better file quality",
    "Greater confidence",
    "Faster handoff to a lender"
  ]

  bank_benefits = [
    "Less administrative rework",
    "More consistent files",
    "Faster pre-credit preparation",
    "Better productivity",
    "Improved applicant experience"
  ]

  <<~HTML
    <section class="craas-specialist-section" aria-labelledby="craas-specialist-heading">
      <div class="story-copy">
        <h2 id="craas-specialist-heading">#{esc(PRODUCT_CAPABILITIES.detail("craas_specialist_heading"))}</h2>
      </div>
      <div class="craas-service-grid" aria-label="Specialist support services">
        #{specialist_services.map { |item| %(<article><strong>#{esc(item)}</strong></article>) }.join}
      </div>
    </section>

    <section class="craas-bank-section" aria-labelledby="craas-bank-heading">
      <div class="story-copy">
        <h2 id="craas-bank-heading">#{esc(PRODUCT_CAPABILITIES.detail("craas_bank_heading"))}</h2>
      </div>
      <div class="craas-list-panel">
        <ul>
          #{bank_receives.map { |item| %(<li>#{esc(item)}</li>) }.join}
        </ul>
      </div>
    </section>

    <section class="craas-benefits-section" aria-labelledby="craas-benefits-heading">
      <div class="story-copy">
        <h2 id="craas-benefits-heading">#{esc(PRODUCT_CAPABILITIES.detail("craas_benefits_heading"))}</h2>
      </div>
      <div class="craas-benefit-grid">
        <article>
          <h3>For businesses</h3>
          <ul>
            #{business_benefits.map { |item| %(<li>#{esc(item)}</li>) }.join}
          </ul>
        </article>
        <article>
          <h3>For banks</h3>
          <ul>
            #{bank_benefits.map { |item| %(<li>#{esc(item)}</li>) }.join}
          </ul>
        </article>
      </div>
    </section>
  HTML
end

def partner_page_html
  opportunity_metrics = [
    ["RWF 288B+", "Annual ibimina savings flow"],
    ["4.8M", "Informal and group savers"],
    ["94,000", "Savings groups nationwide"],
    ["90.4%", "Employment operating informally"]
  ]
  list_html = lambda do |items|
    return "" if Array(items).empty?

    %(<ul>#{Array(items).map { |item| %(<li>#{esc(item)}</li>) }.join}</ul>)
  end

  deposit_mobilisation = [
    "Daily and periodic microsavings"
  ]

  daily_income_lending = [
    "Daily or periodic micro-repayments",
    "Earlier visibility of repayment stress"
  ]

  collect_provides = PRODUCT_CAPABILITIES.detail("partner_collect_provides")

  bank_provides = [
    "Regulated savings accounts and account operations",
    "KYC, KYB and AML/CFT controls",
    "Credit assessment and pricing",
    "Loan disbursement"
  ]

  bank_value = [
    "Growth in low-cost deposits",
    "New retail and MSME customers",
    "Increased loan origination",
    "Reduced pre-credit administration"
  ]

  <<~HTML
    <section class="partner-opportunity-section" aria-labelledby="partner-opportunity-heading">
      <div class="story-copy">
        <h2 id="partner-opportunity-heading">A large savings and credit market already exists, mostly outside formal banking.</h2>
      </div>
      <div class="partner-metric-grid" aria-label="Banking opportunity metrics">
        #{opportunity_metrics.map { |value, label| %(<article><strong#{value.include?("RWF") ? ' class="currency-value"' : ""}>#{esc(value)}</strong><span>#{esc(label)}</span></article>) }.join}
      </div>
    </section>

    <section class="partner-market-section" aria-labelledby="partner-growth-heading">
      <div class="story-copy">
        <h2 id="partner-growth-heading">Prospective opportunities for licensed providers</h2>
        <p>#{esc(PRODUCT_CAPABILITIES.detail("partner_engine_intro"))}</p>
      </div>
      <div class="partner-engine-grid" aria-label="Growth engines for partner banks">
        <article>
          <strong>Low-cost deposit mobilisation</strong>
          <p>#{esc(PRODUCT_CAPABILITIES.detail("partner_deposits"))}</p>
          #{list_html.call(deposit_mobilisation)}
        </article>
        <article>
          <strong>Daily-income lending and repayment</strong>
          <p>#{esc(PRODUCT_CAPABILITIES.detail("partner_lending"))}</p>
          #{list_html.call(daily_income_lending)}
        </article>
        <article>
          <strong>Rwanda group savings records</strong>
          <p>#{esc(PRODUCT_CAPABILITIES.detail("partner_records"))}</p>
        </article>
        <article>
          <strong>Stronger MSME credit origination</strong>
          <p>#{esc(PRODUCT_CAPABILITIES.detail("partner_credit_readiness"))}</p>
        </article>
      </div>
    </section>

    <section class="partner-operating-section" aria-labelledby="partner-operating-heading">
      <div class="story-copy">
        <h2 id="partner-operating-heading">What each side brings</h2>
      </div>
      <div class="partner-operating-grid">
        <article>
          <h3>#{esc(PRODUCT_CAPABILITIES.detail("partner_collect_heading"))}</h3>
          #{list_html.call(collect_provides)}
        </article>
        <article>
          <h3>#{esc(PRODUCT_CAPABILITIES.detail("partner_bank_heading"))}</h3>
          #{list_html.call(bank_provides)}
        </article>
        <article>
          <h3>#{esc(PRODUCT_CAPABILITIES.detail("partner_value_heading"))}</h3>
          <p>#{esc(PRODUCT_CAPABILITIES.detail("partner_value_intro"))}</p>
          #{list_html.call(bank_value)}
        </article>
      </div>
    </section>
  HTML
end

def hero_visual_html(page)
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
  media = (@public_app_media ||= PublicAppMedia.new(ROOT)).screens.fetch(id)
  <<~HTML
    <figure class="app-capture" data-app-screen="#{esc(id)}">
      <img src="#{esc(media.fetch('url'))}" alt="#{esc(media.fetch('alt'))}" width="#{media.fetch('width')}" height="#{media.fetch('height')}" fetchpriority="high">
      <figcaption>#{media.fetch('capture_kind') == 'browser_flutter_fixture' ? 'Collect interface preview' : 'Collect app'} · Example data</figcaption>
    </figure>
  HTML
end

def page_html(page, current_path: page[:path])
  <<~HTML
    <!doctype html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>#{esc(page[:title])}</title>
      <meta name="description" content="#{esc(page[:description])}">
      <meta name="theme-color" content="#{BRAND_BLACK}">
      <link rel="canonical" href="#{page_url(current_path)}">
      #{alternate_links(current_path)}
      <link rel="icon" href="/icons/collect.png" type="image/png">
      <link rel="manifest" href="/manifest.json">
      <meta property="og:type" content="website">
      <meta property="og:locale" content="en_US">
      <meta property="og:url" content="#{page_url(current_path)}">
      <meta property="og:title" content="#{esc(page[:title])}">
      <meta property="og:description" content="#{esc(page[:description])}">
      <meta property="og:image" content="#{PUBLIC_URL}/icons/collect.png">
      <meta name="twitter:card" content="summary_large_image">
      <meta name="twitter:title" content="#{esc(page[:title])}">
      <meta name="twitter:description" content="#{esc(page[:description])}">
      <link rel="stylesheet" href="/styles.css?v=#{ASSET_VERSION}">
      <link rel="stylesheet" href="/sections.css?v=#{ASSET_VERSION}">
      <link rel="stylesheet" href="/revolut.css?v=#{ASSET_VERSION}">
      <script type="application/ld+json">#{json_ld(page)}</script>
    </head>
    <body class="#{esc(page_classes(page, current_path))}">
      <a class="skip-link" href="#content">Skip to content</a>
      <header class="site-header">
        <a class="brand" href="/">
          <img src="/icons/collect.png" alt="" width="42" height="42">
          <span><strong>Collect</strong><small>by IKANISA</small></span>
        </a>
        <button class="menu-button" type="button" data-menu-button aria-expanded="false" aria-controls="site-nav">Menu</button>
        <nav id="site-nav" class="site-nav" data-site-nav aria-label="Main navigation">
          #{nav_html(current_path)}
          <div class="mobile-menu-actions">#{cta_links_html(current_path, page, surface: :hero)}</div>
        </nav>
        <div class="header-actions">
          #{cta_links_html(current_path, page, surface: :header)}
        </div>
      </header>

      <main id="content">
        <section class="hero #{page[:legal_key] ? "legal-hero" : ""}">
          <div class="hero-copy">
            #{page[:eyebrow] ? %(<p class="hero-eyebrow">#{esc(page[:eyebrow])}</p>) : ""}
            <h1>#{esc(page[:h1])}</h1>
            <p class="hero-intro">#{esc(page[:intro])}</p>
            <div class="hero-actions">
              #{cta_links_html(current_path, page, surface: :hero)}
            </div>
          </div>
          #{current_path == "/" ? '<img class="hero-editorial" src="/assets/marketing/rwanda/kigali-woman-hero.png" alt="" width="1672" height="941" fetchpriority="high">' : "<div class=\"hero-device\">#{hero_visual_html(page)}</div>"}
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
    "This privacy-safe link takes you to the exact group after sign-in. If you are new to Collect, the invitation is retained while you finish onboarding."
  else
    "Continue in the native Collect app. If Collect is not installed, use the official store for this phone."
  end
  native_link = group_link ? "collect://group/shared-group" : "collect://app"
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
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>#{esc(title)}</title>
      <meta name="description" content="#{esc(description)}">
      <meta name="robots" content="noindex, nofollow">
      <meta name="theme-color" content="#{BRAND_BLACK}">
      <meta name="apple-itunes-app" content="app-id=#{APPLE_APP_STORE_ID}, app-argument=#{PUBLIC_URL}#{canonical_path}" data-share-smart-banner>
      <link rel="canonical" href="#{PUBLIC_URL}#{canonical_path}" data-share-canonical>
      <link rel="icon" href="/icons/collect.png" type="image/png">
      <link rel="manifest" href="/manifest.json">
      <meta property="og:type" content="website">
      <meta property="og:locale" content="en_US">
      <meta property="og:url" content="#{PUBLIC_URL}#{canonical_path}" data-share-og-url>
      <meta property="og:title" content="#{esc(title)}">
      <meta property="og:description" content="#{esc(description)}">
      <meta property="og:image" content="#{PUBLIC_URL}/icons/collect.png">
      <meta name="twitter:card" content="summary_large_image">
      <link rel="stylesheet" href="/styles.css?v=#{ASSET_VERSION}">
      <link rel="stylesheet" href="/sections.css?v=#{ASSET_VERSION}">
      <link rel="stylesheet" href="/revolut.css?v=#{ASSET_VERSION}">
      <script type="application/ld+json">#{share_schema}</script>
    </head>
    <body class="revolut-public route-share-link" data-share-landing="#{group_link ? "group" : "app"}">
      <a class="skip-link" href="#content">Skip to content</a>
      <header class="site-header">
        <a class="brand" href="/">
          <img src="/icons/collect.png" alt="" width="42" height="42">
          <span><strong>Collect</strong><small>by IKANISA</small></span>
        </a>
        <button class="menu-button" type="button" data-menu-button aria-expanded="false" aria-controls="site-nav">Menu</button>
        <nav id="site-nav" class="site-nav" data-site-nav aria-label="Public website">
          <a class="nav-link" href="/group-savings/">Group Savings</a>
          <a class="nav-link" href="/trust/">Trust &amp; Security</a>
          <div class="mobile-menu-actions"><a class="button primary" href="#{GOOGLE_PLAY_URL}" data-collect-store-link>Get Collect</a></div>
        </nav>
        <div class="header-actions">
          <a class="button secondary" href="#{GOOGLE_PLAY_URL}" data-collect-store-link>Get Collect</a>
        </div>
      </header>

      <main id="content">
        <section class="hero share-link-hero">
          <div class="hero-copy">
            <p class="hero-eyebrow">Shared Collect link</p>
            <h1 data-share-heading>#{esc(heading)}</h1>
            <p class="hero-intro">#{esc(intro)}</p>
            <p class="share-link-code" data-share-code#{group_link ? "" : " hidden"}>Secure group invitation</p>
            #{group_link ? '<p class="share-link-validity">Collect confirms the invitation after sign-in. Expired, revoked or invalid links cannot join a group.</p>' : ''}
            <div class="hero-actions">
              <a class="button primary" href="#{native_link}" data-collect-open-link>Open in Collect</a>
              <a class="button ghost" href="#{GOOGLE_PLAY_URL}" data-collect-store-link>Get Collect</a>
              <button class="button ghost" type="button" data-collect-copy-link>Copy link</button>
            </div>
            <p class="share-link-store-options">
              <a href="#{APPLE_APP_STORE_URL}" aria-label="Get Collect on the Apple App Store">App Store</a>
              <span aria-hidden="true">&middot;</span>
              <a href="#{GOOGLE_PLAY_URL}" aria-label="Get Collect on Google Play">Google Play</a>
            </p>
            <p class="share-link-status" data-share-status role="status" aria-live="polite"></p>
          </div>
          <div class="hero-device">
            <div class="hero-widget share-link-widget" aria-label="Collect shared link preview">
              <img src="/icons/collect.png" alt="" width="72" height="72">
              <span>#{group_link ? "COLLECT GROUP LINK" : "COLLECT APP LINK"}</span>
              <strong>Private details stay in the app.</strong>
              <p>Receiver numbers, raw payment messages and member phone numbers are never placed in this public link.</p>
            </div>
          </div>
        </section>
        <section class="start-section" aria-labelledby="share-link-help-heading">
          <div>
            <h2 id="share-link-help-heading">#{group_link ? "A link that survives onboarding" : "Continue in the Collect app"}</h2>
          </div>
          <div>
            <p>#{group_link ? "Collect retains the invitation link for up to 24 hours on the device, then joins only after the member signs in and the backend confirms that the invitation is current." : "Open Collect if it is installed, or use the store link for this device to install the app. Group invitations are confirmed separately after sign-in."}</p>
            <p>Having a link does not expose payment credentials or confirm a payment.</p>
          </div>
        </section>
      </main>

      #{site_footer_html}
      <script src="/site.js?v=#{ASSET_VERSION}" defer></script>
    </body>
    </html>
  HTML
end

def stylesheet
  File.read(File.join(ROOT, "web/public/layout.css"))
end

def minify_css(css)
  # Whitespace before pseudo-classes can be a descendant combinator, and
  # calc() operators require surrounding spaces. Keep both intact.
  css
    .gsub(%r{/\*.*?\*/}m, "")
    .gsub(/\s+/, " ")
    .gsub(/\s*([{};,])\s*/, "\\1")
    .gsub(/;}/, "}")
    .gsub(/\b0+\./, ".")
    .gsub(/(:|\s)0(px|rem|em|%)/, "\\10")
    .gsub("#ffffff", "#fff")
    .strip
end

def split_stylesheets(css)
  section_prefixes = %w[
    content-grid infographic infographic-step supported-groups section-card bullet-list legal-
    group-problem group-workflow group-feature group-accumulation group-use
    problem-list use-case-grid group-journey journey-rail accumulation-panel
    change-compare insurance-work insurance-finance
    insurance-step premium-finance craas- partner- story-grid.five story-grid.six
    story-grid market-grid source-note home-flow section-number localized-
    protection-card readiness-card community-card partner-card
    trust-card policy-card terms-card deletion-card data-card
    activity-list app-list app-segments corridor-map faq-list home-app-card
    ledger- member- proof-grid protection-item record-card shield-mark
    statement- supported-group workflow-stack
  ]
  sections_css = []
  core_lines = []
  media_stack = []

  css.each_line do |line|
    stripped = line.strip
    if stripped.start_with?("@media") && stripped.end_with?("{")
      media_stack << { line: line, core_open: false, section_open: false }
      next
    end

    if media_stack.any? && stripped == "}"
      frame = media_stack.pop
      core_lines << "}\n" if frame[:core_open]
      sections_css << "}\n" if frame[:section_open]
      next
    end

    selector = stripped.split("{", 2).first.to_s
    section_rule = section_prefixes.any? do |prefix|
      selector.include?(".#{prefix}") || selector.include?(prefix)
    end

    if media_stack.any?
      frame = media_stack.last
      if section_rule
        unless frame[:section_open]
          sections_css << frame[:line]
          frame[:section_open] = true
        end
        sections_css << line
      else
        unless frame[:core_open]
          core_lines << frame[:line]
          frame[:core_open] = true
        end
        core_lines << line
      end
    elsif section_rule
      sections_css << line
    else
      core_lines << line
    end
  end

  [minify_css(core_lines.join), minify_css(sections_css.join)]
end

def site_js
  <<~JS
    const homeHeader = document.querySelector('.route-home .site-header');
    const homeHero = document.querySelector('.route-home .hero');
    if (homeHeader && homeHero) {
      let headerFrame = 0;
      const syncHeader = () => {
        headerFrame = 0;
        homeHeader.classList.toggle('on-light',
          homeHero.getBoundingClientRect().bottom <= homeHeader.getBoundingClientRect().bottom);
      };
      const scheduleHeader = () => {
        if (!headerFrame) headerFrame = requestAnimationFrame(syncHeader);
      };
      window.addEventListener('scroll', scheduleHeader, { passive: true });
      window.addEventListener('resize', scheduleHeader);
      syncHeader();
    }
    const nav = document.querySelector('[data-site-nav]');
    const button = document.querySelector('[data-menu-button]');
    if (button && nav) {
      const setMenu = (open, returnFocus = false) => {
        nav.classList.toggle('open', open);
        document.body.classList.toggle('menu-open', open);
        button.setAttribute('aria-expanded', String(open));
        button.textContent = open ? 'Close' : 'Menu';
        document.querySelectorAll('main, .site-footer').forEach((element) => {
          element.inert = open;
        });
        if (open) nav.querySelector('a')?.focus();
        else if (returnFocus) button.focus();
      };
      button.addEventListener('click', () => setMenu(!nav.classList.contains('open')));
      document.addEventListener('keydown', (event) => {
        if (!nav.classList.contains('open')) return;
        if (event.key === 'Escape') {
          event.preventDefault();
          setMenu(false, true);
        }
        if (event.key === 'Tab') {
          const controls = [button, ...nav.querySelectorAll('a[href], button')];
          const first = controls[0], last = controls[controls.length - 1];
          if (event.shiftKey && document.activeElement === first) {
            event.preventDefault(); last.focus();
          } else if (!event.shiftKey && document.activeElement === last) {
            event.preventDefault(); first.focus();
          }
        }
      });
      nav.addEventListener('click', (event) => {
        if (event.target.closest('a')) setMenu(false);
      });
      window.addEventListener('resize', () => {
        if (window.innerWidth > 1100) setMenu(false);
      });
    }
    if (window.location.hash === '#/privacy') {
      window.location.replace('/privacy/');
    }
    const shareLanding = document.querySelector('[data-share-landing]');
    if (shareLanding) {
      const segments = window.location.pathname.split('/').filter(Boolean);
      const search = new URLSearchParams(window.location.search);
      const kind = shareLanding.dataset.shareLanding;
      const pathSlug = segments.length === 2 && segments[0].toLowerCase() === 'c'
        ? segments[1]
        : null;
      const pathInviteId = segments.length === 2 && segments[0].toLowerCase() === 'invite'
        ? segments[1]
        : null;
      const slug = kind === 'group' ? (pathSlug || search.get('slug') || '').toLowerCase() : null;
      const inviteId = kind === 'app' ? (pathInviteId || search.get('publicId')) : null;
      const openLink = document.querySelector('[data-collect-open-link]');
      const code = document.querySelector('[data-share-code]');
      const heading = document.querySelector('[data-share-heading]');
      const status = document.querySelector('[data-share-status]');
      const canonical = document.querySelector('[data-share-canonical]');
      const ogUrl = document.querySelector('[data-share-og-url]');
      const smartBanner = document.querySelector('[data-share-smart-banner]');
      const googlePlayUrl = '#{GOOGLE_PLAY_URL}';
      const appleAppStoreUrl = '#{APPLE_APP_STORE_URL}';
      const userAgent = navigator.userAgent || '';
      const platform = navigator.userAgentData?.platform || navigator.platform || '';
      const isIPadOS = platform === 'MacIntel' && navigator.maxTouchPoints > 1;
      const isIOS = /iPad|iPhone|iPod/i.test(userAgent) || isIPadOS;
      const isAndroid = /Android/i.test(userAgent);
      const storeUrl = isIOS ? appleAppStoreUrl : googlePlayUrl;
      const storeLabel = isIOS ? 'Get on the App Store' : isAndroid ? 'Get it on Google Play' : 'Get Collect';
      document.querySelectorAll('[data-collect-store-link]').forEach((link) => {
        link.href = storeUrl;
        link.textContent = storeLabel;
        link.setAttribute('aria-label', isIOS
          ? 'Get Collect on the Apple App Store'
          : isAndroid
          ? 'Get Collect on Google Play'
          : 'Get Collect for this device');
      });
      const safeSlug = slug && slug.length <= 140 && /^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(slug) ? slug : null;
      const safeInviteId = inviteId && /^[A-Za-z0-9_-]{1,64}$/.test(inviteId) ? inviteId : null;
      if (kind === 'group') {
        if (safeSlug) {
          openLink.href = `collect://group/${encodeURIComponent(safeSlug)}`;
          code.textContent = `Group link: ${safeSlug}`;
        } else {
          openLink.removeAttribute('href');
          openLink.setAttribute('aria-disabled', 'true');
          code.textContent = 'This group link is invalid.';
          status.textContent = 'Ask the group member to share a new link.';
        }
      } else if (safeInviteId) {
        openLink.href = `collect://invite/${encodeURIComponent(safeInviteId)}`;
        heading.textContent = 'Join someone you know on Collect';
      } else {
        openLink.href = 'collect://app';
      }
      const exactPath = kind === 'group' && safeSlug
        ? `/c/${encodeURIComponent(safeSlug)}`
        : kind === 'app' && safeInviteId
        ? `/invite/${encodeURIComponent(safeInviteId)}`
        : window.location.pathname;
      const exactUrl = `${window.location.origin}${exactPath}`;
      if (canonical) canonical.href = exactUrl;
      if (ogUrl) ogUrl.content = exactUrl;
      if (smartBanner) {
        smartBanner.content = `app-id=#{APPLE_APP_STORE_ID}, app-argument=${exactUrl}`;
      }
      if (openLink && openLink.hasAttribute('href')) {
        openLink.addEventListener('click', () => {
          if (!isIOS && !isAndroid) return;
          const startedAt = Date.now();
          window.setTimeout(() => {
            const stillHere = document.visibilityState === 'visible' && Date.now() - startedAt < 3000;
            if (stillHere) window.location.assign(storeUrl);
          }, 1400);
        });
      }
      const copyButton = document.querySelector('[data-collect-copy-link]');
      if (copyButton) {
        copyButton.addEventListener('click', async () => {
          try {
            await navigator.clipboard.writeText(exactUrl);
            status.textContent = 'Link copied.';
          } catch (_) {
            status.textContent = 'Copy the link from your browser address bar.';
          }
        });
      }
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
      Content-Security-Policy: default-src 'self'; script-src 'self' 'unsafe-inline' https://static.cloudflareinsights.com; style-src 'self'; img-src 'self' data:; font-src 'self' data:; connect-src 'self' https://cloudflareinsights.com https://*.cloudflareinsights.com; manifest-src 'self'; object-src 'none'; base-uri 'self'; frame-ancestors 'none'; form-action 'self'; upgrade-insecure-requests

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

    /sections.css
      Cache-Control: public, max-age=31536000, immutable

    /manifest.json
      Cache-Control: public, max-age=3600, must-revalidate

    /assets/*
      Cache-Control: public, max-age=31536000, immutable

    /icons/*
      Cache-Control: public, max-age=31536000, immutable

  HEADERS
end

def public_build_destination_mode(destination, source_root:, allowed_roots:, explicit_path:)
  internal = allowed_roots.any? do |allowed_root|
    destination.start_with?("#{allowed_root}#{File::SEPARATOR}")
  end
  if !internal && (destination == source_root || destination.start_with?(source_root + File::SEPARATOR))
    raise ArgumentError, "Repository PUBLIC_BUILD_DIR must be inside build or .cache"
  end
  unless internal || (explicit_path && explicit_path.start_with?(File::SEPARATOR) &&
                      explicit_path == destination && explicit_path == File.expand_path(explicit_path))
    raise ArgumentError, "External PUBLIC_BUILD_DIR must be an explicit absolute path"
  end

  # Never traverse a symlink while replacing a build or claiming a new output.
  cursor = File::SEPARATOR
  destination.split(File::SEPARATOR).reject(&:empty?).each do |part|
    cursor = File.join(cursor, part)
    raise ArgumentError, "PUBLIC_BUILD_DIR contains a symlink" if File.symlink?(cursor)
    if File.exist?(cursor) && !File.directory?(cursor)
      raise ArgumentError, "PUBLIC_BUILD_DIR contains a non-directory"
    end
  end
  return :replace_internal if internal

  # An external release directory must be new. Never recursively remove an
  # arbitrary destination supplied through the environment.
  if File.exist?(destination)
    raise ArgumentError, "External PUBLIC_BUILD_DIR already exists; choose a new release directory"
  end
  unless File.directory?(File.dirname(destination))
    raise ArgumentError, "External PUBLIC_BUILD_DIR requires an existing parent directory"
  end
  :create_external
end

def prepare_public_build_directory(destination, mode)
  if mode == :replace_internal
    FileUtils.rm_rf(destination)
    FileUtils.mkdir_p(destination)
  elsif mode == :create_external
    # mkdir fails if another process claimed this path after validation.
    Dir.mkdir(destination)
  else
    raise ArgumentError, "Unknown public build destination mode"
  end
end

def copy_public_well_known(source_root, build_root)
  source_directory = File.join(source_root, "web", ".well-known")
  return unless Dir.exist?(source_directory)

  target_directory = File.join(build_root, ".well-known")
  FileUtils.mkdir_p(target_directory)
  Dir.children(source_directory).sort.each do |entry|
    next if entry.start_with?("._") || entry == ".DS_Store"

    source = File.join(source_directory, entry)
    next unless File.file?(source)

    FileUtils.cp(source, File.join(target_directory, entry))
  end
end

allowed_build_roots = [File.join(ROOT, "build"), File.join(ROOT, ".cache")]
begin
  destination_mode = public_build_destination_mode(
    BUILD_DIR, source_root: ROOT, allowed_roots: allowed_build_roots, explicit_path: ENV["PUBLIC_BUILD_DIR"]
  )
rescue ArgumentError => error
  abort(error.message)
end
# Validate screenshot freshness before replacing a previously usable build.
public_app_media = PublicAppMedia.new(ROOT)
public_app_screens = public_app_media.screens
photography = PublicPhotography.new(ROOT)
photography.photos
unless INDEXNOW_KEY.empty? || INDEXNOW_KEY.match?(INDEXNOW_KEY_PATTERN)
  abort("PUBLIC_INDEXNOW_KEY must be 8-128 characters using A-Z, a-z, 0-9, or dashes only")
end
begin
  # Recheck the path after input validation, before any output is replaced.
  public_build_destination_mode(
    BUILD_DIR, source_root: ROOT, allowed_roots: allowed_build_roots, explicit_path: ENV["PUBLIC_BUILD_DIR"]
  )
  prepare_public_build_directory(BUILD_DIR, destination_mode)
rescue ArgumentError, SystemCallError => error
  abort(error.message)
end
build_lastmod = Time.now.utc.strftime("%Y-%m-%d")

core_stylesheet, section_stylesheet = split_stylesheets(stylesheet)
write_file(File.join(BUILD_DIR, "styles.css"), core_stylesheet)
write_file(File.join(BUILD_DIR, "sections.css"), section_stylesheet)
write_file(File.join(BUILD_DIR, "revolut.css"), photography.prepare_css(File.read(File.join(ROOT, "web/public/revolut.css"))))
write_file(File.join(BUILD_DIR, "site.js"), site_js)
write_file(File.join(BUILD_DIR, "_headers"), headers)
write_file(
  File.join(BUILD_DIR, "_redirects"),
  "/c/* /group-link/?slug=:splat 302\n/invite/* /app/?publicId=:splat 302\n/privacy-request/ /account-deletion/ 302\n/cookies/ /privacy/#cookies 302\n/subprocessors/ /privacy/#sharing 302\n"
)
write_file(File.join(BUILD_DIR, "robots.txt"), "User-agent: *\nAllow: /\nSitemap: #{PUBLIC_URL}/sitemap.xml\n")
write_file(File.join(BUILD_DIR, "#{INDEXNOW_KEY}.txt"), "#{INDEXNOW_KEY}\n") unless INDEXNOW_KEY.empty?

assets = [
  ICON_ASSET,
  *TYPEFACE_ASSETS,
  TYPEFACE_LICENSE,
  *Dir.glob("assets/marketing/rwanda/*.png", base: ROOT)
]
assets.each do |asset|
  source = File.join(ROOT, asset)
  next unless File.file?(source)

  target = File.join(BUILD_DIR, asset)
  FileUtils.mkdir_p(File.dirname(target))
  FileUtils.cp(source, target)
end
photography.copy_to(BUILD_DIR)

public_app_screens.each_value do |media|
  target = File.join(BUILD_DIR, media.fetch("url").delete_prefix("/"))
  FileUtils.mkdir_p(File.dirname(target))
  FileUtils.cp(media.fetch("source"), target)
end

FileUtils.mkdir_p(File.join(BUILD_DIR, "icons"))
FileUtils.cp(File.join(ROOT, ICON_ASSET), File.join(BUILD_DIR, "icons", "collect.png"))

copy_public_well_known(ROOT, BUILD_DIR)

manifest = {
  "name" => "Collect by IKANISA",
  "short_name" => "Collect",
  "description" => "Microsavings and group savings for daily earners.",
  "start_url" => "/",
  "display" => "standalone",
  "background_color" => BRAND_BLACK,
  "theme_color" => BRAND_BLACK,
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
  html = photography.prepare_html(page_html(page))
  write_file(route_file(page[:path]), html)
  all_paths << page[:path]
  Array(page[:aliases]).each do |alias_path|
    alias_page = alias_page_for(page, alias_path)
    write_file(route_file(alias_path), photography.prepare_html(page_html(alias_page, current_path: alias_path)))
    all_paths << alias_path
  end
end

write_file(File.join(BUILD_DIR, "c", "index.html"), share_landing_page_html(kind: :group))
write_file(File.join(BUILD_DIR, "group-link", "index.html"), share_landing_page_html(kind: :group))
write_file(File.join(BUILD_DIR, "app", "index.html"), share_landing_page_html(kind: :app))


sitemap_urls = all_paths.uniq.sort.map do |path|
  "  <url><loc>#{page_url(path)}</loc><lastmod>#{build_lastmod}</lastmod></url>"
end.join("\n")
write_file(
  File.join(BUILD_DIR, "sitemap.xml"),
  "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">\n#{sitemap_urls}\n</urlset>\n"
)

source_metadata = BoundedGitMetadata.observe(ROOT)
write_file(
  File.join(BUILD_DIR, "version.json"),
  JSON.pretty_generate(
    "name" => "collect-public-static",
    "generated_at" => Time.now.utc.iso8601,
    "source_commit" => source_metadata.fetch("source_commit"),
    "source_dirty" => source_metadata.fetch("source_dirty"),
    "source_git_status" => source_metadata.fetch("source_git_status"),
    "source_git_status_error" => source_metadata.fetch("source_git_status_error"),
    "routes" => all_paths.uniq.sort,
    "share_routes" => ["/c/:slug", "/app", "/invite/:publicId"],
    "indexnow_key_file" => INDEXNOW_KEY.empty? ? nil : "#{INDEXNOW_KEY}.txt"
  ) + "\n"
)

puts "Prepared static public website build: #{BUILD_DIR}"
