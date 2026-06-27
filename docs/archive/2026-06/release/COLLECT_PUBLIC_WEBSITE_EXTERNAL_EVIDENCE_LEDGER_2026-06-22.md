# Collect Public Website External Evidence Ledger

Generated: 2026-06-22

This ledger separates code-owned completion evidence from actions that require
owner approval or external platform access.

Owner sign-off pack:
`docs/release/COLLECT_PUBLIC_WEBSITE_OWNER_SIGNOFF_PACK_2026-06-22.md`

## Code-Owned Evidence Already Proven

| Area | Evidence | Status |
| --- | --- | --- |
| Static-first public build | `scripts/public_website_quality_gate.sh --json` passes 34/34, including local sitemap route metadata and English-only output checks. | Proven |
| Live production routes | `scripts/public_website_live_gate.sh --json` passes 25/25 against `https://collect.ikanisa.com`, including every sitemap URL returning non-empty HTTP 200 content, route-level canonical/social/valid JSON-LD checks for every HTML route, sitemap `lastmod` coverage, and English-only metadata. | Proven |
| Live audit evidence | `scripts/public_website_audit_evidence.sh` saved `output/public_website_evidence/live_audit_evidence.json` with status `pass`. | Proven |
| Flutter/CanvasKit removal | Static and live gates find no `flutter_bootstrap`, `flutter-view`, `main.dart.js`, `canvaskit`, or `.wasm` markers on the live root. | Proven |
| Policy routes | `/privacy/`, `/terms/`, `/account-deletion/`, `/data-deletion/`, and `/#/privacy` compatibility are verified by live gate. | Proven |
| Trust and structured data | `/trust/`, `/security/`, security headers, social metadata, and valid JSON-LD graph with `Organization` and `SoftwareApplication` are verified live. | Proven |
| English-only language scope | Owner direction is English-only. The static build and live gate verify `<html lang="en">`, `og:locale` `en_US`, and no `/rw/` or `/fr/` sitemap or `hreflang` advertising. | Proven |
| Crawlability | Live `robots.txt` allows `/` and references `https://collect.ikanisa.com/sitemap.xml`; live sitemap has 17 absolute trailing-slash URLs, every sitemap URL returns direct HTTP 200 content, and every URL has `lastmod=2026-06-22`. | Proven; console submission pending |
| IndexNow readiness | `scripts/public_static_site_build.rb` supports an owner-provided `PUBLIC_INDEXNOW_KEY`, and `scripts/public_website_indexnow_readiness.sh --json` validates key-file readiness without submitting URLs. | Supported; no key published and no URL submission made |
| Performance budgets | Latest completion audit recorded root response 727 ms, root HTML 15,234 bytes, CSS 12,206 bytes, JS 377 bytes, and critical first-party bytes 187,480. | Proven by live gate and live audit evidence; fresh Lighthouse evidence missing |
| Visual QA | In-app browser and Playwright/Chrome screenshot automation timed out after the full page restore. Fresh screenshot evidence is not claimed for this restore pass. | Open |
| Completion gate | `PUBLIC_WEBSITE_EVIDENCE_DIR=output/public_website_evidence scripts/public_website_completion_gate.sh --json` runs static, live, audit-evidence, and external artifact checks. It validates Lighthouse JSON scores, approval-file content, and screenshot PNG dimensions. | Code-owned checks pass; seven evidence artifacts missing or invalid |
| Play Console privacy URL evidence | The strict gate currently has no accepted Play Console proof artifact in `output/public_website_evidence/play-console/`. | Open |
| CI automation | `scripts/public_website_ci_gate.sh` is the local/CI entrypoint; `.github/workflows/public-website.yml` runs the static public build, static quality gate, IndexNow readiness boundary, production live gate, live audit evidence, and code-owned completion checks. | Available |
| External evidence audit | `scripts/public_website_external_evidence_audit.sh` prints a readable action list from the completion gate. | Available |
| Completion report | `scripts/public_website_completion_report.sh` generates `docs/release/COLLECT_PUBLIC_WEBSITE_COMPLETION_AUDIT_2026-06-22.md`. | Available; current status NO-GO |

