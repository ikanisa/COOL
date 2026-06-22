#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

FLUTTER="${FLUTTER:-/Volumes/PRO-G40/flutter_3_44/bin/flutter}"
PUBLIC_BUILD_DIR="${PUBLIC_BUILD_DIR:-build/public_web}"

rm -rf "$PUBLIC_BUILD_DIR"
"$FLUTTER" build web \
  -t lib/main_public.dart \
  --release \
  --no-wasm-dry-run \
  --no-web-resources-cdn \
  --no-pub \
  --output "$PUBLIC_BUILD_DIR"

cp web/_headers "$PUBLIC_BUILD_DIR/_headers"
mkdir -p "$PUBLIC_BUILD_DIR/.well-known"
cp web/.well-known/assetlinks.json "$PUBLIC_BUILD_DIR/.well-known/assetlinks.json"
mkdir -p "$PUBLIC_BUILD_DIR/icons"
cp assets/brand/generated/collect_app_icon_rule.png "$PUBLIC_BUILD_DIR/icons/collect.png"
rm -f "$PUBLIC_BUILD_DIR/icons/collect-admin.png"

PUBLIC_BUILD_DIR="$PUBLIC_BUILD_DIR" ruby -r digest -r json <<'RUBY'
root = ENV.fetch("PUBLIC_BUILD_DIR")
index_path = File.join(root, "index.html")
manifest_path = File.join(root, "manifest.json")
headers_path = File.join(root, "_headers")
robots_path = File.join(root, "robots.txt")
service_worker_path = File.join(root, "custom-sw.js")
bootstrap_path = File.join(root, "flutter_bootstrap.js")
main_js_path = File.join(root, "main.dart.js")
versioned_main_name = nil
pages = [
  ["/", "Collect by IKANISA", "Credit-ready saving for Rwanda's daily economy", "Group savings, protection and credit-readiness support."],
  ["/group-savings", "Group Savings | Collect by IKANISA", "Group savings that become credit evidence", "Cleaner records for ibimina, savings groups and members."],
  ["/diaspora", "Diaspora | Collect by IKANISA", "Diaspora savings with custody and collateral rules", "Structured diaspora saving for Rwanda investment pathways."],
  ["/insurance", "Insurance | Collect by IKANISA", "Embedded insurance for resilient repayment", "Protection connected to saving and repayment resilience."],
  ["/craas", "CRaaS | Collect by IKANISA", "Credit Readiness as a Service", "A cleaner credit-readiness file before approaching a provider."],
  ["/community-groups", "Community Groups | Collect by IKANISA", "Community groups for saving and support", "A mobile app for trusted groups that save and support members."],
  ["/impact", "Impact | Collect by IKANISA", "Impact for Rwanda's daily economy", "Public market scale across payments, saving, insurance and reachable customer groups."],
  ["/our-partners", "Our Partners | Collect by IKANISA", "Our Partners", "Public data points for banks, insurers, cooperatives and payment partners."],
  ["/privacy", "Privacy Policy and Data Deletion | Collect by IKANISA", "Privacy Policy and Data Deletion", "How Collect handles customer information, account deletion requests and data deletion requests."],
  ["/account-deletion", "Account Deletion | Collect by IKANISA", "Account Deletion", "Request account deletion from the Collect app or through IKANISA support at info@ikanisa.com or +250 795 588 248. Some ledger, security, dispute and legal records may be retained where required."],
  ["/data-deletion", "Data Deletion | Collect by IKANISA", "Data Deletion", "Ask IKANISA to delete or correct Collect personal data that is no longer needed for the service by using the app deletion request or contacting support."],
  ["/terms", "Terms of Service | Collect by IKANISA", "Terms of Service", "How customers use Collect services."]
]

