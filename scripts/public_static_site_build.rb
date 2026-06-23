#!/usr/bin/env ruby
# frozen_string_literal: true

require "cgi"
require "fileutils"
require "json"
require "time"

ROOT = File.expand_path("..", __dir__)
BUILD_DIR = File.expand_path(ENV.fetch("PUBLIC_BUILD_DIR", "build/public_web"), ROOT)
PUBLIC_URL = "https://collect.ikanisa.com"
APP_DOWNLOAD_URL = "https://play.google.com/store/apps/details?id=app.cool.mobile"
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
  ["Group Savings", "/group-savings/"],
  ["Diaspora", "/diaspora/"],
  ["Insurance", "/insurance/"],
  ["CRaaS", "/craas/"],
  ["Community Groups", "/community-groups/"],
  ["Impact", "/impact/"],
  ["Our Partners", "/our-partners/"]
].freeze

PAGES = [
  {
    path: "/",
    title: "Collect by IKANISA | Microsavings and Group Savings",
    description: "Collect helps daily earners and savings groups organize microsavings, daily savings, ledgers, credit-readiness support, and provider-review files through a public app and supported USSD journeys.",
    h1: "Microsavings and group savings for daily earners",
    intro: "Collect helps ibimina, community groups, and daily earners turn daily savings into capital accumulation, clearer ledgers, credit-readiness support files, and access to loans.",
    asset: BRAND_ASSET,
    metrics: [
      ["96%", "Rwandan adults financially included"],
      ["85%", "Adults saved formally or informally"],
      ["24%", "Adults using formal borrowing"]
    ],
    sections: [
      ["Microsavings and daily savings", "Support small, regular contributions for people who earn daily and save in practical amounts.", ["Daily earners", "Supported USSD paths", "Low-friction records"]],
      ["Group savings", "Set up a savings group, organize members and roles, and keep contribution activity easier to review.", ["Group setup", "Member roles", "Contribution history"]],
      ["Credit-readiness support", "Prepare contribution history, documents, and request summaries before a financial provider reviews the file.", ["Readiness files", "Missing-item support", "Provider review boundary"]],
      ["Access to capital and loans", "Organize records that may support capital-access and loan conversations with the relevant provider.", ["Provider-review files", "Capital access preparation", "No approval promise"]],
      ["Microinsurance support", "Keep insurance-related records organized where approved providers are involved.", ["Protection records", "Support history", "Provider decision boundary"]],
      ["Diaspora credit and collateral support", "Prepare group savings records for diaspora credit or group savings collateral support discussions, where a provider review is required.", ["Diaspora preparation", "Group savings collateral support", "Provider decision boundary"]]
    ]
  },
  {
    path: "/group-savings/",
    title: "Group Savings | Collect by IKANISA",
    description: "Digitise group savings contributions, give every member a clear record, and grow accumulated group capital that financial institutions can understand.",
    eyebrow: "Group Savings",
    h1: "Your group already has trust. Collect adds structure.",
    intro: "Digitise contributions, give every member a clear record and grow accumulated group capital that financial institutions can understand.",
    start_heading: "Give every contribution a clear purpose and a trusted record.",
    asset: BRAND_ASSET,
    nav_label: "Group Savings",
    sections: []
  },
  {
    path: "/diaspora/",
    title: "Diaspora Savings | Collect by IKANISA",
    description: "Diaspora groups can organize savings records and prepare information for Rwanda-focused discussions.",
    h1: "Diaspora group savings records",
    intro: "Diaspora groups can organize savings records and prepare information for Rwanda-focused discussions.",
    asset: QR_ASSET,
    nav_label: "Diaspora",
    summary_label: "Diaspora group records",
    metrics: [
      ["Group records", "Member contributions"],
      ["Preparation", "Rwanda discussions"]
    ],
    infographic: {
      title: "Diaspora savings pathway",
      body: "Save across borders with clearer rules and records.",
      steps: [
        ["Form the group", "Members agree roles, rules and saving objectives."],
        ["Track contributions", "Savings history is organized into readable group records."],
        ["Prepare information", "Members keep the records needed for discussion and support."],
        ["Discuss next steps", "Any financial-service decision remains with the relevant provider."]
      ]
    },
    sections: [
      ["Diaspora group structure", "Give members a shared record before decisions are made.", ["Rules and roles", "Member balances", "Contribution statements"]],
      ["Readable contribution history", "Keep savings activity easier to review and explain.", ["Group records", "Member summaries", "Support notes"]],
      ["Rwanda-focused preparation", "Prepare cleaner information for future Rwanda discussions.", ["Purpose notes", "Member requests", "Supporting records"]],
      ["Clear communication", "Keep members aligned with fewer side conversations.", ["Member visibility", "Support channel", "Request-ready records"]]
    ]
  },
  {
    path: "/insurance/",
    aliases: ["/protection/"],
    title: "Insurance | Collect by IKANISA",
    description: "Collect can help organize insurance-related records where approved providers are involved.",
    h1: "Insurance record support",
    intro: "Collect can help organize insurance-related records where approved providers are involved.",
    asset: MOMO_ASSET,
    nav_label: "Insurance",
    summary_label: "Insurance support records",
    metrics: [
      ["Records", "Customer support"],
      ["Providers", "Final decisions"]
    ],
    infographic: {
      title: "Insurance support workflow",
      body: "Keep customer records clearer when an approved provider is involved.",
      steps: [
        ["Customer request", "Understand the insurance-related question."],
        ["Record support", "Organize relevant customer and group records."],
        ["Provider review", "Approved providers review under their own rules."],
        ["Support follow-up", "IKANISA support helps customers understand next steps."]
      ]
    },
    sections: [
      ["Organize insurance-related records", "Keep relevant customer, group and contribution details easier to review.", ["Customer details", "Contribution history", "Support notes"]],
      ["Support approved provider workflows", "Collect supports records and communication; providers remain responsible for product decisions.", ["Provider review", "Customer follow-up", "Decision boundaries"]],
      ["Avoid unclear promises", "The website does not say IKANISA issues policies or pays insurance benefits.", ["Records only", "Provider decisions", "WhatsApp support"]],
      ["Cleaner customer support", "Keep the savings and insurance-support context together when customers ask questions.", ["Member records", "Support history", "Clear next steps"]]
    ]
  },
  {
    path: "/craas/",
    aliases: ["/credit-readiness/"],
    title: "CRaaS | Collect by IKANISA",
    description: "Collect helps customers organize documents, contribution history, and request summaries before a provider review.",
    h1: "Credit Readiness as a Service",
    intro: "Collect helps customers organize documents, contribution history, and request summaries before a provider review.",
    asset: MOMO_ASSET,
    nav_label: "CRaaS",
    summary_label: "Credit-readiness service",
    metrics: [
      ["Readiness", "File support"],
      ["Provider", "Final decision"]
    ],
    infographic: {
      title: "From inquiry to support file",
      body: "Turn customer activity into a cleaner readiness file.",
      steps: [
        ["Inquiry", "Understand the customer need."],
        ["File support", "Organize records and missing items."],
        ["Readiness notes", "Prepare a clear customer summary."],
        ["Provider review", "Credit decisions remain with the financial provider."]
      ]
    },
    sections: [
      ["Prepare before asking for credit", "Organize the customer story before the credit conversation.", ["Customer profile", "Loan purpose", "Missing-document support"]],
      ["Use Collect records as proof", "Show discipline through real saving and group records.", ["Savings discipline", "Group participation", "Protection context"]],
      ["Human support to complete the file", "Help customers close gaps before they submit.", ["Checklist support", "Customer summary", "WhatsApp help"]],
      ["Clear next step", "Prepare a cleaner file for review.", ["Organized records", "Customer summary", "Provider decision"]]
    ]
  },
  {
    path: "/community-groups/",
    title: "Community Groups | Collect by IKANISA",
    description: "A mobile app for trusted groups that save, contribute and support members.",
    h1: "Community groups as distribution infrastructure",
    intro: "A mobile app for trusted groups that save, contribute and support members.",
    asset: BRAND_ASSET,
    nav_label: "Community Groups",
    summary_label: "Mobile group operations",
    metrics: [
      ["Group", "Member records"],
      ["Mobile app", "Group operations"]
    ],
    infographic: {
      title: "What the app enables for a group",
      body: "Give trusted groups a simple mobile operating layer.",
      steps: [
        ["Join", "Enter the group from a link or QR code."],
        ["Save", "Contribute and follow the group record."],
        ["Track", "See member activity and progress."],
        ["Support", "Get help without exposing private data."]
      ]
    },
    sections: [
      ["Member app", "A simple place to join, contribute and follow progress.", ["Join groups", "Track contributions", "Use Collect ID"]],
      ["Leader support", "Give group leaders cleaner records for meetings and follow-up.", ["Member activity", "Group sharing", "Meeting records"]],
      ["Member journey", "Reduce confusion after a member contributes.", ["Join", "Contribute", "Follow status"]],
      ["Trusted group support", "Use groups as trusted channels for saving and support.", ["Local trust", "Customer help", "Reusable records"]]
    ]
  },
  {
    path: "/impact/",
    title: "Impact | Collect by IKANISA",
    description: "Impact content for Collect is limited to source-backed public facts and customer-facing outcomes.",
    h1: "Impact through clearer savings records",
    intro: "Collect describes impact through customer-facing outcomes and source-backed public facts only.",
    asset: BRAND_ASSET,
    nav_label: "Impact",
    summary_label: "Source-backed public facts",
    metrics: [
      ["Records", "Group visibility"],
      ["Files", "Better prepared requests"]
    ],
    infographic: {
      title: "Impact chain",
      body: "Collect keeps public impact claims tied to sourced facts and customer-facing outcomes.",
      steps: [
        ["Group records", "Cleaner contribution histories."],
        ["Support files", "Better prepared customer requests."],
        ["Provider boundaries", "Credit and insurance decisions remain with providers."],
        ["Source register", "Public numbers require separate source evidence."]
      ]
    },
    sections: [
      ["Cleaner group records", "Savings groups can keep clearer member and contribution records.", ["Member histories", "Treasurer visibility", "Meeting-ready statements"]],
      ["Better prepared support requests", "Customers can organize documents, contribution history and request summaries before review.", ["Customer summary", "Contribution history", "Missing-item checklist"]],
      ["Careful public claims", "Published numbers require a source register before they appear on the website.", ["Public source URL", "Source owner and date", "Exact approved wording"]],
      ["Decision boundaries", "Collect prepares records and support files. Providers make financial-service decisions under their own rules.", ["Credit provider review", "Approved insurance provider review", "WhatsApp support"]]
    ]
  },
  {
    path: "/our-partners/",
    aliases: ["/partners/"],
    title: "Our Partners | Collect by IKANISA",
    description: "Collect works with approved organizations that need clearer savings-group records and customer support files.",
    h1: "Our Partners",
    intro: "Collect works with approved organizations that need clearer savings-group records and customer support files.",
    asset: MOMO_ASSET,
    nav_label: "Our Partners",
    summary_label: "Partner support model",
    metrics: [
      ["Records", "Customer preparation"],
      ["Support", "WhatsApp inquiries"]
    ],
    infographic: {
      title: "Partner support workflow",
      body: "The public website names no partner discussions unless separately approved.",
      steps: [
        ["Customer need", "A group or customer asks for support."],
        ["Collect records", "Contribution history and request context are organized."],
        ["Provider review", "The relevant organization reviews under its own rules."],
        ["Support follow-up", "IKANISA helps with questions and next steps."]
      ]
    },
    sections: [
      ["Financial-service providers", "Collect can help customers prepare clearer records before a provider review.", ["Contribution history", "Customer summary", "Provider decision boundary"]],
      ["Cooperatives and savings groups", "Groups can use Collect to keep member activity and contribution records easier to review.", ["Group setup", "Member records", "Treasurer visibility"]],
      ["Community organizations", "Organizations can direct customers to the app and WhatsApp support for questions.", ["Public app download", "WhatsApp inquiries", "Support follow-up"]],
      ["Careful partner claims", "The website does not publish partner names, discussions or regulatory claims without separate approval.", ["No unapproved names", "No discussion claims", "Source-backed wording only"]]
    ]
  },
  {
    path: "/trust/",
    aliases: ["/security/"],
    title: "Trust and Security | Collect by IKANISA",
    description: "How Collect handles records, privacy, deletion, support, and careful fintech claims.",
    h1: "Trust starts with clear records and careful claims",
    intro: "Collect keeps contribution records, support paths, and data-handling boundaries visible. Public product, partner, regulator, credit, and insurance claims are made only when approved.",
    asset: QR_ASSET,
    sections: [
      ["Data minimization", "Collect uses identity, contact, Collect ID, group, contribution, payment reference, customer choice, and support data only for the service and requested workflows."],
      ["Deletion and correction", "Customers can request account deletion, data deletion, or correction through the app or WhatsApp after ownership verification."],
      ["Dispute and support path", "IKANISA support can review account, group, contribution, and payment-reference questions through approved support channels."],
      ["Provider decisions", "Collect prepares records. Credit, insurance, and provider decisions remain with the relevant provider under their own rules."]
    ]
  },
  {
    path: "/privacy/",
    title: "Privacy Policy and Data Deletion | Collect by IKANISA",
    description: "How Collect handles customer information, account deletion requests, and data deletion requests.",
    h1: "Privacy Policy and Data Deletion",
    intro: "Collect protects customer information with clear customer choices, limited access, practical safeguards, and account and data deletion request paths for savings, support, credit-readiness and insurance journeys.",
    asset: QR_ASSET,
    nav_label: "Privacy Policy",
    summary_label: "Customer information",
    metrics: [
      ["Choice", "Customer control"],
      ["Delete", "Request path"]
    ],
    sections: [
      ["Information we collect", "Collect may collect information needed to create and support an account, operate savings groups, keep contribution records, verify support requests, and prepare customer-requested credit-readiness or insurance records.", ["Identity, contact, Collect ID and account details provided by the customer", "Group membership, roles, rules, contribution activity and payout records", "Payment references, support messages, service choices and service notifications", "Camera or image inputs only when a customer uses a QR, support, or evidence feature"]],
      ["How information is used", "Customer information is used to operate Collect, maintain group records, support savings workflows, prepare records customers request, protect accounts, prevent misuse, and respond to customer support or deletion requests.", ["Operate app, WhatsApp, support and group workflows", "Prepare savings, contribution, credit-readiness and insurance support records", "Protect accounts, prevent misuse, investigate disputes and support recovery", "Improve reliability, customer support and service quality"]],
      ["Sharing and service providers", "Collect does not sell customer personal data. Information may be shared only when needed to operate the service, support customer requests, process payment or support workflows, meet legal obligations, or work with service providers under appropriate controls.", ["Payment, messaging, hosting, analytics, security and support service providers", "Banks, insurers, cooperatives, group leaders or partners only when required for a customer-requested workflow", "Authorities, auditors or dispute handlers where legally required"]],
      ["Security and retention", "Collect uses access controls, transport security and operational safeguards to protect customer information. Records are kept only as long as needed for the service, customer support, security, audit, dispute, payment reconciliation, tax, legal or regulatory reasons.", ["Data is protected in transit and access is limited by role", "Raw sensitive records are minimized where possible", "Ledger, security, dispute, payment and legal records may be retained where required"]],
      ["Account deletion request", "Customers can request deletion of their Collect account and associated account data from inside the app or from this public web resource without reinstalling the app.", ["In app: Settings, then account deletion request", "WhatsApp: +250 795 588 248 with the phone number or Collect ID connected to the account", "IKANISA may verify account ownership before processing the request"]],
      ["Data deletion and correction request", "Customers can also ask IKANISA to delete or correct personal data that is no longer needed for Collect. When an app account is deleted, associated user data is deleted unless limited retention is required for legitimate security, fraud-prevention, ledger, dispute, payment, audit, tax, legal or regulatory reasons.", ["Request deletion or correction by app or WhatsApp", "Support reviews open groups, unresolved payments and required records", "Support can confirm request status and explain retained record categories"]],
      ["Customer choices and contact", "Customers can ask privacy questions, request access, correction, account deletion or data deletion, and get support through IKANISA contact channels.", ["WhatsApp: +250 795 588 248", "Website: https://collect.ikanisa.com/#/privacy"]]
    ]
  },
  {
    path: "/terms/",
    title: "Terms of Service | Collect by IKANISA",
    description: "How customers use Collect services.",
    h1: "Terms of Service",
    intro: "These terms explain how customers use Collect for group savings, contribution records, credit-readiness support, insurance-related support records and customer service.",
    asset: BRAND_ASSET,
    nav_label: "Terms of Service",
    summary_label: "Service terms",
    metrics: [
      ["Customer", "Service terms"],
      ["Clear", "Group rules"]
    ],
    sections: [
      ["Using Collect", "Customers are responsible for providing accurate information, following their group rules and using Collect only for lawful savings, contribution and support activities.", ["Keep account and group information accurate", "Use app and WhatsApp channels responsibly", "Follow savings group rules approved by members"]],
      ["Savings, credit-readiness and insurance support", "Collect helps customers keep records, organize group savings, prepare credit-readiness files and organize insurance-related support records. Final credit decisions remain with the chosen credit provider.", ["Collect records contributions and group activity", "CRaaS prepares customer files before provider review", "Insurance-related records support customer questions"]],
      ["Support and contact", "Customers can contact IKANISA on WhatsApp for group savings setup, account support, questions or inquiries about these terms.", ["WhatsApp: +250 795 588 248", "Support for group savings setup"]]
    ]
  },
  {
    path: "/account-deletion/",
    title: "Account Deletion | Collect by IKANISA",
    description: "Request account deletion from Collect.",
    h1: "Account Deletion",
    intro: "Collect customers can request account deletion from the app or by contacting IKANISA support.",
    asset: QR_ASSET,
    nav_label: "Account Deletion",
    summary_label: "Account deletion",
    metrics: [
      ["Request", "Customer control"],
      ["Review", "Required records"]
    ],
    infographic: {
      title: "Customer deletion request",
      body: "Request deletion in app or through IKANISA support.",
      steps: []
    },
    sections: [
      ["How to request deletion", "Open Collect settings and use the account deletion request option, or contact IKANISA support on WhatsApp if you cannot access the app.", ["In app: Settings, then account deletion request", "WhatsApp: +250 795 588 248"]],
      ["What happens next", "Support reviews the request, verifies account ownership where needed and starts deletion for account data that is no longer required to provide the service.", ["Access and profile data are reviewed", "Open groups or payment issues may need resolution first", "Support can confirm request status"]],
      ["Records we may retain", "Some ledger, security, dispute, payment and legal records may be retained where required for audit, fraud prevention, customer support or legal compliance.", ["Savings ledger records needed for group accountability", "Security and abuse-prevention records", "Legal, tax, audit or dispute records"]]
    ]
  },
  {
    path: "/data-deletion/",
    title: "Data Deletion | Collect by IKANISA",
    description: "Ask IKANISA to delete or correct Collect personal data that is no longer needed for the service.",
    h1: "Data Deletion",
    intro: "Customers can ask IKANISA to delete or correct personal data that is no longer needed for Collect.",
    asset: BRAND_ASSET,
    nav_label: "Data Deletion",
    summary_label: "Data deletion",
    metrics: [
      ["Data", "Deletion request"],
      ["Support", "Customer review"]
    ],
    infographic: {
      title: "Data deletion request",
      body: "Ask support to delete or correct data that is no longer needed.",
      steps: []
    },
    sections: [
      ["Submit a data deletion request", "Use the in-app account deletion request, or contact IKANISA support on WhatsApp with the phone number or Collect ID connected to your account.", ["In app: Settings, then account deletion request", "WhatsApp: +250 795 588 248"]],
      ["Data covered by the request", "Requests may cover profile details, support messages, service choices and other account data that Collect no longer needs to operate the service.", ["Account and contact details", "Support and service records", "Service data no longer needed for active groups"]],
      ["Limited retention", "Collect may retain limited records where needed for audit, group ledger integrity, security, disputes, payment reconciliation or legal obligations.", ["Ledger records needed by groups", "Fraud prevention and security records", "Legal, tax, audit or dispute records"]]
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
    active = current_path == href ||
      (href == "/craas/" && current_path == "/credit-readiness/") ||
      (href == "/insurance/" && current_path == "/protection/") ||
      (href == "/our-partners/" && current_path == "/partners/")
    %(<a class="nav-link#{active ? " active" : ""}" href="#{href}">#{esc(label)}</a>)
  end.join
end

def alternate_links(current_path)
  return "" unless current_path == "/"

  %(<link rel="alternate" hreflang="x-default" href="#{page_url("/")}">)
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

def infographic_html(page)
  infographic = page[:infographic]
  return "" unless infographic

  steps = Array(infographic[:steps])
  step_cards = steps.each_with_index.map do |(title, body), index|
    %(
      <article class="infographic-step">
        <span class="section-number">#{format("%02d", index + 1)}</span>
        <h3>#{esc(title)}</h3>
        <p>#{esc(body)}</p>
      </article>
    )
  end.join

  <<~HTML
    <section class="infographic-band" aria-labelledby="infographic-heading">
      <div class="infographic-copy">
        <p class="section-kicker">Workflow</p>
        <h2 id="infographic-heading">#{esc(infographic[:title])}</h2>
        <p>#{esc(infographic[:body])}</p>
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
        <h2 id="daily-rhythm-heading">From zero fee microsavings to capital accumulation and credit access</h2>
      </div>
      <div class="journey-rail" aria-label="Collect contribution journey">
        <article><span>01</span><strong>Save</strong><p>Group Savings via the app or USSD.</p></article>
        <article><span>02</span><strong>Build a record</strong><p>Build savings history and capital accumulations.</p></article>
        <article><span>03</span><strong>Prepare</strong><p>Get guidance on loan requirements and support to credit readiness.</p></article>
        <article><span>04</span><strong>Access credit</strong><p>Use group savings as collateral for loan application.</p></article>
        <article><span>05</span><strong>Protect</strong><p>Access suitable insurance for income, savings protection.</p></article>
        <article><span>06</span><strong>Grow</strong><p>Use capital for business, productive assets or community goals.</p></article>
      </div>
    </section>

    <section class="original-story light" aria-labelledby="ibimina-heading">
      <div class="story-copy">
        <h2 id="ibimina-heading">Everything Collect brings together</h2>
      </div>
      <div class="story-grid four home-product-grid">
        <article><strong>Group Savings</strong><span>Digitise group savings via zero-fee microsavings and grow accumulated group capital.</span><a href="/group-savings/">Explore Group Savings</a></article>
        <article><strong>Diaspora Group Savings</strong><span>Save together through a host-country partner bank and build collateral, access credit and capital to invest home.</span><a href="/diaspora/">Explore Diaspora</a></article>
        <article><strong>Credit Readiness</strong><span>Move from a loan inquiry to a complete, structured, bank-review-ready loan application file.</span><a href="/craas/">Explore CRaaS</a></article>
        <article><strong>Insurance</strong><span>Access insurance designed around daily and irregular income patterns to protect income and savings.</span><a href="/insurance/">Explore Insurance</a></article>
      </div>
    </section>

    <section class="original-story mint" aria-labelledby="diaspora-heading">
      <div class="story-copy">
        <h2 id="diaspora-heading">Built for people who earn, save, and borrow differently</h2>
      </div>
      <div class="story-grid four">
        <article><strong>Ibimina</strong><span>Rotating and accumulating groups that need readable activity records.</span></article>
        <article><strong>Daily earners</strong><span>People saving in small amounts around daily or irregular income.</span></article>
        <article><strong>MSMEs</strong><span>Helps businesses understand requirements, coordinate specialist services and prepare bank review-ready loan file.</span></article>
        <article><strong>Diaspora</strong><span>Diaspora group savings at host-country partner banks. Collateral pledged and Credit access.</span></article>
      </div>
    </section>

    <section class="original-story info" aria-labelledby="credit-boundary-heading">
      <div class="story-copy">
        <h2 id="credit-boundary-heading">Payments work. Financial progress still does not.</h2>
      </div>
      <div class="story-grid problem-grid">
        <article><strong>Daily-income mismatch</strong><span>90% of employment is informal, yet finance is designed around monthly salaries and lump-sum payments.</span></article>
        <article><strong>Invisible group savings</strong><span>52% of adults save through ibimina, but many records remain manual and cannot support formal credit.</span></article>
        <article><strong>Credit-readiness gap</strong><span>Rwanda has extensive payment agents, but no scalable last-mile service helping MSMEs prepare complete, bank-ready loan files.</span></article>
        <article><strong>Microinsurance gap</strong><span>Premiums and claims processes rarely match small, irregular daily incomes.</span></article>
        <article><strong>Diaspora credit barriers</strong><span>Mobility risk, thin credit histories, unstable employment and insufficient acceptable collateral restrict access to affordable host-country loans.</span></article>
      </div>
    </section>
  HTML
end

def group_savings_page_html
  how_steps = [
    ["Create the group", "Define its purpose, leadership, rules and contribution schedule."],
    ["Invite members", "Onboard members individually through the app or supported assisted channels."],
    ["Contribute", "Members save through the app, mobile money or USSD."],
    ["Receive proof", "Each member receives confirmation when the transaction is completed."],
    ["Update the ledger", "The member and group balances update automatically."],
    ["Track progress", "Members and leaders can view balances, missed contributions and goals."],
    ["Build financial history", "Contribution consistency becomes a verified record."],
    ["Connect to partners", "Eligible groups may access partner-led credit, insurance or purpose-based finance."]
  ]
  features = [
    ["Transparent group ledger", "Every recognised contribution is allocated to the correct member and group."],
    ["Member statements", "Members can view their balances and contribution history without depending solely on the group treasurer."],
    ["Flexible contribution schedules", "Save daily, weekly, monthly or according to the group's own rules."],
    ["Group roles and approvals", "Set leaders, signatories, reviewers and maker-checker controls."],
    ["Purpose-based goals", "Save toward insurance, school fees, business assets, property, agriculture, taxes or green mobility."],
    ["Basic-phone access", "Supported USSD and SMS journeys make participation possible beyond smartphone users."],
    ["Regulated fund handling", "Where approved provider arrangements apply, funds are handled through regulated financial-service partners rather than on Collect's own balance sheet."],
    ["Credit-readiness record", "Contribution discipline can become part of a stronger partner-lender application."]
  ]
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
        <h2 id="group-accumulation-heading">Keep the trust. Grow the capital.</h2>
      </div>
      <div class="accumulation-panel">
        <p>Traditional rotational groups help members access a periodic lump sum, but the group capital is repeatedly distributed and depleted. Collect allows groups to add an accumulating model in which savings remain visible and can support shared goals, collateral arrangements and longer-term investment.</p>
        <strong>Each group chooses its rules.</strong>
        <span>Collect does not force groups to abandon their existing culture or governance.</span>
      </div>
    </section>

    <section class="group-use-section" aria-labelledby="group-use-heading">
      <div class="story-copy">
        <h2 id="group-use-heading">Group use cases</h2>
      </div>
      <div class="use-case-grid" aria-label="Group savings use cases">
        #{use_cases.map { |item| %(<article>#{esc(item)}</article>) }.join}
      </div>
    </section>
  HTML
end

def hero_visual_html(page)
  case page[:path]
  when "/group-savings/"
    <<~HTML
      <div class="hero-widget ledger-widget phone-widget" aria-label="Group savings ledger preview">
        <div class="phone-shell">
          <div class="phone-notch" aria-hidden="true"></div>
          <div class="phone-screen">
            <div class="phone-status"><span>9:41</span><i></i><b></b></div>
            <div class="app-bar">
              <button class="back-button" aria-label="Back"><i aria-hidden="true"></i></button>
              <strong>Statement</strong>
              <button class="download-button" aria-label="Export ledger statement"><i aria-hidden="true"></i></button>
            </div>
            <section class="statement-card">
              <span>Group ledger</span>
              <strong>RayonSport Fan Club</strong>
              <small>June 2026 contribution ledger</small>
            </section>
            <div class="ledger-summary">
              <div><span>Collected</span><strong>RWF 18,000</strong></div>
              <div><span>Pending</span><strong>1 member</strong></div>
            </div>
            <div class="statement-table" role="table" aria-label="RayonSport Fan Club contribution statement">
              <div class="statement-head" role="row"><span>Member</span><span>Amount</span><span>Status</span></div>
              <div class="ledger-row" role="row"><span class="ledger-member" role="cell"><i class="profile-icon" aria-hidden="true"></i>482917</span><strong role="cell">RWF 6,000</strong><em role="cell">Paid</em></div>
              <div class="ledger-row" role="row"><span class="ledger-member" role="cell"><i class="profile-icon" aria-hidden="true"></i>739204</span><strong role="cell">RWF 6,000</strong><em role="cell">Paid</em></div>
              <div class="ledger-row pending" role="row"><span class="ledger-member" role="cell"><i class="profile-icon" aria-hidden="true"></i>156883</span><strong role="cell">RWF 6,000</strong><em role="cell">Pending</em></div>
            </div>
            <nav class="phone-tabs" aria-label="App navigation preview">
              <span>Home</span><span class="active">Ledger</span><span>Members</span>
            </nav>
          </div>
        </div>
      </div>
    HTML
  when "/diaspora/"
    <<~HTML
      <div class="hero-widget diaspora-widget phone-widget" aria-label="Diaspora savings app screen preview">
        <div class="phone-shell">
          <div class="phone-notch" aria-hidden="true"></div>
          <div class="phone-screen">
            <div class="phone-status"><span>9:41</span><i></i><b></b></div>
            <div class="app-bar">
              <button class="back-button" aria-label="Back"><i aria-hidden="true"></i></button>
              <strong>Diaspora</strong>
              <button class="chat-button" aria-label="Open WhatsApp support"><i aria-hidden="true"></i></button>
            </div>
            <section class="diaspora-card">
              <span>Rwanda savings prep</span>
              <strong>Family group record</strong>
              <small>Contribution notes and support questions in one place.</small>
            </section>
            <div class="app-segments" aria-label="Diaspora workflow tabs">
              <span class="active">Records</span><span>Members</span><span>Support</span>
            </div>
            <div class="app-list" role="list" aria-label="Diaspora record checklist">
              <div role="listitem"><i class="app-dot ready"></i><span><strong>Group record</strong><small>Member contributions and rules</small></span><em>Ready</em></div>
              <div role="listitem"><i class="app-dot"></i><span><strong>Rwanda plan</strong><small>Purpose and preparation notes</small></span><em>Draft</em></div>
              <div role="listitem"><i class="app-dot support"></i><span><strong>WhatsApp support</strong><small>Questions and inquiries</small></span><em>Open</em></div>
            </div>
            <nav class="phone-tabs" aria-label="App navigation preview">
              <span>Home</span><span class="active">Diaspora</span><span>Support</span>
            </nav>
          </div>
        </div>
      </div>
    HTML
  when "/insurance/", "/protection/"
    <<~HTML
      <div class="hero-widget protection-widget phone-widget" aria-label="Protection support app screen preview">
        <div class="phone-shell">
          <div class="phone-notch" aria-hidden="true"></div>
          <div class="phone-screen">
            <div class="phone-status"><span>9:41</span><i></i><b></b></div>
            <div class="app-bar">
              <button class="back-button" aria-label="Back"><i aria-hidden="true"></i></button>
              <strong>Protection</strong>
              <button class="chat-button" aria-label="Open WhatsApp support"><i aria-hidden="true"></i></button>
            </div>
            <section class="protection-card">
              <span>Support request</span>
              <strong>Insurance-related records</strong>
              <small>Organize questions and records where approved providers are involved.</small>
            </section>
            <div class="app-segments" aria-label="Protection workflow tabs">
              <span class="active">Request</span><span>Records</span><span>Provider</span>
            </div>
            <div class="app-list" role="list" aria-label="Protection support checklist">
              <div role="listitem"><i class="app-dot ready"></i><span><strong>Customer question</strong><small>Support topic and preferred follow-up</small></span><em>Open</em></div>
              <div role="listitem"><i class="app-dot"></i><span><strong>Related records</strong><small>Contribution and account context</small></span><em>Added</em></div>
              <div role="listitem"><i class="app-dot support"></i><span><strong>Provider review</strong><small>Final product decisions stay with provider</small></span><em>Provider</em></div>
            </div>
            <nav class="phone-tabs" aria-label="App navigation preview">
              <span>Home</span><span class="active">Protection</span><span>Support</span>
            </nav>
          </div>
        </div>
      </div>
    HTML
  when "/craas/", "/credit-readiness/"
    <<~HTML
      <div class="hero-widget file-widget phone-widget" aria-label="Credit-readiness app screen preview">
        <div class="phone-shell">
          <div class="phone-notch" aria-hidden="true"></div>
          <div class="phone-screen">
            <div class="phone-status"><span>9:41</span><i></i><b></b></div>
            <div class="app-bar">
              <button class="back-button" aria-label="Back"><i aria-hidden="true"></i></button>
              <strong>Readiness</strong>
              <button class="download-button" aria-label="Export readiness file"><i aria-hidden="true"></i></button>
            </div>
            <section class="readiness-card">
              <span>Provider review prep</span>
              <strong>Customer support file</strong>
              <small>Documents, contribution history and request notes before review.</small>
            </section>
            <div class="app-segments" aria-label="Readiness file tabs">
              <span class="active">File</span><span>History</span><span>Notes</span>
            </div>
            <div class="app-list" role="list" aria-label="Readiness file checklist">
              <div role="listitem"><i class="app-dot ready"></i><span><strong>Customer summary</strong><small>Request purpose and contact route</small></span><em>Ready</em></div>
              <div role="listitem"><i class="app-dot ready"></i><span><strong>Contribution history</strong><small>Group saving activity record</small></span><em>Ready</em></div>
              <div role="listitem"><i class="app-dot"></i><span><strong>Missing items</strong><small>Documents still to prepare</small></span><em>Check</em></div>
              <div role="listitem"><i class="app-dot support"></i><span><strong>Provider notes</strong><small>Credit decision stays with provider</small></span><em>Review</em></div>
            </div>
            <nav class="phone-tabs" aria-label="App navigation preview">
              <span>Home</span><span class="active">File</span><span>Support</span>
            </nav>
          </div>
        </div>
      </div>
    HTML
  when "/community-groups/"
    <<~HTML
      <div class="hero-widget community-widget phone-widget" aria-label="Community group app screen preview">
        <div class="phone-shell">
          <div class="phone-notch" aria-hidden="true"></div>
          <div class="phone-screen">
            <div class="phone-status"><span>9:41</span><i></i><b></b></div>
            <div class="app-bar">
              <button class="back-button" aria-label="Back"><i aria-hidden="true"></i></button>
              <strong>Community</strong>
              <button class="chat-button" aria-label="Open WhatsApp support"><i aria-hidden="true"></i></button>
            </div>
            <section class="community-card">
              <span>Group activity</span>
              <strong>Community savings group</strong>
              <small>Member records, leader questions and contribution updates.</small>
            </section>
            <div class="app-segments" aria-label="Community group tabs">
              <span class="active">Activity</span><span>Members</span><span>Records</span>
            </div>
            <div class="member-strip" aria-label="Member preview">
              <i></i><i></i><i></i><i></i><span>Member records visible</span>
            </div>
            <div class="app-list" role="list" aria-label="Community group activity">
              <div role="listitem"><i class="app-dot ready"></i><span><strong>Contributions updated</strong><small>Group ledger reflects the latest activity</small></span><em>Done</em></div>
              <div role="listitem"><i class="app-dot"></i><span><strong>Leader questions</strong><small>Support questions stay attached to the group</small></span><em>Open</em></div>
              <div role="listitem"><i class="app-dot support"></i><span><strong>Member records</strong><small>Shared records stay organized</small></span><em>Visible</em></div>
            </div>
            <nav class="phone-tabs" aria-label="App navigation preview">
              <span>Home</span><span class="active">Groups</span><span>Support</span>
            </nav>
          </div>
        </div>
      </div>
    HTML
  when "/impact/"
    <<~HTML
      <div class="hero-widget impact-widget phone-widget" aria-label="Impact source app screen preview">
        <div class="phone-shell">
          <div class="phone-notch" aria-hidden="true"></div>
          <div class="phone-screen">
            <div class="phone-status"><span>9:41</span><i></i><b></b></div>
            <div class="app-bar">
              <button class="back-button" aria-label="Back"><i aria-hidden="true"></i></button>
              <strong>Impact</strong>
              <button class="download-button" aria-label="Export source register"><i aria-hidden="true"></i></button>
            </div>
            <section class="impact-card">
              <span>Public wording</span>
              <strong>Source-backed claims</strong>
              <small>Publish only facts that have a public source or approved wording.</small>
            </section>
            <div class="app-segments" aria-label="Impact tabs">
              <span class="active">Sources</span><span>Records</span><span>Boundaries</span>
            </div>
            <div class="app-list" role="list" aria-label="Impact source register">
              <div role="listitem"><i class="app-dot ready"></i><span><strong>Public facts</strong><small>Use source-backed wording</small></span><em>Checked</em></div>
              <div role="listitem"><i class="app-dot"></i><span><strong>Customer outcomes</strong><small>Records and support files</small></span><em>Allowed</em></div>
              <div role="listitem"><i class="app-dot support"></i><span><strong>Figures</strong><small>Need evidence before publishing</small></span><em>Hold</em></div>
            </div>
            <nav class="phone-tabs" aria-label="App navigation preview">
              <span>Home</span><span class="active">Impact</span><span>Sources</span>
            </nav>
          </div>
        </div>
      </div>
    HTML
  when "/our-partners/", "/partners/"
    <<~HTML
      <div class="hero-widget partner-widget phone-widget" aria-label="Partner workflow app screen preview">
        <div class="phone-shell">
          <div class="phone-notch" aria-hidden="true"></div>
          <div class="phone-screen">
            <div class="phone-status"><span>9:41</span><i></i><b></b></div>
            <div class="app-bar">
              <button class="back-button" aria-label="Back"><i aria-hidden="true"></i></button>
              <strong>Partners</strong>
              <button class="chat-button" aria-label="Open WhatsApp support"><i aria-hidden="true"></i></button>
            </div>
            <section class="partner-card">
              <span>Partner workflow</span>
              <strong>Records before review</strong>
              <small>Groups keep records. Providers review under their own rules.</small>
            </section>
            <div class="workflow-stack" aria-label="Partner workflow preview">
              <div><i class="app-dot ready"></i><span><strong>Groups</strong><small>Use Collect to organize records</small></span></div>
              <b></b>
              <div><i class="app-dot"></i><span><strong>Records</strong><small>Contribution history and request notes</small></span></div>
              <b></b>
              <div><i class="app-dot support"></i><span><strong>Providers</strong><small>Review and decide under their own rules</small></span></div>
            </div>
            <nav class="phone-tabs" aria-label="App navigation preview">
              <span>Home</span><span class="active">Partners</span><span>Support</span>
            </nav>
          </div>
        </div>
      </div>
    HTML
  when "/trust/", "/security/"
    <<~HTML
      <div class="hero-widget trust-widget phone-widget" aria-label="Trust app screen preview">
        <div class="phone-shell">
          <div class="phone-notch" aria-hidden="true"></div>
          <div class="phone-screen">
            <div class="phone-status"><span>9:41</span><i></i><b></b></div>
            <div class="app-bar">
              <button class="back-button" aria-label="Back"><i aria-hidden="true"></i></button>
              <strong>Trust</strong>
              <button class="chat-button" aria-label="Open WhatsApp support"><i aria-hidden="true"></i></button>
            </div>
            <section class="trust-card">
              <span>Trust center</span>
              <strong>Clear records and support paths</strong>
              <small>Deletion routes, careful public claims and WhatsApp support.</small>
            </section>
            <div class="app-list" role="list" aria-label="Trust checklist">
              <div role="listitem"><i class="app-dot ready"></i><span><strong>Clear records</strong><small>Readable contribution and request history</small></span><em>Active</em></div>
              <div role="listitem"><i class="app-dot"></i><span><strong>Deletion routes</strong><small>Account and data deletion support</small></span><em>Available</em></div>
              <div role="listitem"><i class="app-dot support"></i><span><strong>Public claims</strong><small>Only approved wording goes public</small></span><em>Checked</em></div>
            </div>
            <nav class="phone-tabs" aria-label="App navigation preview">
              <span>Home</span><span class="active">Trust</span><span>Support</span>
            </nav>
          </div>
        </div>
      </div>
    HTML
  when "/privacy/"
    <<~HTML
      <div class="hero-widget policy-widget phone-widget" aria-label="Privacy app screen preview">
        <div class="phone-shell">
          <div class="phone-notch" aria-hidden="true"></div>
          <div class="phone-screen">
            <div class="phone-status"><span>9:41</span><i></i><b></b></div>
            <div class="app-bar">
              <button class="back-button" aria-label="Back"><i aria-hidden="true"></i></button>
              <strong>Privacy</strong>
              <button class="chat-button" aria-label="Open WhatsApp support"><i aria-hidden="true"></i></button>
            </div>
            <section class="policy-card"><span>Privacy controls</span><strong>Manage data requests</strong><small>Access, correction, account deletion and data deletion routes.</small></section>
            <div class="app-list" role="list" aria-label="Privacy controls">
              <div role="listitem"><i class="app-dot ready"></i><span><strong>Access</strong><small>Ask about profile and service data</small></span><em>Open</em></div>
              <div role="listitem"><i class="app-dot"></i><span><strong>Correction</strong><small>Request correction support</small></span><em>Support</em></div>
              <div role="listitem"><i class="app-dot support"></i><span><strong>Deletion</strong><small>Account and data deletion routes</small></span><em>Available</em></div>
            </div>
            <nav class="phone-tabs" aria-label="App navigation preview"><span>Home</span><span class="active">Privacy</span><span>Support</span></nav>
          </div>
        </div>
      </div>
    HTML
  when "/terms/"
    <<~HTML
      <div class="hero-widget terms-widget phone-widget" aria-label="Terms app screen preview">
        <div class="phone-shell">
          <div class="phone-notch" aria-hidden="true"></div>
          <div class="phone-screen">
            <div class="phone-status"><span>9:41</span><i></i><b></b></div>
            <div class="app-bar">
              <button class="back-button" aria-label="Back"><i aria-hidden="true"></i></button>
              <strong>Terms</strong>
              <button class="chat-button" aria-label="Open WhatsApp support"><i aria-hidden="true"></i></button>
            </div>
            <section class="terms-card"><span>Service terms</span><strong>Use Collect clearly</strong><small>Customer responsibilities, group rules and provider decision boundaries.</small></section>
            <div class="app-list" role="list" aria-label="Terms summary">
              <div role="listitem"><i class="app-dot ready"></i><span><strong>Customer responsibilities</strong><small>Use accurate information</small></span><em>Read</em></div>
              <div role="listitem"><i class="app-dot"></i><span><strong>Group rules</strong><small>Groups manage their own rules</small></span><em>Group</em></div>
              <div role="listitem"><i class="app-dot support"></i><span><strong>Provider decisions</strong><small>Providers decide under their own rules</small></span><em>Provider</em></div>
            </div>
            <nav class="phone-tabs" aria-label="App navigation preview"><span>Home</span><span class="active">Terms</span><span>Support</span></nav>
          </div>
        </div>
      </div>
    HTML
  when "/account-deletion/"
    <<~HTML
      <div class="hero-widget deletion-widget phone-widget" aria-label="Account deletion app screen preview">
        <div class="phone-shell">
          <div class="phone-notch" aria-hidden="true"></div>
          <div class="phone-screen">
            <div class="phone-status"><span>9:41</span><i></i><b></b></div>
            <div class="app-bar">
              <button class="back-button" aria-label="Back"><i aria-hidden="true"></i></button>
              <strong>Delete Account</strong>
              <button class="chat-button" aria-label="Open WhatsApp support"><i aria-hidden="true"></i></button>
            </div>
            <section class="deletion-card"><span>Account deletion</span><strong>Request support</strong><small>Use WhatsApp support to request account deletion and status updates.</small></section>
            <div class="app-list" role="list" aria-label="Account deletion steps">
              <div role="listitem"><i class="app-dot ready"></i><span><strong>Request</strong><small>Start deletion support</small></span><em>Step 1</em></div>
              <div role="listitem"><i class="app-dot"></i><span><strong>Verify account</strong><small>Confirm the account request</small></span><em>Step 2</em></div>
              <div role="listitem"><i class="app-dot support"></i><span><strong>Confirm status</strong><small>Receive support follow-up</small></span><em>Step 3</em></div>
            </div>
            <nav class="phone-tabs" aria-label="App navigation preview"><span>Home</span><span class="active">Account</span><span>Support</span></nav>
          </div>
        </div>
      </div>
    HTML
  when "/data-deletion/"
    <<~HTML
      <div class="hero-widget data-widget phone-widget" aria-label="Data deletion app screen preview">
        <div class="phone-shell">
          <div class="phone-notch" aria-hidden="true"></div>
          <div class="phone-screen">
            <div class="phone-status"><span>9:41</span><i></i><b></b></div>
            <div class="app-bar">
              <button class="back-button" aria-label="Back"><i aria-hidden="true"></i></button>
              <strong>Delete Data</strong>
              <button class="chat-button" aria-label="Open WhatsApp support"><i aria-hidden="true"></i></button>
            </div>
            <section class="data-card"><span>Data deletion</span><strong>Request data support</strong><small>Profile details, support messages and service data are handled through support.</small></section>
            <div class="app-list" role="list" aria-label="Data deletion scope">
              <div role="listitem"><i class="app-dot ready"></i><span><strong>Profile details</strong><small>Profile-related deletion request</small></span><em>Scope</em></div>
              <div role="listitem"><i class="app-dot"></i><span><strong>Support messages</strong><small>Support request history</small></span><em>Review</em></div>
              <div role="listitem"><i class="app-dot support"></i><span><strong>Retention rules</strong><small>Limited retention may apply</small></span><em>Policy</em></div>
            </div>
            <nav class="phone-tabs" aria-label="App navigation preview"><span>Home</span><span class="active">Data</span><span>Support</span></nav>
          </div>
        </div>
      </div>
    HTML
  else
    <<~HTML
      <div class="hero-widget home-widget phone-widget" aria-label="Collect app home screen preview">
        <div class="phone-shell">
          <div class="phone-notch" aria-hidden="true"></div>
          <div class="phone-screen">
            <div class="phone-status"><span>9:41</span><i></i><b></b></div>
            <div class="app-bar">
              <button class="back-button" aria-label="Open menu"><i aria-hidden="true"></i></button>
              <strong>Collect</strong>
              <button class="chat-button" aria-label="Open WhatsApp support"><i aria-hidden="true"></i></button>
            </div>
            <section class="home-dashboard-card">
              <strong>RayonSport Fan Club</strong>
              <div class="dashboard-progress" aria-label="Group contribution progress"><i></i></div>
              <div class="dashboard-stats" aria-label="Group summary">
                <span><b>RWF 18,000</b><small>Collected</small></span>
                <span><b>3</b><small>Paid</small></span>
              </div>
            </section>
            <div class="quick-actions" aria-label="Collect app quick actions">
              <button type="button"><i class="quick-save" aria-hidden="true"></i><span>Save</span></button>
              <button type="button"><i class="quick-ledger" aria-hidden="true"></i><span>Ledger</span></button>
              <button type="button"><i class="quick-export" aria-hidden="true"></i><span>Readiness</span></button>
            </div>
            <div class="home-record-list" role="list" aria-label="Recent contribution records">
              <div role="listitem"><i class="profile-icon" aria-hidden="true"></i><span><strong>482917</strong><small>Daily saving received</small></span><em>Paid</em></div>
              <div role="listitem"><i class="profile-icon" aria-hidden="true"></i><span><strong>739204</strong><small>Readiness file updated</small></span><em>Paid</em></div>
              <div role="listitem"><i class="profile-icon" aria-hidden="true"></i><span><strong>156883</strong><small>Protection follow-up</small></span><em>Paid</em></div>
            </div>
            <nav class="phone-tabs" aria-label="App navigation preview">
              <span class="active">Home</span><span>Groups</span><span>Records</span>
            </nav>
          </div>
        </div>
      </div>
    HTML
  end
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
      <meta name="theme-color" content="#8885F0">
      <link rel="canonical" href="#{page_url(current_path)}">
      #{alternate_links(current_path)}
      <link rel="icon" href="/icons/collect.png" type="image/png">
      <link rel="manifest" href="/manifest.json">
      <meta property="og:type" content="website">
      <meta property="og:locale" content="en_US">
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
          <a class="button secondary cta-app" href="#{APP_DOWNLOAD_URL}">Get the App</a>
          <a class="button ghost cta-group" href="#{whatsapp_url("Hello IKANISA, I want to create a Collect group.")}">Create Group</a>
          <a class="button ghost cta-touch" href="#{whatsapp_url("Hello IKANISA, I have a question about Collect.")}">Get in Touch</a>
        </div>
      </header>

      <main id="content">
        <section class="hero">
          <div class="hero-copy">
            #{page[:eyebrow] ? %(<p class="hero-eyebrow">#{esc(page[:eyebrow])}</p>) : ""}
            <h1>#{esc(page[:h1])}</h1>
            <p class="hero-intro">#{esc(page[:intro])}</p>
            <div class="hero-actions">
              <a class="button primary cta-app" href="#{APP_DOWNLOAD_URL}">Get the App</a>
              <a class="button ghost cta-group" href="#{whatsapp_url("Hello IKANISA, I want to create a Collect group.")}">Create Group</a>
              <a class="button ghost cta-touch" href="#{whatsapp_url("Hello IKANISA, I have a question about Collect.")}">Get in Touch</a>
            </div>
          </div>
          <div class="hero-device">
            #{hero_visual_html(page)}
          </div>
        </section>

        #{current_path == "/" ? "" : infographic_html(page)}

        #{current_path == "/" ? home_credit_readiness_html : ""}

        #{current_path == "/group-savings/" ? group_savings_page_html : ""}

        #{current_path == "/" || current_path == "/group-savings/" ? "" : <<~HTML}
        <section class="content-grid" aria-label="Page sections">
          #{sections_html(page[:sections])}
        </section>
        HTML
        }

        #{current_path == "/" ? original_home_sections_html : ""}

        <section id="start" class="start-section" aria-labelledby="start-heading">
          <div>
            <h2 id="start-heading">#{page[:start_heading] ? esc(page[:start_heading]) : "Download <span class=\"brand-word\">Collect</span> or Get in Touch"}</h2>
            <div class="start-actions">
              <a class="button primary cta-app" href="#{APP_DOWNLOAD_URL}">Get the App</a>
              <a class="button ghost on-light cta-group" href="#{whatsapp_url("Hello IKANISA, I want to create a Collect group.")}">Create Group</a>
              <a class="button ghost on-light cta-touch" href="#{whatsapp_url("Hello IKANISA, I have a question about Collect.")}">Get in Touch</a>
            </div>
          </div>
        </section>

      </main>

      <footer class="site-footer">
        <div>
          <strong>Collect by IKANISA</strong>
        </div>
        <nav aria-label="Footer navigation">
          <a href="/privacy/">Privacy</a>
          <a href="/terms/">Terms</a>
          <a href="/account-deletion/">Account deletion</a>
          <a href="/data-deletion/">Data deletion</a>
          <a href="/trust/">Trust</a>
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
    .site-header { min-height: 72px; display: flex; align-items: center; gap: 16px; padding: 18px clamp(20px, 4vw, 48px); position: sticky; top: 0; z-index: 5; background: rgba(5, 5, 16, .86); backdrop-filter: blur(18px); border-bottom: 1px solid rgba(250,248,245,.08); }
    .brand { display: inline-flex; align-items: center; gap: 10px; text-decoration: none; min-width: max-content; }
    .brand img { border-radius: 10px; }
    .brand strong, .brand small { display: block; line-height: 1; }
    .brand strong { font-size: 19px; font-weight: 900; }
    .brand small { color: rgba(250,248,245,.7); font-weight: 800; margin-top: 3px; }
    .site-nav { display: flex; gap: 2px; align-items: center; flex: 1; justify-content: center; min-width: 0; }
    .nav-link { text-decoration: none; font-size: 12px; font-weight: 850; color: rgba(250,248,245,.72); padding: 10px 8px; border-radius: 10px; white-space: nowrap; }
    .nav-link:hover, .nav-link.active { color: var(--paper); background: rgba(250,248,245,.09); }
    .header-actions, .hero-actions { display: flex; gap: 10px; flex-wrap: wrap; }
    .header-actions { flex: 0 0 auto; flex-wrap: nowrap; gap: 8px; }
    .button, button { min-height: 44px; border: 1px solid rgba(250,248,245,.18); border-radius: 12px; display: inline-flex; align-items: center; justify-content: center; padding: 12px 18px; text-decoration: none; font-size: 14px; font-weight: 900; cursor: pointer; }
    .button { white-space: nowrap; }
    .header-actions .button { padding: 11px 14px; font-size: 13px; }
    .button.primary, .button.secondary { background: var(--periwinkle); color: white; border-color: var(--periwinkle); box-shadow: 0 14px 34px rgba(136,133,240,.24); }
    .button.ghost { background: transparent; color: var(--paper); }
    .button.cta-app { background: var(--periwinkle); color: #fffdfb; border-color: var(--periwinkle); box-shadow: 0 14px 34px rgba(136,133,240,.28); }
    .button.cta-group { background: var(--mint); color: #050510; border-color: var(--mint); box-shadow: 0 14px 34px rgba(60,208,112,.22); }
    .button.cta-touch { background: var(--orange); color: #fffdfb; border-color: var(--orange); box-shadow: 0 14px 34px rgba(255,94,67,.24); }
    .menu-button { display: none; background: rgba(250,248,245,.08); color: var(--paper); }
    .hero { min-height: calc(100svh - 72px); display: grid; grid-template-columns: minmax(0, 1.02fr) minmax(320px, .78fr); gap: clamp(28px, 5vw, 72px); align-items: center; padding: clamp(48px, 8vw, 104px) clamp(20px, 5vw, 64px) 64px; background: radial-gradient(circle at 72% 18%, rgba(136,133,240,.28), transparent 32%), radial-gradient(circle at 18% 80%, rgba(60,208,112,.16), transparent 32%), #050510; }
    .section-kicker { color: var(--mint); font-size: 13px; font-weight: 900; text-transform: uppercase; letter-spacing: .08em; margin: 0 0 18px; }
    .hero-eyebrow { color: var(--mint); font-size: 13px; font-weight: 950; text-transform: uppercase; letter-spacing: .12em; margin: 0 0 18px; }
    section { scroll-margin-top: 96px; }
    h1 { font-size: clamp(44px, 8vw, 96px); line-height: .94; margin: 0; max-width: 920px; font-weight: 950; }
    .hero-intro { color: rgba(250,248,245,.74); font-size: clamp(19px, 2.1vw, 25px); line-height: 1.38; max-width: 760px; margin: 26px 0 30px; }
    .hero-device { position: relative; min-height: 520px; display: grid; place-items: center; }
    .hero-widget { width: min(94%, 450px); min-height: 430px; border-radius: 34px; padding: 28px; color: var(--paper); border: 1px solid rgba(250,248,245,.18); background: linear-gradient(145deg, rgba(250,248,245,.11), rgba(136,133,240,.16)); box-shadow: 0 34px 90px rgba(0,0,0,.42); display: grid; gap: 16px; align-content: center; overflow: hidden; }
    .hero-widget strong, .hero-widget span, .hero-widget em, .hero-widget small { overflow-wrap: anywhere; }
    .widget-topline span, .widget-note, .hero-widget small, .hero-widget > span, .hero-widget li { color: rgba(250,248,245,.7); }
    .widget-topline strong { display: block; font-size: clamp(28px, 4vw, 42px); line-height: 1; margin-top: 8px; }
    .widget-note { font-weight: 850; line-height: 1.35; }
    .phone-widget { width: min(94%, 366px); min-height: 650px; border: 0; border-radius: 52px; padding: 0; background: transparent; box-shadow: none; display: block; overflow: visible; }
    .phone-shell { position: relative; width: 100%; height: 650px; min-height: 650px; border-radius: 52px; padding: 10px; background: linear-gradient(145deg, #060811, #171923); border: 1px solid rgba(250,248,245,.16); box-shadow: 0 38px 96px rgba(0,0,0,.55), inset 0 0 0 2px rgba(255,255,255,.05); }
    .phone-shell::before { content: ""; position: absolute; right: -4px; top: 124px; width: 4px; height: 66px; border-radius: 0 4px 4px 0; background: #272936; }
    .phone-notch { position: absolute; z-index: 2; top: 18px; left: 50%; width: 92px; height: 25px; transform: translateX(-50%); border-radius: 999px; background: #050510; box-shadow: inset 0 0 0 1px rgba(255,255,255,.06); }
    .phone-screen { height: 630px; min-height: 630px; border-radius: 42px; overflow: hidden; background: #f5f7fb; color: #17142c; display: flex; flex-direction: column; padding: 18px 16px 14px; border: 1px solid rgba(255,255,255,.08); }
    .phone-status { display: flex; align-items: center; justify-content: space-between; min-height: 24px; color: #18162c; font-size: 12px; font-weight: 950; padding: 0 4px; }
    .phone-status i { width: 52px; height: 5px; border-radius: 999px; background: transparent; }
    .phone-status b { width: 18px; height: 9px; border-radius: 3px; border: 1.5px solid #18162c; position: relative; }
    .phone-status b::after { content: ""; position: absolute; right: -4px; top: 2px; width: 2px; height: 3px; border-radius: 1px; background: #18162c; }
    .app-bar { display: grid; grid-template-columns: 38px minmax(0, 1fr) 38px; align-items: center; gap: 10px; min-height: 48px; margin-top: 8px; }
    .app-bar strong { text-align: center; font-size: 16px; line-height: 1; color: #17142c; }
    .back-button, .download-button, .chat-button { width: 38px; min-height: 38px; height: 38px; padding: 0; border-radius: 14px; background: white; border: 1px solid #e5e8f0; box-shadow: 0 8px 18px rgba(23,20,44,.08); }
    .back-button i, .download-button i, .chat-button i { display: block; width: 18px; height: 18px; margin: auto; position: relative; }
    .back-button i::before { content: ""; position: absolute; left: 5px; top: 3px; width: 10px; height: 10px; border-left: 3px solid #17142c; border-bottom: 3px solid #17142c; transform: rotate(45deg); border-radius: 1px; }
    .download-button i::before { content: ""; position: absolute; left: 7px; top: 1px; width: 4px; height: 10px; border-radius: 999px; background: #17142c; box-shadow: 0 7px 0 -2px #17142c; }
    .download-button i::after { content: ""; position: absolute; left: 3px; bottom: 1px; width: 12px; height: 7px; border-left: 3px solid #17142c; border-bottom: 3px solid #17142c; transform: rotate(-45deg); border-radius: 1px; }
    .chat-button i::before { content: ""; position: absolute; inset: 2px 1px 5px; border: 3px solid #17142c; border-radius: 999px; }
    .chat-button i::after { content: ""; position: absolute; left: 3px; bottom: 2px; width: 8px; height: 8px; border-left: 3px solid #17142c; border-bottom: 3px solid #17142c; transform: rotate(-18deg); border-radius: 1px; background: white; }
    .statement-card { margin-top: 10px; padding: 18px; border-radius: 24px; color: white; background: linear-gradient(145deg, #231f58, #5865e8 68%, #28b86b); box-shadow: 0 18px 36px rgba(88,101,232,.25); }
    .statement-card span, .statement-card small { display: block; color: rgba(255,255,255,.78); font-weight: 850; }
    .statement-card strong { display: block; margin-top: 8px; font-size: 26px; line-height: 1.05; }
    .statement-card small { margin-top: 18px; font-size: 12px; }
    .diaspora-card { margin-top: 10px; padding: 18px; border-radius: 24px; color: white; background: linear-gradient(145deg, #15352d, #23895b 58%, #6976f0); box-shadow: 0 18px 36px rgba(35,137,91,.22); }
    .diaspora-card span, .diaspora-card small { display: block; color: rgba(255,255,255,.78); font-weight: 850; }
    .diaspora-card strong { display: block; margin-top: 8px; font-size: 25px; line-height: 1.05; }
    .diaspora-card small { margin-top: 18px; font-size: 12px; line-height: 1.35; }
    .protection-card { margin-top: 10px; padding: 18px; border-radius: 24px; color: white; background: linear-gradient(145deg, #251d52, #6d63dc 58%, #f2b84b); box-shadow: 0 18px 36px rgba(109,99,220,.22); }
    .protection-card span, .protection-card small { display: block; color: rgba(255,255,255,.78); font-weight: 850; }
    .protection-card strong { display: block; margin-top: 8px; font-size: 24px; line-height: 1.05; }
    .protection-card small { margin-top: 18px; font-size: 12px; line-height: 1.35; }
    .readiness-card { margin-top: 10px; padding: 18px; border-radius: 24px; color: white; background: linear-gradient(145deg, #151833, #3846b8 58%, #2f9ec8); box-shadow: 0 18px 36px rgba(56,70,184,.22); }
    .readiness-card span, .readiness-card small { display: block; color: rgba(255,255,255,.78); font-weight: 850; }
    .readiness-card strong { display: block; margin-top: 8px; font-size: 25px; line-height: 1.05; }
    .readiness-card small { margin-top: 18px; font-size: 12px; line-height: 1.35; }
    .community-card { margin-top: 10px; padding: 18px; border-radius: 24px; color: white; background: linear-gradient(145deg, #102f45, #257ea4 58%, #28b86b); box-shadow: 0 18px 36px rgba(37,126,164,.22); }
    .community-card span, .community-card small { display: block; color: rgba(255,255,255,.78); font-weight: 850; }
    .community-card strong { display: block; margin-top: 8px; font-size: 24px; line-height: 1.05; }
    .community-card small { margin-top: 18px; font-size: 12px; line-height: 1.35; }
    .impact-card { margin-top: 10px; padding: 18px; border-radius: 24px; color: white; background: linear-gradient(145deg, #17142c, #4d3fb1 58%, #2f9ec8); box-shadow: 0 18px 36px rgba(77,63,177,.22); }
    .impact-card span, .impact-card small { display: block; color: rgba(255,255,255,.78); font-weight: 850; }
    .impact-card strong { display: block; margin-top: 8px; font-size: 25px; line-height: 1.05; }
    .impact-card small { margin-top: 18px; font-size: 12px; line-height: 1.35; }
    .partner-card { margin-top: 10px; padding: 18px; border-radius: 24px; color: white; background: linear-gradient(145deg, #142f3a, #2f9ec8 58%, #6976f0); box-shadow: 0 18px 36px rgba(47,158,200,.22); }
    .partner-card span, .partner-card small { display: block; color: rgba(255,255,255,.78); font-weight: 850; }
    .partner-card strong { display: block; margin-top: 8px; font-size: 25px; line-height: 1.05; }
    .partner-card small { margin-top: 18px; font-size: 12px; line-height: 1.35; }
    .trust-card { margin-top: 10px; padding: 18px; border-radius: 24px; color: white; background: linear-gradient(145deg, #17142c, #23415f 58%, #28b86b); box-shadow: 0 18px 36px rgba(35,65,95,.22); }
    .trust-card span, .trust-card small { display: block; color: rgba(255,255,255,.78); font-weight: 850; }
    .trust-card strong { display: block; margin-top: 8px; font-size: 24px; line-height: 1.05; }
    .trust-card small { margin-top: 18px; font-size: 12px; line-height: 1.35; }
    .policy-card, .terms-card, .deletion-card, .data-card { margin-top: 10px; padding: 18px; border-radius: 24px; color: white; box-shadow: 0 18px 36px rgba(23,20,44,.18); }
    .policy-card { background: linear-gradient(145deg, #17324b, #2f9ec8 58%, #6976f0); }
    .terms-card { background: linear-gradient(145deg, #211b43, #6976f0 58%, #28b86b); }
    .deletion-card { background: linear-gradient(145deg, #331a2d, #b04b7a 58%, #6976f0); }
    .data-card { background: linear-gradient(145deg, #172d35, #23895b 58%, #2f9ec8); }
    .policy-card span, .policy-card small, .terms-card span, .terms-card small, .deletion-card span, .deletion-card small, .data-card span, .data-card small { display: block; color: rgba(255,255,255,.78); font-weight: 850; }
    .policy-card strong, .terms-card strong, .deletion-card strong, .data-card strong { display: block; margin-top: 8px; font-size: 24px; line-height: 1.05; }
    .policy-card small, .terms-card small, .deletion-card small, .data-card small { margin-top: 18px; font-size: 12px; line-height: 1.35; }
    .home-app-card { margin-top: 10px; padding: 18px; border-radius: 24px; color: white; background: linear-gradient(145deg, #211b43, #6976f0 55%, #28b86b); box-shadow: 0 18px 36px rgba(105,118,240,.24); }
    .home-app-card span, .home-app-card small { display: block; color: rgba(255,255,255,.78); font-weight: 850; }
    .home-app-card strong { display: block; margin-top: 8px; font-size: 24px; line-height: 1.05; }
    .home-app-card small { margin-top: 18px; font-size: 12px; line-height: 1.35; }
    .home-dashboard-card { margin-top: 10px; padding: 18px; border-radius: 26px; color: white; background: linear-gradient(145deg, #17142c, #5b63df 58%, #27af67); box-shadow: 0 18px 36px rgba(91,99,223,.24); }
    .home-dashboard-card > span, .home-dashboard-card > small { display: block; color: rgba(255,255,255,.76); font-weight: 850; }
    .home-dashboard-card > strong { display: block; margin-top: 8px; font-size: 27px; line-height: 1.02; color: white; }
    .home-dashboard-card > small { margin-top: 10px; font-size: 12px; line-height: 1.35; }
    .dashboard-progress { height: 9px; margin: 18px 0 14px; border-radius: 999px; background: rgba(255,255,255,.22); overflow: hidden; }
    .dashboard-progress i { display: block; width: 72%; height: 100%; border-radius: inherit; background: linear-gradient(90deg, #3cd070, #fffdfb); }
    .dashboard-stats { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; }
    .dashboard-stats span { display: block; min-height: 62px; padding: 11px; border-radius: 17px; background: rgba(5,5,16,.22); border: 1px solid rgba(255,255,255,.16); }
    .dashboard-stats b, .dashboard-stats small { display: block; }
    .dashboard-stats b { color: white; font-size: 18px; line-height: 1.05; }
    .dashboard-stats small { margin-top: 6px; color: rgba(255,255,255,.72); font-size: 11px; font-weight: 850; }
    .quick-actions { display: grid; grid-template-columns: repeat(3, 1fr); gap: 9px; margin-top: 12px; }
    .quick-actions button { min-height: 72px; padding: 10px 8px; border-radius: 19px; border: 1px solid #e5e8f0; background: #fff; color: #17142c; box-shadow: 0 10px 20px rgba(23,20,44,.05); display: grid; gap: 7px; justify-items: center; font-size: 11px; line-height: 1; }
    .quick-actions i { width: 28px; height: 28px; border-radius: 999px; position: relative; background: #edf2ff; color: #6976f0; }
    .quick-actions i::before, .quick-actions i::after { content: ""; position: absolute; }
    .quick-save::before { left: 8px; top: 6px; width: 12px; height: 16px; border-radius: 8px 8px 5px 5px; background: currentColor; }
    .quick-save::after { left: 12px; top: 3px; width: 4px; height: 8px; border-radius: 999px; background: #3cd070; }
    .quick-ledger::before { left: 7px; top: 7px; width: 14px; height: 14px; border: 2px solid currentColor; border-radius: 4px; }
    .quick-ledger::after { left: 10px; top: 12px; width: 8px; height: 2px; background: currentColor; box-shadow: 0 5px 0 currentColor; }
    .quick-export::before { left: 12px; top: 6px; width: 4px; height: 13px; border-radius: 999px; background: currentColor; }
    .quick-export::after { left: 8px; top: 13px; width: 12px; height: 8px; border-left: 3px solid currentColor; border-bottom: 3px solid currentColor; transform: rotate(-45deg); border-radius: 1px; }
    .home-record-list { display: grid; gap: 10px; margin-top: 12px; }
    .home-record-list > div { display: grid; grid-template-columns: 28px minmax(0, 1fr) auto; gap: 10px; align-items: center; min-height: 62px; padding: 10px 12px; border: 1px solid #e5e8f0; border-radius: 18px; background: #ffffff; box-shadow: 0 10px 20px rgba(23,20,44,.05); }
    .home-record-list strong, .home-record-list small { display: block; }
    .home-record-list strong { color: #17142c; font-size: 14px; line-height: 1.1; }
    .home-record-list small { margin-top: 4px; color: #72738a; font-size: 11px; line-height: 1.25; }
    .home-record-list em { font-style: normal; color: #28b86b; font-size: 11px; font-weight: 950; }
    .app-segments { display: grid; grid-template-columns: repeat(3, 1fr); gap: 6px; margin-top: 12px; padding: 5px; border-radius: 17px; background: #e9edf5; }
    .app-segments span { min-height: 32px; display: grid; place-items: center; border-radius: 13px; color: #77788c; font-size: 11px; font-weight: 950; }
    .app-segments span.active { color: #17142c; background: #ffffff; box-shadow: 0 6px 14px rgba(23,20,44,.08); }
    .app-list { display: grid; gap: 10px; margin-top: 12px; }
    .app-list > div { display: grid; grid-template-columns: 28px minmax(0, 1fr) auto; gap: 10px; align-items: center; min-height: 66px; padding: 10px 12px; border: 1px solid #e5e8f0; border-radius: 18px; background: #ffffff; box-shadow: 0 10px 20px rgba(23,20,44,.05); }
    .app-list strong, .app-list small { display: block; }
    .app-list strong { color: #17142c; font-size: 14px; line-height: 1.1; }
    .app-list small { margin-top: 4px; color: #72738a; font-size: 11px; line-height: 1.25; }
    .app-list em { font-style: normal; color: #6976f0; font-size: 11px; font-weight: 950; }
    .app-dot { width: 28px; height: 28px; border-radius: 999px; background: #edf2ff; border: 1px solid #d7ddf0; position: relative; }
    .app-dot::after { content: ""; position: absolute; inset: 8px; border-radius: 999px; background: #6976f0; }
    .app-dot.ready { background: #e7f8ee; border-color: #cdeed9; }
    .app-dot.ready::after { background: #28b86b; }
    .app-dot.support { background: #fff7df; border-color: #f3e4ad; }
    .app-dot.support::after { background: #f2b84b; }
    .member-strip { display: flex; align-items: center; gap: 0; margin-top: 12px; padding: 12px; border: 1px solid #e5e8f0; border-radius: 18px; background: #ffffff; box-shadow: 0 10px 20px rgba(23,20,44,.05); }
    .member-strip i { width: 30px; height: 30px; border-radius: 999px; border: 2px solid #fff; background: linear-gradient(145deg, #edf2ff, #6976f0); margin-left: -8px; }
    .member-strip i:first-child { margin-left: 0; background: linear-gradient(145deg, #e7f8ee, #28b86b); }
    .member-strip i:nth-child(3) { background: linear-gradient(145deg, #fff7df, #f2b84b); }
    .member-strip span { margin-left: 10px; color: #17142c; font-size: 12px; font-weight: 950; }
    .workflow-stack { display: grid; gap: 8px; margin-top: 14px; }
    .workflow-stack > div { display: grid; grid-template-columns: 28px minmax(0, 1fr); gap: 10px; align-items: center; min-height: 66px; padding: 10px 12px; border: 1px solid #e5e8f0; border-radius: 18px; background: #ffffff; box-shadow: 0 10px 20px rgba(23,20,44,.05); }
    .workflow-stack > b { display: block; width: 2px; height: 18px; margin-left: 25px; background: #d9dee9; border-radius: 999px; }
    .workflow-stack strong, .workflow-stack small { display: block; }
    .workflow-stack strong { color: #17142c; font-size: 14px; line-height: 1.1; }
    .workflow-stack small { margin-top: 4px; color: #72738a; font-size: 11px; line-height: 1.25; }
    .ledger-summary { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; margin-top: 12px; }
    .ledger-summary div { border: 1px solid #e5e8f0; border-radius: 18px; padding: 13px; background: #ffffff; box-shadow: 0 10px 20px rgba(23,20,44,.05); }
    .ledger-summary span, .ledger-summary strong { display: block; }
    .ledger-summary span, .statement-head span { color: #72738a; }
    .ledger-summary strong { margin-top: 5px; font-size: 18px; line-height: 1.05; color: #17142c; }
    .statement-table { margin-top: 12px; border: 1px solid #e5e8f0; border-radius: 22px; overflow: hidden; background: #ffffff; box-shadow: 0 12px 24px rgba(23,20,44,.06); }
    .statement-head, .ledger-widget .ledger-row { display: grid; grid-template-columns: minmax(112px, 1fr) auto auto; gap: 10px; align-items: center; }
    .statement-head { padding: 12px 14px; background: #eef2f8; font-size: 10px; font-weight: 950; text-transform: uppercase; }
    .ledger-row, .record-card, .protection-item, .file-widget li, .activity-list, .impact-widget:not(.phone-widget) > div, .policy-widget:not(.phone-widget) span, .terms-widget:not(.phone-widget) span, .deletion-widget:not(.phone-widget) span, .data-widget:not(.phone-widget) span { border: 1px solid rgba(250,248,245,.14); border-radius: 16px; padding: 14px; background: rgba(5,5,16,.38); }
    .ledger-row { display: grid; grid-template-columns: minmax(0, 1fr) auto auto; gap: 10px; align-items: center; }
    .ledger-widget .ledger-row { border: 0; border-radius: 0; border-top: 1px solid #edf0f5; padding: 13px 14px; background: transparent; color: #17142c; }
    .ledger-member { display: inline-flex; align-items: center; gap: 9px; min-width: 0; font-weight: 950; }
    .profile-icon { position: relative; width: 28px; height: 28px; border-radius: 999px; flex: 0 0 auto; background: #edf2ff; border: 1px solid #d7ddf0; }
    .profile-icon::before { content: ""; position: absolute; left: 9px; top: 6px; width: 8px; height: 8px; border-radius: 999px; background: #6976f0; }
    .profile-icon::after { content: ""; position: absolute; left: 6px; bottom: 5px; width: 14px; height: 9px; border-radius: 999px 999px 6px 6px; background: #6976f0; }
    .ledger-row strong { font-size: 15px; }
    .ledger-widget .ledger-row strong { font-size: 12px; white-space: nowrap; color: #17142c; }
    .ledger-row em { font-style: normal; color: var(--mint); font-weight: 950; }
    .ledger-row.pending em { color: #f5c65b; }
    .phone-tabs { margin-top: auto; display: grid; grid-template-columns: repeat(3, 1fr); gap: 8px; padding: 10px 6px 4px; border-top: 1px solid #e7ebf2; }
    .phone-tabs span { display: grid; place-items: center; min-height: 34px; border-radius: 13px; color: #77788c; font-size: 11px; font-weight: 950; }
    .phone-tabs span.active { color: #17142c; background: #edf2ff; }
    .corridor-map { display: grid; grid-template-columns: auto minmax(68px, 1fr) auto; align-items: center; gap: 10px; font-weight: 900; }
    .corridor-map i, .home-flow i, .partner-line { display: block; height: 2px; background: linear-gradient(90deg, var(--mint), var(--periwinkle)); border-radius: 999px; }
    .record-card strong, .record-card span, .protection-item strong, .protection-item span, .impact-widget strong, .impact-widget span, .activity-list strong, .activity-list span { display: block; }
    .record-card span, .protection-item span, .impact-widget span, .activity-list span { margin-top: 6px; color: rgba(250,248,245,.68); line-height: 1.35; }
    .record-card.accent, .protection-item:nth-child(2), .policy-widget:not(.phone-widget) span:nth-of-type(2), .data-widget:not(.phone-widget) span:nth-of-type(2) { border-color: rgba(60,208,112,.36); }
    .protection-widget { grid-template-columns: 1fr; }
    .protection-item strong { font-size: 34px; line-height: 1; }
    .file-header strong, .policy-widget:not(.phone-widget) strong, .terms-widget:not(.phone-widget) strong, .deletion-widget:not(.phone-widget) strong, .data-widget:not(.phone-widget) strong, .trust-widget:not(.phone-widget) > strong { display: block; font-size: clamp(27px, 3vw, 38px); line-height: 1; }
    .file-header span { color: rgba(250,248,245,.68); font-weight: 850; }
    .file-widget ul { margin: 4px 0 0; padding: 0; list-style: none; display: grid; gap: 10px; }
    .file-widget li { color: var(--paper); font-weight: 850; display: flex; align-items: center; gap: 10px; }
    .file-widget li span { width: 12px; height: 12px; border-radius: 999px; background: var(--mint); flex: 0 0 auto; }
    .community-widget:not(.phone-widget) { grid-template-columns: .8fr 1fr; align-items: center; }
    .member-ring { width: 150px; height: 150px; border-radius: 999px; display: grid; place-items: center; align-content: center; border: 16px solid rgba(60,208,112,.52); box-shadow: inset 0 0 0 1px rgba(250,248,245,.18); }
    .member-ring span { font-size: 50px; line-height: .9; font-weight: 950; }
    .member-ring small { font-weight: 900; }
    .activity-list { display: grid; gap: 8px; }
    .activity-list span { margin-top: 0; }
    .impact-widget:not(.phone-widget), .policy-widget:not(.phone-widget), .terms-widget:not(.phone-widget), .deletion-widget:not(.phone-widget), .data-widget:not(.phone-widget) { align-content: stretch; }
    .impact-widget > div { min-height: 96px; display: grid; align-content: center; }
    .partner-widget { grid-template-columns: 1fr; align-content: center; }
    .partner-node { min-height: 78px; display: grid; place-items: center; border-radius: 18px; border: 1px solid rgba(250,248,245,.16); background: rgba(250,248,245,.1); font-weight: 950; }
    .partner-line { width: 70%; justify-self: center; }
    .shield-mark { width: 118px; height: 118px; border-radius: 32px; display: grid; place-items: center; background: linear-gradient(145deg, rgba(60,208,112,.9), rgba(136,133,240,.9)); color: #050510; font-weight: 950; font-size: 32px; }
    .trust-widget { justify-items: start; }
    .trust-widget span { line-height: 1.4; }
    .policy-widget:not(.phone-widget), .terms-widget:not(.phone-widget), .deletion-widget:not(.phone-widget), .data-widget:not(.phone-widget) { grid-template-columns: 1fr 1fr; }
    .policy-widget:not(.phone-widget) strong, .terms-widget:not(.phone-widget) strong, .deletion-widget:not(.phone-widget) strong, .data-widget:not(.phone-widget) strong { grid-column: 1 / -1; }
    .policy-widget:not(.phone-widget) span, .terms-widget:not(.phone-widget) span, .deletion-widget:not(.phone-widget) span, .data-widget:not(.phone-widget) span { font-weight: 850; display: grid; align-items: center; min-height: 58px; }
    .home-flow { display: grid; grid-template-columns: auto minmax(34px, 1fr) auto minmax(34px, 1fr) auto; align-items: center; gap: 10px; }
    .home-flow span { font-weight: 950; }
    .infographic-band h2 { font-size: clamp(34px, 5vw, 64px); line-height: 1; margin: 0; }
    .infographic-band p { color: var(--muted); line-height: 1.55; }
    .infographic-band { display: grid; gap: 28px; padding: clamp(56px, 8vw, 96px) clamp(20px, 5vw, 64px); background: #f2f4ff; color: var(--ink); }
    .infographic-copy { max-width: 860px; }
    .infographic-grid { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 14px; }
    .infographic-step { min-height: 150px; border: 1px solid #e1d9f0; border-radius: 18px; padding: 18px; background: rgba(255,253,251,.86); box-shadow: 0 14px 34px rgba(37,32,68,.06); }
    .infographic-step h3 { margin: 16px 0 8px; font-size: 19px; line-height: 1.12; }
    .infographic-step p { margin: 0; font-size: 14px; }
    .explain-band, .start-section, .market-context { display: grid; grid-template-columns: minmax(0, .72fr) minmax(0, 1fr); gap: clamp(24px, 5vw, 72px); padding: clamp(56px, 8vw, 96px) clamp(20px, 5vw, 64px); background: var(--paper); color: var(--ink); }
    .explain-band h2, .start-section h2, .market-context h2 { font-size: clamp(34px, 5vw, 64px); line-height: 1; margin: 0; }
    .brand-word { color: var(--orange); }
    .market-context p { color: var(--muted); line-height: 1.55; }
    .source-note { font-size: 13px; max-width: 680px; }
    .source-note a { color: #2f3db9; font-weight: 850; }
    .market-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); border: 1px solid #e5deef; border-radius: 20px; overflow: hidden; background: #fffdfb; }
    .market-grid article { min-height: 154px; padding: 24px; border-right: 1px solid #e5deef; border-bottom: 1px solid #e5deef; display: grid; align-content: end; }
    .market-grid article:nth-child(2n) { border-right: 0; }
    .market-grid article:nth-last-child(-n+2) { border-bottom: 0; }
    .market-grid strong { display: block; font-size: clamp(42px, 5vw, 62px); line-height: .9; color: #23306f; }
    .market-grid span { display: block; margin-top: 12px; color: var(--muted); font-weight: 850; line-height: 1.3; }
    .step-list { display: grid; gap: 12px; margin: 0; padding: 0; list-style: none; }
    .step-list li, .section-card { border: 1px solid #e5deef; border-radius: 16px; padding: 18px; background: #fffdfb; }
    .step-list strong, .step-list span { display: block; }
    .step-list span { color: var(--muted); margin-top: 4px; line-height: 1.45; }
    .content-grid { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 18px; padding: clamp(56px, 8vw, 96px) clamp(20px, 5vw, 64px); background: #fffdfb; color: var(--ink); }
    .section-number { color: var(--periwinkle); font-weight: 950; }
    .section-card h2 { margin: 18px 0 10px; font-size: 24px; line-height: 1.12; }
    .section-card p, .start-section p { color: var(--muted); line-height: 1.55; }
    .bullet-list { margin: 18px 0 0; padding: 0; list-style: none; display: grid; gap: 10px; }
    .bullet-list li { position: relative; padding-left: 22px; color: var(--muted); line-height: 1.4; font-weight: 700; }
    .bullet-list li::before { content: ""; position: absolute; left: 0; top: .62em; width: 8px; height: 8px; border-radius: 999px; background: var(--mint); }
    .original-story { display: grid; grid-template-columns: minmax(0, .72fr) minmax(0, 1fr); gap: clamp(24px, 5vw, 72px); padding: clamp(56px, 8vw, 96px) clamp(20px, 5vw, 64px); background: #11101a; color: var(--paper); }
    .original-story.light { background: #fffdfb; color: var(--ink); }
    .original-story.mint { background: #ecfbf1; color: var(--ink); }
    .original-story.danger { background: #fff3f3; color: var(--ink); }
    .original-story.info { background: #f2f4ff; color: var(--ink); }
    .original-story h2 { font-size: clamp(34px, 5vw, 62px); line-height: 1; margin: 0; }
    .original-story p { color: color-mix(in srgb, currentColor 72%, transparent); line-height: 1.55; }
    .story-grid { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 14px; }
    .story-grid.four { grid-template-columns: repeat(4, minmax(0, 1fr)); }
    .story-grid.home-product-grid { grid-template-columns: repeat(2, minmax(0, 1fr)); }
    .story-grid.problem-grid { grid-template-columns: 1fr; }
    .story-grid.five { grid-template-columns: repeat(5, minmax(0, 1fr)); }
    .story-grid.six { grid-template-columns: repeat(3, minmax(0, 1fr)); }
    .story-grid article { min-height: 142px; border: 1px solid rgba(136,133,240,.2); border-radius: 16px; padding: 18px; background: rgba(255,255,255,.72); color: var(--ink); }
    .original-story:not(.light):not(.mint):not(.danger):not(.info) .story-grid article { background: rgba(250,248,245,.08); color: var(--paper); border-color: rgba(250,248,245,.14); }
    .story-grid strong, .story-grid span { display: block; }
    .story-grid strong { font-size: 18px; font-weight: 950; line-height: 1.05; }
    .story-grid span { margin-top: 10px; color: color-mix(in srgb, currentColor 68%, transparent); line-height: 1.35; }
    .story-grid a { display: inline-flex; margin-top: 18px; color: #6976f0; font-weight: 950; text-decoration: none; }
    .group-problem-section, .group-workflow-section, .group-feature-section, .group-accumulation-section, .group-use-section { display: grid; grid-template-columns: minmax(0, .72fr) minmax(0, 1fr); gap: clamp(24px, 5vw, 72px); padding: clamp(56px, 8vw, 96px) clamp(20px, 5vw, 64px); }
    .group-problem-section { background: #fffdfb; color: var(--ink); }
    .group-workflow-section { background: #11101a; color: var(--paper); }
    .group-feature-section { background: #f2f4ff; color: var(--ink); }
    .group-accumulation-section { background: #ecfbf1; color: var(--ink); }
    .group-use-section { background: #fffdfb; color: var(--ink); }
    .group-problem-section h2, .group-workflow-section h2, .group-feature-section h2, .group-accumulation-section h2, .group-use-section h2 { font-size: clamp(34px, 5vw, 62px); line-height: 1; margin: 0; }
    .group-problem-section p, .group-accumulation-section p { color: var(--muted); line-height: 1.55; font-size: 18px; }
    .problem-list { display: grid; gap: 12px; }
    .problem-list article, .use-case-grid article { border: 1px solid #e5deef; border-radius: 16px; padding: 18px; background: rgba(255,255,255,.78); color: var(--ink); font-weight: 900; line-height: 1.2; }
    .problem-list.compact { grid-template-columns: repeat(2, minmax(0, 1fr)); }
    .group-journey { grid-template-columns: repeat(4, minmax(0, 1fr)); }
    .group-journey article { min-height: 210px; }
    .group-journey article:nth-child(3n) { border-right: 1px solid rgba(250,248,245,.14); }
    .group-journey article:nth-child(4n) { border-right: 0; }
    .group-journey article:nth-last-child(-n+4) { border-bottom: 0; }
    .group-feature-grid { grid-template-columns: repeat(4, minmax(0, 1fr)); }
    .accumulation-panel { border: 1px solid rgba(37,32,68,.12); border-radius: 24px; padding: clamp(24px, 4vw, 42px); background: rgba(255,255,255,.78); box-shadow: 0 18px 48px rgba(37,32,68,.06); }
    .accumulation-panel p { margin-top: 0; }
    .accumulation-panel strong, .accumulation-panel span { display: block; }
    .accumulation-panel strong { color: #164a2b; font-size: 24px; line-height: 1.1; }
    .accumulation-panel span { margin-top: 8px; color: var(--muted); line-height: 1.45; }
    .use-case-grid { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 12px; }
    .journey-rail { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 0; border: 1px solid rgba(250,248,245,.16); border-radius: 22px; overflow: hidden; background: rgba(250,248,245,.06); }
    .journey-rail article { min-height: 190px; padding: 22px; border-right: 1px solid rgba(250,248,245,.14); border-bottom: 1px solid rgba(250,248,245,.14); display: grid; align-content: end; }
    .journey-rail article:nth-child(3n) { border-right: 0; }
    .journey-rail article:nth-last-child(-n+3) { border-bottom: 0; }
    .journey-rail span { color: var(--mint); font-size: 13px; font-weight: 950; }
    .journey-rail strong { display: block; margin-top: 42px; font-size: clamp(22px, 2.1vw, 30px); line-height: 1; }
    .journey-rail p { margin: 14px 0 0; color: rgba(250,248,245,.72); line-height: 1.38; }
    .journey-rail.group-journey { grid-template-columns: repeat(4, minmax(0, 1fr)); }
    .journey-rail.group-journey article { min-height: 210px; }
    .journey-rail.group-journey article:nth-child(3n) { border-right: 1px solid rgba(250,248,245,.14); }
    .journey-rail.group-journey article:nth-child(4n) { border-right: 0; }
    .journey-rail.group-journey article:nth-last-child(-n+4) { border-bottom: 0; }
    .start-actions { display: flex; gap: 10px; flex-wrap: wrap; margin-top: 22px; }
    .button.on-light:not(.cta-app):not(.cta-group):not(.cta-touch) { color: var(--ink); border-color: #ded8ea; }
    .site-footer { display: grid; grid-template-columns: minmax(0, 1fr) minmax(280px, .8fr); gap: 28px; padding: 36px clamp(20px, 5vw, 64px); border-top: 1px solid rgba(250,248,245,.12); background: #050510; }
    .site-footer nav { display: flex; flex-wrap: wrap; justify-content: flex-end; align-content: start; gap: 12px 18px; }
    .site-footer a { color: rgba(250,248,245,.82); font-weight: 800; }
    @media (max-width: 1120px) and (min-width: 981px) {
      .site-header { flex-wrap: nowrap; }
      .menu-button { display: inline-flex; margin-left: auto; }
      .site-nav { display: none; position: absolute; top: 100%; left: 0; right: 0; padding: 12px clamp(20px, 5vw, 64px) 18px; justify-content: flex-start; overflow: visible; flex-wrap: wrap; background: #050510; border-bottom: 1px solid rgba(250,248,245,.1); box-shadow: 0 24px 60px rgba(0,0,0,.35); }
      .site-nav.open { display: flex; }
      .header-actions { display: none; }
    }
    @media (max-width: 980px) {
      .site-header { flex-wrap: nowrap; }
      .menu-button { display: inline-flex; margin-left: auto; }
      .site-nav { display: none; position: absolute; top: 100%; left: 0; right: 0; padding: 12px clamp(20px, 5vw, 64px) 18px; justify-content: flex-start; overflow: visible; flex-wrap: wrap; background: #050510; border-bottom: 1px solid rgba(250,248,245,.1); box-shadow: 0 24px 60px rgba(0,0,0,.35); }
      .site-nav.open { display: flex; }
      .header-actions { display: none; }
      .hero { min-height: auto; grid-template-columns: 1fr; padding-top: 40px; }
      .hero-device { min-height: 360px; }
      .hero-widget { width: min(100%, 390px); min-height: 350px; }
      .phone-widget { width: min(100%, 366px); min-height: 650px; }
      .content-grid, .infographic-grid { grid-template-columns: 1fr 1fr; }
      .explain-band, .start-section, .market-context, .original-story { grid-template-columns: 1fr; }
      .group-problem-section, .group-workflow-section, .group-feature-section, .group-accumulation-section, .group-use-section { grid-template-columns: 1fr; }
      .problem-list.compact, .use-case-grid { grid-template-columns: repeat(2, minmax(0, 1fr)); }
      .story-grid, .story-grid.four, .story-grid.five, .story-grid.six { grid-template-columns: 1fr 1fr; }
      .journey-rail { grid-template-columns: repeat(2, minmax(0, 1fr)); }
      .journey-rail.group-journey { grid-template-columns: repeat(2, minmax(0, 1fr)); }
      .journey-rail article { border-right: 1px solid rgba(250,248,245,.14); border-bottom: 1px solid rgba(250,248,245,.14); }
      .journey-rail article:nth-child(3n) { border-right: 1px solid rgba(250,248,245,.14); }
      .journey-rail article:nth-child(2n) { border-right: 0; }
      .journey-rail article:not(:nth-last-child(-n+2)) { border-bottom: 1px solid rgba(250,248,245,.14); }
      .journey-rail article:nth-last-child(-n+2) { border-bottom: 0; }
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
      .hero-widget { width: 100%; min-height: 300px; border-radius: 24px; padding: 20px; }
      .phone-widget { width: min(100%, 340px); min-height: 620px; padding: 0; border-radius: 48px; }
      .phone-shell { height: 620px; min-height: 620px; border-radius: 48px; }
      .phone-screen { height: 600px; min-height: 600px; border-radius: 38px; padding: 16px 14px 12px; }
      .ledger-summary { grid-template-columns: 1fr; }
      .statement-head, .ledger-widget .ledger-row { grid-template-columns: minmax(92px, 1fr) auto; }
      .statement-head span:last-child, .ledger-widget .ledger-row em { grid-column: 1 / -1; }
      .ledger-row { grid-template-columns: 1fr auto; gap: 8px; }
      .ledger-row strong { grid-column: 1 / -1; }
      .ledger-widget .ledger-row strong { grid-column: auto; }
      .community-widget:not(.phone-widget), .policy-widget:not(.phone-widget), .terms-widget:not(.phone-widget), .deletion-widget:not(.phone-widget), .data-widget:not(.phone-widget) { grid-template-columns: 1fr; }
      .member-ring { width: 128px; height: 128px; justify-self: center; }
      .home-flow { grid-template-columns: 1fr; }
      .home-flow i { height: 18px; width: 2px; justify-self: center; }
      .content-grid, .infographic-grid { grid-template-columns: 1fr; }
      .story-grid, .story-grid.four, .story-grid.five, .story-grid.six { grid-template-columns: 1fr; }
      .explain-band, .start-section, .market-context, .content-grid { padding: 48px 20px; }
      .group-problem-section, .group-workflow-section, .group-feature-section, .group-accumulation-section, .group-use-section { grid-template-columns: 1fr; padding: 48px 20px; }
      .problem-list.compact, .use-case-grid, .journey-rail.group-journey { grid-template-columns: 1fr; }
      .market-grid { grid-template-columns: 1fr; }
      .market-grid article { min-height: 128px; border-right: 0; }
      .market-grid article:nth-last-child(2) { border-bottom: 1px solid #e5deef; }
      .original-story { padding: 48px 20px; }
      .journey-rail { grid-template-columns: 1fr; }
      .journey-rail article { min-height: 180px; border-right: 0; border-bottom: 1px solid rgba(250,248,245,.14); }
      .journey-rail article:last-child { border-bottom: 0; }
      .site-footer { grid-template-columns: 1fr; }
      .site-footer nav { justify-content: flex-start; }
    }
    @media (max-width: 1180px) and (min-width: 981px) {
      .journey-rail { grid-template-columns: repeat(2, minmax(0, 1fr)); }
      .journey-rail article { border-right: 1px solid rgba(250,248,245,.14); border-bottom: 1px solid rgba(250,248,245,.14); }
      .journey-rail article:nth-child(3n) { border-right: 1px solid rgba(250,248,245,.14); }
      .journey-rail article:nth-child(2n) { border-right: 0; }
      .journey-rail article:nth-last-child(-n+3) { border-bottom: 1px solid rgba(250,248,245,.14); }
      .journey-rail article:nth-last-child(-n+2) { border-bottom: 0; }
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
  "description" => "Microsavings and group savings for daily earners.",
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
