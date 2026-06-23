# Collect Public Website Page Restore Evidence

Generated: 2026-06-22

Deployment: `2ca0058b-bd5f-4e21-9d20-5e0f93d38258`

Scope: restore the original English public website page content from
`lib/features/landing/public_content.dart` and
`lib/features/landing/collect_landing_page.dart` into the static public
website generator without reintroducing `/rw/` or `/fr/` routes.

## Restored Pages

| Page | Live URL | Restored original content checked live |
| --- | --- | --- |
| Home | `https://collect.ikanisa.com/` | Original positioning, `Get the App`, `Create Group`, USSD example, rhythm gap, ibimina records, diaspora, insurance, CRaaS, customer journeys. |
| Group Savings | `https://collect.ikanisa.com/group-savings/` | `Group savings journey`, `Make contributions easier to follow`, `Support treasurers`, `Credit-ready evidence`. |
| Diaspora | `https://collect.ikanisa.com/diaspora/` | `Diaspora savings pathway`, `Diaspora group saving structure`, `Custody and collateral rules`, `Trust and communication`. |
| Insurance | `https://collect.ikanisa.com/insurance/` | `Protection and premium flow`, `Protection at the point of saving`, `Prepare for premiums`, `Simple product language`. |
| CRaaS | `https://collect.ikanisa.com/craas/` | `From inquiry to bank-ready file`, `Prepare before asking for credit`, `Use Collect records as proof`, `Human support to complete the file`. |
| Community Groups | `https://collect.ikanisa.com/community-groups/` | `What the app enables for a group`, `Member app`, `Leader support`, `Trusted group support`. |
| Impact | `https://collect.ikanisa.com/impact/` | `Impact chain`, `Insurance market with a concrete renewal problem`, `Moto-taxi customers are a visible distribution base`, `70,000`. |
| Our Partners | `https://collect.ikanisa.com/our-partners/` | `Partner value chain`, `Banks and deposit partners`, `Mobile-money and agent networks`, `Moto-taxi associations`. |
| Privacy | `https://collect.ikanisa.com/privacy/` | `Information we collect`, `Camera or image inputs`, `Collect does not sell customer personal data`, `Customer choices and contact`. |
| Account Deletion | `https://collect.ikanisa.com/account-deletion/` | `What happens next`, `Open groups or payment issues may need resolution first`, `Records we may retain`. |
| Data Deletion | `https://collect.ikanisa.com/data-deletion/` | `Submit a data deletion request`, `Data covered by the request`, `Limited retention`. |
| Terms | `https://collect.ikanisa.com/terms/` | `Using Collect`, `Savings, credit-readiness and protection`, `Support and contact`. |

## Alias Routes Kept For Audit Compatibility

| Alias | Canonical content served |
| --- | --- |
| `https://collect.ikanisa.com/credit-readiness/` | CRaaS content |
| `https://collect.ikanisa.com/protection/` | Insurance content |
| `https://collect.ikanisa.com/partners/` | Our Partners content |
| `https://collect.ikanisa.com/security/` | Trust and Security content |

## Tests Run

| Check | Result |
| --- | --- |
| `ruby -c scripts/public_static_site_build.rb` | PASS |
| `scripts/public_landing_prepare_build.sh` | PASS |
| `scripts/public_website_quality_gate.sh --json` | PASS, 34/34 |
| Local generated HTML page-by-page content checks | PASS for the pages listed above |
| `wrangler deploy --name collect-public --assets build/public_web --compatibility-date 2026-06-22 --message "Restore all original Collect public pages"` | PASS, version `2ca0058b-bd5f-4e21-9d20-5e0f93d38258` |
| `scripts/public_website_live_gate.sh --json` | PASS, 25/25 |
| `scripts/public_website_audit_evidence.sh` | PASS |
| Live `curl` page-by-page content checks | PASS for the pages listed above |

## Browser Visual QA Status

The in-app browser setup timed out. Playwright/Chrome screenshot automation also
timed out after deployment and left automation browser processes, which were
terminated. No fresh screenshot pass is claimed for this restore pass.

## Current Strict Completion Boundary

The website implementation and live route content are restored and green. The
strict completion gate remains `NO-GO` because the evidence folder currently
lacks accepted Search Console, Bing, Lighthouse, visual screenshot, Play Console,
and Collect-product-proof artifacts.