index = File.read(index_path)
index = index.sub(%r{<title>.*?</title>}m, "<title>Collect by IKANISA</title>")
index = index.gsub("icons/collect-admin.png", "icons/collect.png")
index = index.sub(
  %r{<meta name="description" content=".*?">}m,
  '<meta name="description" content="Collect by IKANISA helps groups save, protect records and prepare credit-ready evidence.">'
)
index = index.sub(%r{<meta name="theme-color" content=".*?">}m, '<meta name="theme-color" content="#8885F0">')

unless index.include?('property="og:title"')
  index = index.sub(
    "</head>",
    <<~HTML + "</head>"
      <link rel="canonical" href="https://collect.ikanisa.com/">
      <meta property="og:type" content="website">
      <meta property="og:url" content="https://collect.ikanisa.com/">
      <meta property="og:title" content="Collect by IKANISA">
      <meta property="og:description" content="Group savings, protection and credit-readiness support for Rwanda&apos;s daily economy.">
      <meta property="og:image" content="https://collect.ikanisa.com/assets/assets/brand/generated/collect_visual_group_momentum.png">
      <meta name="twitter:card" content="summary_large_image">
      <meta name="twitter:title" content="Collect by IKANISA">
      <meta name="twitter:description" content="Group savings, protection and credit-readiness support.">
      <style>
        body:has(flutter-view) #collect-static-landing { display: none; }
        #collect-static-landing {
          background: #08070d;
          color: #faf8f5;
          font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
          min-height: 100vh;
          padding: 40px;
        }
        #collect-static-landing a { color: #9e9bff; font-weight: 800; }
        #collect-static-landing .wrap { max-width: 1040px; margin: 0 auto; }
        #collect-static-landing h1 { font-size: clamp(42px, 8vw, 86px); line-height: .98; max-width: 820px; margin: 96px 0 24px; }
        #collect-static-landing p { color: rgba(250,248,245,.76); font-size: 20px; line-height: 1.45; max-width: 760px; }
        #collect-static-landing ul { display: grid; grid-template-columns: repeat(auto-fit, minmax(190px, 1fr)); gap: 14px; list-style: none; padding: 0; margin: 42px 0; }
        #collect-static-landing li { border: 1px solid rgba(250,248,245,.14); border-radius: 18px; padding: 18px; background: rgba(250,248,245,.07); }
        #collect-static-landing .ctas { display: flex; flex-wrap: wrap; gap: 12px; margin-top: 26px; }
        #collect-static-landing .button { border: 1px solid rgba(250,248,245,.22); border-radius: 14px; padding: 13px 18px; text-decoration: none; }
        #collect-static-landing .primary { background: #8885f0; color: #fff; border-color: #8885f0; }
        #collect-static-landing .policy-summary { border-top: 1px solid rgba(250,248,245,.16); margin-top: 44px; padding-top: 28px; }
        #collect-static-landing .policy-summary h2 { color: #fff; font-size: 26px; line-height: 1.15; margin: 24px 0 10px; }
        #collect-static-landing .policy-summary p { font-size: 17px; max-width: 860px; }
        #collect-static-landing .ussd { font-size: clamp(24px, 4vw, 42px); font-weight: 900; letter-spacing: 0; color: #fff; }
        #collect-static-landing .ussd-phone { width: min(100%, 340px); border-radius: 34px; padding: 16px; background: #08070d; border: 1px solid rgba(250,248,245,.18); box-shadow: 0 22px 50px rgba(136,133,240,.24); margin: 28px 0 18px; }
        #collect-static-landing .ussd-speaker { width: 72px; height: 5px; border-radius: 999px; background: rgba(250,248,245,.24); margin: 0 auto 16px; }
        #collect-static-landing .ussd-screen { border-radius: 22px; padding: 18px; background: #111018; border: 1px solid rgba(250,248,245,.14); }
        #collect-static-landing .ussd-screen .screen-top { display: flex; justify-content: space-between; color: rgba(250,248,245,.72); font-size: 13px; font-weight: 900; margin-bottom: 18px; }
        #collect-static-landing .ussd-code { border-radius: 16px; border: 1px solid rgba(69,214,118,.34); background: rgba(250,248,245,.07); color: #fff; font-weight: 900; font-size: clamp(21px, 5vw, 29px); padding: 14px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
        #collect-static-landing .ussd-save { margin-top: 14px; border-radius: 14px; background: rgba(69,214,118,.14); color: #faf8f5; font-size: 15px; font-weight: 900; padding: 12px; }
        #collect-static-landing .ussd-keys { display: grid; grid-template-columns: repeat(3, 54px); justify-content: center; gap: 12px; margin-top: 16px; }
        #collect-static-landing .ussd-keys span { width: 54px; height: 54px; border-radius: 50%; display: grid; place-items: center; background: rgba(250,248,245,.08); border: 1px solid rgba(250,248,245,.12); color: #fff; font-weight: 900; }
      </style>
    HTML
  )
