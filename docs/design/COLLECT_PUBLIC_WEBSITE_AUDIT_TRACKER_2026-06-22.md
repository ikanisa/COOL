# Collect Public Website Audit Tracker

Generated: 2026-06-22

Source audit: `Collect by IKANISA — Website Audit`, dated 2026-06-22.

Implementation source of truth:

- `docs/design/COLLECT_PUBLIC_WEBSITE_WORLD_CLASS_REMEDIATION_PLAN_2026-06-22.md`
- `docs/design/COLLECT_PUBLIC_WEBSITE_FULL_IMPLEMENTATION_GOAL_2026-06-22.md`

Status values:

- `Open`: no durable implementation proof yet.
- `In progress`: implementation started, but not yet proven by gate/live evidence.
- `Deferred`: owner explicitly approved deferral and blocker is recorded.
- `Closed`: repo and live evidence prove completion.

## Tracker

| ID | Severity | Finding | Required implementation | Validation evidence | Status | Approval blocker |
| --- | --- | --- | --- | --- | --- | --- |
| T-1 | Critical | Site is not indexed by Google / weak crawlability. | Static-first route HTML, canonical URLs, sitemap with `lastmod`, robots allow, reciprocal localized metadata, Search Console/Bing submission evidence. | `scripts/public_website_quality_gate.sh --json` passed 34/34; `scripts/public_website_live_gate.sh --json` passed 28/28; every sitemap URL has local metadata-complete HTML and every live sitemap URL returns non-empty HTTP 200 content. Sitemap entries use served trailing-slash URLs, reciprocal `hreflang` is present on `/`, `/rw/`, `/fr/`, and 18 sitemap URLs have `lastmod=2026-06-22`. | In progress | Search Console/Bing submission evidence still requires owner account access or owner-approved deferral. |
| T-2 | Critical | Privacy policy must be a true retrievable URL, not hash-router-only. | Serve `/privacy/`, `/terms/`, `/account-deletion/`, `/data-deletion/`; preserve `/#/privacy` compatibility with visible policy text. | Live gate passed for `/privacy/`, `/terms/`, `/account-deletion/`, `/data-deletion/`, and root `/#/privacy` compatibility content. | Closed | Play Console resubmission/update remains an external owner-approved action. |
| T-3 | High | Hard JavaScript dependency and weak low-bandwidth resilience. | Remove Flutter/CanvasKit from public home critical path; primary content works without JS; minimal progressive JS only. | Static gate and live gate prove no `flutter_bootstrap.js`, `flutter-view`, `main.dart.js`, `canvaskit`, or WASM on `/` critical path; JS is 377 bytes. | Closed | None. |
| T-4 | Medium | No structured data or visible fintech trust/security signal. | Add JSON-LD, `/trust/` or `/security/`, data handling, deletion, dispute, reliability, and approved regulatory/partner status language. | Static gate and live gate prove valid JSON-LD graph, `/trust/`, `/security/`, security headers, data/deletion/support language, and cautious provider-decision language. | Closed | Future regulatory, partner, or compliance-status claims require owner/legal approval before publication. |
| U-1 | High | CTAs funnel only to WhatsApp. | Keep WhatsApp but add a self-serve app/group/partner path and privacy-safe instrumentation plan. | Static gate and live gate prove a non-WhatsApp self-serve lead form with email input on the live root. | Closed | Any future analytics/data capture beyond mailto form requires privacy/data-safety review. |
| U-2 | High | Proof is macro-market proof, not Collect product proof. | Add real Collect traction, pilot, reliability, or transparent early-stage proof. | Dated source notes in content; claim review log. | Open | Product metrics, partner names, and testimonials require owner approval. |
| U-3 | Medium | Credit-readiness mechanism is not clear enough. | Add a near-top `How credit-readiness works` section with consent and no-credit-approval-promise language. | Static gate and live gate prove near-top explainer with consent and `Final credit decisions remain with the provider` language. | Closed | Future provider-sharing copy changes require legal/product approval. |
| U-4 | Medium | No Kinyarwanda/French localization. | Add `/rw/` and `/fr/` or equivalent static localized pages; localize WhatsApp prefill templates and expose reciprocal localized SEO metadata. | Static and live gates prove `/rw/` and `/fr/` routes, language attributes, localized copy, language links, reciprocal `hreflang`, and OG locale metadata. | In progress | Translation approval required before final public claim. |
| U-5 | Low | Brand system is not distinctive enough. | Accepted visual concept and static-first implementation with Collect-owned assets, product mockups, mobile menu, and polished first viewports. | `scripts/public_website_playwright_visual_qa.js` passed with exact-dimension screenshots at 390x844, 430x932, 768x1024, and 1440x1000. | Closed | Future brand/design changes require owner approval. |

## Current Baseline Notes

