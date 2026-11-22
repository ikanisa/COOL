# frozen_string_literal: true

require_relative "product_capabilities"
require_relative "public_legal_rendering"

module CollectPublicSite
  include CollectPublicLegalRendering

  ROOT = File.expand_path("..", __dir__)
  PRODUCT_CAPABILITIES = CollectProductCapabilities.new(ROOT)

  MEDIA_GROUP = "group"
  MEDIA_PAYMENT = "payment"
  MEDIA_SHARE = "share"

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

  def route_file(path, build_dir:)
    return File.join(build_dir, "index.html") if path == "/"
    File.join(build_dir, path.delete_prefix("/").delete_suffix("/"), "index.html")
  end

  def pages_with_aliases
    PAGES.flat_map do |page|
      [page, *Array(page[:aliases]).map { |alias_path| alias_page_for(page, alias_path) }]
    end
  end

  def write_routes(photography, public_app_screens: nil, build_dir:)
    write_file(
      File.join(build_dir, "_redirects"),
      "/c/* /group-link/?slug=:splat 302\n/invite/* /app/?publicId=:splat 302\n/privacy-request/ /account-deletion/ 302\n/cookies/ /privacy/#cookies 302\n/subprocessors/ /privacy/#sharing 302\n"
    )

    all_paths = pages_with_aliases.map do |page|
      path = page.fetch(:path)
      html = photography.prepare_html(page_html(page, public_app_screens: public_app_screens))
      write_file(route_file(path, build_dir: build_dir), html)
      path
    end

    write_file(File.join(build_dir, "c", "index.html"), share_landing_page_html(kind: :group))
    write_file(File.join(build_dir, "group-link", "index.html"), share_landing_page_html(kind: :group))
    write_file(File.join(build_dir, "app", "index.html"), share_landing_page_html(kind: :app))
    all_paths.uniq.sort
  end
end