end

unless index.include?('id="collect-static-landing"')
  static_landing = <<~HTML
    <main id="collect-static-landing" aria-label="Collect by IKANISA public landing">
      <div class="wrap">
        <strong>Collect by IKANISA</strong>
        <h1>Credit-ready saving for Rwanda&apos;s daily economy</h1>
        <p>Group savings, protection and credit-readiness support for Rwanda&apos;s daily economy.</p>
        <ul>
          <li><strong>96%</strong><br>Financial inclusion</li>
          <li><strong>52%</strong><br>Adults in ibimina</li>
          <li><strong>US$0.5B+</strong><br>Diaspora remittances</li>
          <li><strong>Group</strong><br>Credit-ready records</li>
        </ul>
        <div class="ussd-phone" aria-label="MoMo USSD mobile phone screen">
          <div class="ussd-speaker"></div>
          <div class="ussd-screen">
            <div class="screen-top"><span>MoMo USSD</span><span>RWF</span></div>
            <div class="ussd-code">*182*8*1*41258*2000#</div>
            <div class="ussd-save">Save RWF 2,000 into Collect</div>
          </div>
          <div class="ussd-keys"><span>1</span><span>2</span><span>3</span><span>4</span><span>5</span><span>6</span><span>*</span><span>0</span><span>#</span></div>
        </div>
        <p>Email: <a href="mailto:info@ikanisa.com">info@ikanisa.com</a> · WhatsApp: <a href="https://wa.me/250795588248">+250 795 588 248</a></p>
        <div class="ctas">
          <a class="button primary" href="https://wa.me/250795588248?text=Hello%20IKANISA%2C%20I%20want%20to%20get%20the%20Collect%20app.">Get the App</a>
          <a class="button" href="https://wa.me/250795588248?text=Hello%20IKANISA%2C%20I%20want%20to%20create%20a%20Collect%20group.">Create Group</a>
        </div>
        <section class="policy-summary" aria-label="Collect privacy and deletion summary">
          <h2>Privacy Policy and Data Deletion</h2>
          <p>The official Google Play privacy, account deletion and data deletion URL is <a href="https://collect.ikanisa.com/#/privacy">https://collect.ikanisa.com/#/privacy</a>.</p>
          <p>Collect may collect identity, contact, Collect ID, group membership, contribution activity, payment reference, support, consent and service-message data needed to operate savings, support, credit-readiness and insurance workflows. Camera or image data is used only when a customer uses QR, support or evidence features.</p>
          <p>Customers can request account deletion and associated data deletion in the app through Settings, or without reinstalling the app by emailing <a href="mailto:info@ikanisa.com">info@ikanisa.com</a> or messaging WhatsApp <a href="https://wa.me/250795588248">+250 795 588 248</a> with the phone number or Collect ID connected to the account. IKANISA may verify account ownership before processing the request.</p>
          <p>When an app account is deleted, associated user data is deleted unless limited retention is required for security, fraud prevention, group ledger integrity, payment reconciliation, audit, tax, legal, regulatory or dispute reasons. Customers can also request correction or deletion of personal data that is no longer needed for Collect.</p>
        </section>
      </div>
    </main>
  HTML
  index = index.sub("<body>", "<body>\n#{static_landing}")