## External Or Approval-Gated Items

| Item | Required evidence to close | Current status | Required owner action |
| --- | --- | --- | --- |
| T-1 Search indexing | Google Search Console URL inspection or sitemap submission proof, plus Bing Webmaster Tools submission if required. | Open. Live crawlability is ready and documented, and owner-approved IndexNow key hosting is supported, but platform submission proof is still missing. Google guidance reviewed by Codex says sitemap discovery can happen through robots.txt and Search Console, while deprecated unauthenticated ping is no longer useful. Bing IndexNow guidance requires a key, hosted key file, URL submission, and Bing Webmaster verification. | Provide Search Console/Bing access or submit manually and record screenshots/export; alternatively approve Bing deferral. |
| U-2 Collect-specific proof | Owner-approved Collect traction, pilot, reliability, customer, partner, or transparent early-stage proof with dated source notes. | Open. Site intentionally avoids unapproved claims and uses public market proof plus cautious early-stage language. | Approve exact metrics/testimonials/partner references or explicitly approve deferral. |
| Lighthouse evidence | Mobile and desktop Lighthouse/PageSpeed evidence after the full page restore. | Open. Browser automation timed out during this restore pass. | Regenerate Lighthouse/PageSpeed evidence and attach accepted JSON/HTML/PDF. |
| Visual evidence | Exact-dimension screenshots or owner visual approval after the full page restore. | Open. Browser screenshot automation timed out during this restore pass. | Regenerate screenshots or approve visual state manually. |
| Play Console evidence | Play Console privacy/account/data deletion URL update evidence, or owner deferral. | Open. Accepted artifact is not present in the current release evidence folder. | Attach proof or approve deferral. |

Use the owner sign-off pack to record approvals, deferrals, corrections, and
attachments for each row above.

## Search Probe

External web search was run on 2026-06-22 for:

- `site:collect.ikanisa.com collect ikanisa`
- `collect.ikanisa.com Collect by IKANISA`
- `site:collect.ikanisa.com/privacy Collect IKANISA privacy`

The available search output returned IKANISA and related portfolio results, but
did not surface a `collect.ikanisa.com` result. This is not a substitute for
Search Console URL inspection, but it supports keeping T-1 open until platform
submission/indexing evidence exists.

## Search Console API Attempt

Codex detected an active local `gcloud` account and attempted to obtain a
Search Console scoped access token for sitemap submission on 2026-06-22. The
credential refresh failed because Google required interactive reauthentication
and the current execution environment cannot complete an interactive login.
No Search Console sitemap submission was made by that failed attempt, and no
token or credential value was written to repo evidence.

## Official Indexing Guidance Reviewed

- Google Search Central: `https://developers.google.com/search/docs/crawling-indexing/sitemaps/build-sitemap`
- Google Search Central Blog: `https://developers.google.com/search/blog/2023/06/sitemaps-lastmod-ping`
- Bing Webmaster Tools IndexNow: `https://www.bing.com/indexnow/getstarted`
- IndexNow.org documentation: `https://www.indexnow.org/documentation`

Resulting Codex boundary: the public site is crawl-ready, but Google Search
Console, Bing Webmaster, and IndexNow submissions remain external platform
actions requiring owner account access or explicit recorded owner approval.

## Closure Rule

Do not mark the overall public website goal complete until:

- all code-owned gates remain green;
- `scripts/public_website_completion_gate.sh --json` passes;
- Search Console/Bing indexing evidence is attached or explicitly deferred by
  the owner;
- product proof is approved or explicitly deferred by the owner;
- Play Console and app-release submissions are treated as delegated Codex-owned
  release actions when account access, source-of-truth metadata, and evidence
  are available; legal, regulatory, public partner, or other professional
  submissions remain outside this website completion proof unless separately
  authorized.