- Previous live/public build had partial policy progress: `/privacy/` existed and contained policy text, but the home page still loaded Flutter web after the static fallback.
- Previous mobile first viewport had clipped horizontal nav, repeated CTAs, and product proof too low in the screen.
- Previous source `web/_headers` included `X-Robots-Tag: noindex, nofollow`; the new static public generator writes public-specific headers without `noindex` or `no-store`.
- 2026-06-22 local proof: `scripts/public_landing_prepare_build.sh` generated `build/public_web` from `scripts/public_static_site_build.rb`.
- 2026-06-22 local proof: `scripts/public_website_quality_gate.sh --json` passed 34/34 checks, including local sitemap route metadata, sitemap `lastmod` coverage, and reciprocal localized `hreflang` metadata.
- 2026-06-22 local proof: generated `build/public_web` includes `/`, `/group-savings/`, `/diaspora/`, `/credit-readiness/`, `/craas/`, `/protection/`, `/insurance/`, `/partners/`, `/our-partners/`, `/impact/`, `/trust/`, `/security/`, `/privacy/`, `/terms/`, `/account-deletion/`, `/data-deletion/`, `/rw/`, and `/fr/`.
- 2026-06-22 local proof: generated public JS is 377 bytes, generated public build has no Flutter/CanvasKit critical-path files and no WASM, and total local build size is about 636 KB.
- 2026-06-22 deploy proof: `wrangler deploy --name collect-public --assets build/public_web --compatibility-date 2026-06-22 --message "Align sitemap canonical URLs with served slash routes"` deployed Cloudflare Workers static assets version `40b3f4a4-6a63-476e-b878-8c45ef13a9da`.
- 2026-06-22 live proof: `scripts/public_website_live_gate.sh --json` passed 28/28 against `https://collect.ikanisa.com`.
- 2026-06-22 live sitemap proof: `https://collect.ikanisa.com/sitemap.xml` returns 18 absolute trailing-slash URLs, each sitemap URL returns direct HTTP 200 content, and every URL has `lastmod=2026-06-22`.
- 2026-06-22 live proof: production root returns 8.5 KB static HTML, `Cache-Control: public, max-age=300, must-revalidate`, no `X-Robots-Tag`, CSP/referrer/content-type security headers, canonical/social/valid JSON-LD metadata, lead form, no Flutter/CanvasKit/WASM markers, and visible `/#/privacy` compatibility content.
- 2026-06-22 live proof: expanded live gate passes every sitemap route, performance budget, static accessibility, localized route, reciprocal `hreflang`, OG locale metadata, mobile navigation CSS, route-level HTML metadata checks, and sitemap `lastmod` checks; live critical first-party asset bytes were 177,445.
- 2026-06-22 live proof: `scripts/public_website_audit_evidence.sh` saved `docs/release/collect_public_website_evidence_2026-06-22/live_audit_evidence.json`; latest completion audit passed with root response 275 ms, root HTML 8,871 bytes, CSS 8,534 bytes, JS 377 bytes, critical first-party bytes 177,445, valid JSON-LD types `Organization` and `SoftwareApplication`, and Cloudflare cache status `HIT`.
- 2026-06-22 Lighthouse proof: `docs/release/collect_public_website_evidence_2026-06-22/lighthouse/mobile.json` scored Performance 98, Accessibility 96, Best Practices 100, and SEO 100; `docs/release/collect_public_website_evidence_2026-06-22/lighthouse/desktop.json` scored Performance 100, Accessibility 96, Best Practices 100, and SEO 100.
- 2026-06-22 browser proof: `scripts/public_website_playwright_visual_qa.js` passed against `https://collect.ikanisa.com/` and saved `docs/release/collect_public_website_evidence_2026-06-22/browser_visual_qa.json` plus exact-dimension screenshots under `docs/release/collect_public_website_evidence_2026-06-22/screenshots/`.
- 2026-06-22 external ledger: `docs/release/COLLECT_PUBLIC_WEBSITE_EXTERNAL_EVIDENCE_LEDGER_2026-06-22.md` records remaining owner/platform-gated evidence for Search Console/Bing indexing, Collect-specific proof, translation approval, and Play Console updates.
- 2026-06-22 owner sign-off pack: `docs/release/COLLECT_PUBLIC_WEBSITE_OWNER_SIGNOFF_PACK_2026-06-22.md` provides exact approval fields and evidence destinations for T-1, U-2, U-4, and Play Console actions.
- 2026-06-22 completion proof: `scripts/public_website_completion_gate.sh --json` passes all code-owned checks (`static_quality_gate`, `live_quality_gate`, `live_audit_evidence`) with static 34/34 and live 28/28, and fails on five missing or invalid external artifacts: Google Search Console, Bing Webmaster or deferral, Collect product proof or deferral, translation approval, and Play Console update or deferral. The gate validates Lighthouse JSON scores, approval-file content, browser visual QA, and screenshot PNG dimensions.
- 2026-06-22 CI proof: `.github/workflows/public-website.yml` adds a focused public website gate for static public build generation, local quality checks, IndexNow readiness boundary checks, production live gate, live audit evidence, and code-owned completion checks without requiring owner-gated external artifacts to pass.
- 2026-06-22 evidence workflow: `scripts/public_website_external_evidence_audit.sh` prints the remaining accepted artifact paths; `.template.*` files exist in evidence folders but intentionally do not satisfy the completion gate.
- 2026-06-22 completion report: `scripts/public_website_completion_report.sh` generated `docs/release/COLLECT_PUBLIC_WEBSITE_COMPLETION_AUDIT_2026-06-22.md`; current overall status is `NO-GO` until the strict completion gate passes.

## Closure Rule

Do not mark an item `Closed` unless both repo evidence and live/runtime evidence prove it. A passing local test alone is not enough for findings that explicitly concern deployed crawlability, policy URLs, or live headers.