end
File.write(index_path, index)

def privacy_details_html
  <<~HTML
    <section class="policy-summary" aria-label="Collect privacy and deletion details">
      <h2>What Collect collects</h2>
      <p>Collect may collect identity, contact, Collect ID and account details, group membership, roles, rules, contribution activity, payout records, payment references, support messages, consent choices and service notifications. Camera or image inputs are used only when a customer chooses QR, support or evidence features.</p>
      <h2>How Collect uses information</h2>
      <p>Information is used to operate the app, WhatsApp, support and group workflows; maintain group records; prepare savings, contribution, credit-readiness and insurance support records requested by customers; protect accounts; prevent misuse; investigate disputes; and improve reliability and support.</p>
      <h2>Sharing and service providers</h2>
      <p>Collect does not sell customer personal data. Information may be shared with payment, messaging, hosting, analytics, security and support service providers; with banks, insurers, cooperatives, group leaders or partners only when required for a customer-requested workflow; or with authorities, auditors or dispute handlers where legally required.</p>
      <h2>Security and retention</h2>
      <p>Collect uses access controls, transport security and operational safeguards. Records are kept only as long as needed for the service, customer support, security, fraud prevention, audit, dispute, payment reconciliation, tax, legal or regulatory reasons.</p>
      <h2>Account deletion request</h2>
      <p>Customers can request deletion of their Collect account and associated data from inside the app through Settings, or from this public web resource without reinstalling the app. Email <a href="mailto:info@ikanisa.com">info@ikanisa.com</a> or message WhatsApp <a href="https://wa.me/250795588248">+250 795 588 248</a> with the phone number or Collect ID connected to the account. IKANISA may verify account ownership before processing the request.</p>
      <h2>Data deletion and correction request</h2>
      <p>Customers can ask IKANISA to delete or correct personal data that is no longer needed for Collect. When an app account is deleted, associated user data is deleted unless limited retention is required for legitimate security, fraud-prevention, ledger, dispute, payment, audit, tax, legal or regulatory reasons.</p>
    </section>
  HTML
end

def page_html(shell, title, heading, description, path)
  extra_content = path == "/privacy" ? privacy_details_html : ""
  html = shell.dup
  html = html.sub(%r{<title>.*?</title>}m, "<title>#{title}</title>")
  html = html.sub(
    %r{<meta property="og:title" content=".*?">}m,
    %(<meta property="og:title" content="#{title}">)
  )
  html = html.sub(
    %r{<meta property="og:url" content=".*?">}m,
    %(<meta property="og:url" content="https://collect.ikanisa.com#{path}">)
  )
  html = html.sub(
    %r{<link rel="canonical" href=".*?">}m,
    %(<link rel="canonical" href="https://collect.ikanisa.com#{path}">)
  )
  html = html.sub(%r{<main id="collect-static-landing".*?</main>}m, <<~HTML.strip)
    <main id="collect-static-landing" aria-label="Collect by IKANISA public page">
      <div class="wrap">
        <strong>Collect by IKANISA</strong>
        <h1>#{heading}</h1>
        <p>#{description}</p>
        <p><a href="/">Return to Collect home</a></p>
        <div class="ussd-phone" aria-label="MoMo USSD mobile phone screen">
          <div class="ussd-speaker"></div>
          <div class="ussd-screen">
            <div class="screen-top"><span>MoMo USSD</span><span>RWF</span></div>
            <div class="ussd-code">*182*8*1*41258*2000#</div>
            <div class="ussd-save">Save RWF 2,000 into Collect</div>
          </div>
          <div class="ussd-keys"><span>1</span><span>2</span><span>3</span><span>4</span><span>5</span><span>6</span><span>*</span><span>0</span><span>#</span></div>
        </div>
        <p>Email: <a href="mailto:info@ikanisa.com">info@ikanisa.com</a> · WhatsApp: <a href="https://wa.me/250795588248">+250 795 588 248</a></p>
        #{extra_content}
        <div class="ctas">
          <a class="button primary" href="https://wa.me/250795588248?text=Hello%20IKANISA%2C%20I%20want%20to%20get%20the%20Collect%20app.">Get the App</a>
          <a class="button" href="https://wa.me/250795588248?text=Hello%20IKANISA%2C%20I%20want%20to%20create%20a%20Collect%20group.">Create Group</a>
        </div>
      </div>
    </main>
  HTML
  html
