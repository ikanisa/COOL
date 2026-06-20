#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ADMIN_BUILD_DIR="${ADMIN_BUILD_DIR:-build/web}"
PUBLIC_BUILD_DIR="${PUBLIC_BUILD_DIR:-build/public_web}"

if [[ ! -f "$ADMIN_BUILD_DIR/index.html" ]]; then
  echo "Missing source web build: $ADMIN_BUILD_DIR/index.html" >&2
  echo "Run scripts/admin_pwa_release_build.sh first." >&2
  exit 1
fi

rm -rf "$PUBLIC_BUILD_DIR"
cp -R "$ADMIN_BUILD_DIR" "$PUBLIC_BUILD_DIR"

PUBLIC_BUILD_DIR="$PUBLIC_BUILD_DIR" ruby -r json <<'RUBY'
root = ENV.fetch("PUBLIC_BUILD_DIR")
index_path = File.join(root, "index.html")
manifest_path = File.join(root, "manifest.json")
headers_path = File.join(root, "_headers")
robots_path = File.join(root, "robots.txt")
service_worker_path = File.join(root, "custom-sw.js")
bootstrap_path = File.join(root, "flutter_bootstrap.js")
pages = [
  ["/", "Collect by IKANISA", "Credit-ready saving for Rwanda's daily economy", "From payment inclusion to credit conversion: Collect turns local ibimina and diaspora savings into verified ledgers, credit-ready files, collateral rules and insured repayment capacity."],
  ["/group-savings", "Group savings | Collect by IKANISA", "Group savings that become credit evidence", "Collect helps ibimina and savings groups move from informal contribution tracking to verified ledgers, daily saving discipline, consented statements and bank-ready evidence."],
  ["/diaspora", "Diaspora | Collect by IKANISA", "Diaspora savings with custody and collateral rules", "Collect gives diaspora groups a structured way to save together through custody records, ring-fenced collateral and Rwanda investment pathways."],
  ["/insurance", "Insurance | Collect by IKANISA", "Embedded insurance for resilient repayment", "Collect embeds protection around savings and credit journeys so health, death, income and climate shocks do not automatically destroy repayment discipline."],
  ["/craas", "CRaaS | Collect by IKANISA", "Credit Readiness as a Service", "CRaaS turns a loan inquiry into a credit-ready file with evidence quality, human completion, indexed documents, risk flags and a clear borrower handoff."],
  ["/community-groups", "Community groups | Collect by IKANISA", "Community groups as customer support infrastructure", "Collect treats trusted local groups as the strongest last-mile interface for savings, credit readiness, protection and customer support."],
  ["/privacy", "Privacy Policy | Collect by IKANISA", "Privacy Policy", "Collect protects customer information with clear consent, limited access and practical safeguards for savings, credit-readiness and insurance journeys."],
  ["/terms", "Terms of Service | Collect by IKANISA", "Terms of Service", "These terms explain how customers use Collect for group savings, contribution records, credit-readiness support, insurance records and customer service."]
]

index = File.read(index_path)
index = index.sub(%r{<title>.*?</title>}m, "<title>Collect by IKANISA</title>")
index = index.sub(
  %r{<meta name="description" content=".*?">}m,
  '<meta name="description" content="Collect by IKANISA turns local ibimina and diaspora savings into verified ledgers, credit-ready files, collateral rules and insured repayment capacity for Rwanda&apos;s daily economy.">'
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
      <meta property="og:description" content="Credit-ready saving for Rwanda&apos;s daily economy: ibimina, diaspora custody, verified ledgers, microinsurance and application-ready credit files.">
      <meta property="og:image" content="https://collect.ikanisa.com/assets/assets/brand/generated/collect_visual_group_momentum.png">
      <meta name="twitter:card" content="summary_large_image">
      <meta name="twitter:title" content="Collect by IKANISA">
      <meta name="twitter:description" content="From payment inclusion to credit conversion for local groups, diaspora savers and families.">
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
        #collect-static-landing .ussd { font-size: clamp(24px, 4vw, 42px); font-weight: 900; letter-spacing: 0; color: #fff; }
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
        <p>From payment inclusion to credit conversion: Collect turns local ibimina and diaspora savings into verified ledgers, credit-ready files, collateral rules and insured repayment capacity.</p>
        <ul>
          <li><strong>96%</strong><br>financial inclusion</li>
          <li><strong>52%</strong><br>adults in ibimina</li>
          <li><strong>US$0.5B+</strong><br>diaspora remittances</li>
          <li><strong>0</strong><br>credit-readiness agents</li>
        </ul>
        <p class="ussd">*182*8*1*41258*2000#</p>
        <p>Dial *182*8*1*41258*2000# to save RWF 2,000 into Collect.</p>
        <p>Email: <a href="mailto:info@ikanisa.com">info@ikanisa.com</a> · WhatsApp: <a href="https://wa.me/250795588248">+250 795 588 248</a></p>
        <div class="ctas">
          <a class="button primary" href="https://wa.me/250795588248?text=Hello%20IKANISA%2C%20I%20want%20to%20get%20the%20Collect%20app.">Get the app</a>
          <a class="button" href="https://wa.me/250795588248?text=Hello%20IKANISA%2C%20I%20want%20to%20create%20a%20Collect%20group%20savings%20account.">Create group savings</a>
          <a class="button" href="/privacy">Privacy Policy</a>
          <a class="button" href="/terms">Terms</a>
        </div>
      </div>
    </main>
  HTML
  index = index.sub("<body>", "<body>\n#{static_landing}")
end
File.write(index_path, index)

def page_html(shell, title, heading, description, path)
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
        <ul>
          <li><strong>Home</strong><br><a href="/">Credit-ready saving</a></li>
          <li><strong>Group savings</strong><br><a href="/group-savings">Verified ibimina ledgers</a></li>
          <li><strong>Diaspora</strong><br><a href="/diaspora">Custody and collateral rules</a></li>
          <li><strong>Insurance</strong><br><a href="/insurance">Embedded repayment protection</a></li>
          <li><strong>CRaaS</strong><br><a href="/craas">Credit-ready files</a></li>
          <li><strong>Community groups</strong><br><a href="/community-groups">Customer support infrastructure</a></li>
          <li><strong>Privacy</strong><br><a href="/privacy">Privacy Policy</a></li>
          <li><strong>Terms</strong><br><a href="/terms">Terms of Service</a></li>
        </ul>
        <p class="ussd">*182*8*1*41258*2000#</p>
        <p>Dial *182*8*1*41258*2000# to save RWF 2,000 into Collect.</p>
        <p>Email: <a href="mailto:info@ikanisa.com">info@ikanisa.com</a> · WhatsApp: <a href="https://wa.me/250795588248">+250 795 588 248</a></p>
        <div class="ctas">
          <a class="button primary" href="https://wa.me/250795588248?text=Hello%20IKANISA%2C%20I%20want%20to%20get%20the%20Collect%20app.">Get the app</a>
          <a class="button" href="https://wa.me/250795588248?text=Hello%20IKANISA%2C%20I%20want%20to%20create%20a%20Collect%20group%20savings%20account.">Create group savings</a>
          <a class="button" href="/privacy">Privacy Policy</a>
          <a class="button" href="/terms">Terms</a>
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
  File.write(bootstrap_path, bootstrap)
end
RUBY

printf 'Prepared public landing build: %s\n' "$PUBLIC_BUILD_DIR"