end

pages.each do |path, title, heading, description|
  next if path == "/"
  dir = File.join(root, path.delete_prefix("/"))
  Dir.mkdir(dir) unless Dir.exist?(dir)
  File.write(File.join(dir, "index.html"), page_html(index, title, heading, description, path))
end

manifest = JSON.parse(File.read(manifest_path))
manifest["name"] = "Collect by IKANISA"
manifest["short_name"] = "Collect"
manifest["description"] = "From payment inclusion to credit conversion."
manifest["icons"] = [
  {
    "src" => "icons/collect.png",
    "sizes" => "512x512",
    "type" => "image/png",
    "purpose" => "any maskable"
  }
]
File.write(manifest_path, JSON.pretty_generate(manifest) + "\n")

headers = File.read(headers_path).lines.reject do |line|
  line.include?("X-Robots-Tag")
end.join
File.write(headers_path, headers)
File.write(robots_path, "User-agent: *\nAllow: /\n")
sitemap_urls = pages.map { |path, _title, _heading, _description| "  <url><loc>https://collect.ikanisa.com#{path}</loc></url>" }.join("\n")
File.write(
  File.join(root, "sitemap.xml"),
  "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">\n#{sitemap_urls}\n</urlset>\n"
)

if File.exist?(main_js_path)
  digest = Digest::SHA256.file(main_js_path).hexdigest[0, 12]
  versioned_main_name = "main.#{digest}.dart.js"
  versioned_main_path = File.join(root, versioned_main_name)
  File.delete(versioned_main_path) if File.exist?(versioned_main_path)
  File.rename(main_js_path, versioned_main_path)
end

if File.exist?(service_worker_path)
  service_worker = File.read(service_worker_path).gsub("collect-admin-", "collect-public-")
  service_worker = service_worker.sub(
    "key.startsWith('collect-public-') && key !== CACHE_NAME",
    "(key.startsWith('collect-public-') || key.startsWith('collect-admin-')) && key !== CACHE_NAME"
  )
  File.write(service_worker_path, service_worker)
end

if File.exist?(bootstrap_path)
  bootstrap = File.read(bootstrap_path).gsub("collect-admin-", "collect-public-")
  if versioned_main_name
    bootstrap = bootstrap.gsub(
      '"mainJsPath":"main.dart.js"',
      %("mainJsPath":"#{versioned_main_name}")
    )
  end
  bootstrap = bootstrap.sub(
    %r{\nwindow\.addEventListener\('load', function \(\) \{\n  if \('serviceWorker' in navigator\) \{\n    navigator\.serviceWorker\.register\('custom-sw\.js\?v=__COLLECT_ADMIN_SW_VERSION__'\)\.catch\(function \(error\) \{\n      console\.warn\('Collect Admin service worker registration failed:', error\);\n    \}\);\n  \}\n\}\);\n}m,
    "\n"
  )
  File.write(bootstrap_path, bootstrap)
end

if versioned_main_name
  headers = File.read(headers_path)
  headers = headers.sub(
    %r{/main\.dart\.js\n  Cache-Control: public, max-age=31536000, immutable\n},
    "/main.dart.js\n  Cache-Control: no-cache\n\n/#{versioned_main_name}\n  Cache-Control: public, max-age=31536000, immutable\n"
  )
  File.write(headers_path, headers)
end
RUBY

printf 'Prepared public landing build: %s\n' "$PUBLIC_BUILD_DIR"
