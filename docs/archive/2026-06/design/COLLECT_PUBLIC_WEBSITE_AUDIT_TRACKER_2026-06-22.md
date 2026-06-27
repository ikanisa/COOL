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
| T-1 | Critical | Site is not indexed by Google / weak crawlability. | Static-first route HTML, canonical URLs, sitemap with `lastmod`, robots allow, English-only metadata, Search Console/Bing submission evidence. | `scripts/public_website_quality_gate.sh --json` passed 34/34; `scripts/public_website_live_gate.sh --json` passed 25/25; every sitemap URL has local metadata-complete HTML and every live sitemap URL returns non-empty HTTP 200 content. Sitemap entries use served trailing-slash URLs, the root is `lang="en"` with `og:locale` `en_US`, no `/rw/` or `/fr/` sitemap or `hreflang` advertising exists, and 17 sitemap URLs have `lastmod=2026-06-22`. | In progress | Search Console/Bing submission evidence still requires platform proof or owner-approved deferral. |
| T-2 | Critical | Privacy policy must be a true retrievable URL, not hash-router-only. | Serve `/privacy/`, `/terms/`, `/account-deletion/`, `/data-deletion/`; preserve `/#/privacy` compatibility by redirecting users to `/privacy/` without duplicating policy content on the homepage. | Local gate passes for `/privacy/`, `/terms/`, `/account-deletion/`, `/data-deletion/`, and `/#/privacy` redirect compatibility. Live gate will prove the same after deployment. | Closed locally | None. |
| T-3 | High | Hard JavaScript dependency and weak low-bandwidth resilience. | Remove Flutter/CanvasKit from public home critical path; primary content works without JS; minimal progressive JS only. | Static gate and live gate prove no `flutter_bootstrap.js`, `flutter-view`, `main.dart.js`, `canvaskit`, or WASM on `/` critical path; JS is 377 bytes. | Closed | None. |
| T-4 | Medium | No structured data or visible fintech trust/security signal. | Add JSON-LD, `/trust/` or `/security/`, data handling, deletion, dispute, reliability, and approved regulatory/partner status language. | Static gate and live gate prove valid JSON-LD graph, `/trust/`, `/security/`, security headers, data/deletion/support language, and cautious provider-decision language. | Closed | Future regulatory, partner, or compliance-status claims require owner/legal approval before publication. |
| U-1 | High | Contact and conversion paths must match the current support model. | Use public app-download CTAs plus lean WhatsApp group/support CTAs; do not imply app access requires WhatsApp, and do not publish email support forms or redundant support-option panels. | Static gate proves the root exposes public app download, `Create Group`, and `Get in Touch` with no support panel or email form. Live gate will prove the same after deployment. | Closed locally | Any future analytics/data capture beyond app-store and WhatsApp links requires privacy/data-safety review. |
| U-2 | High | Proof is macro-market proof, not Collect product proof. | Add real Collect traction, pilot, reliability, or transparent early-stage proof. | Dated source notes in content; claim review log. | Open | Product metrics, partner names, and testimonials require owner approval. |
| U-3 | Medium | Credit-readiness mechanism is not clear enough. | Add a near-top `How credit-readiness works` section with consent and no-credit-approval-promise language. | Static gate and live gate prove near-top explainer with consent and `Final credit decisions remain with the provider` language. | Closed | Future provider-sharing copy changes require legal/product approval. |
| U-4 | Medium | Original audit requested localization. | Current owner direction is English-only; remove localized route output, language switcher output, localized `hreflang`, and translation approval as a blocker. | Static and live gates prove the public website is English-only with no `/rw/` or `/fr/` sitemap or `hreflang` advertising. | Closed | Future localization requires a new owner-approved language-scope decision. |
| U-5 | Low | Brand system is not distinctive enough. | Accepted visual concept and static-first implementation with Collect-owned assets, product mockups, mobile menu, and polished first viewports. | Static and live gates pass mobile navigation and first-viewport CSS checks, but fresh Playwright screenshot evidence timed out after the full original-content restore. | In progress | Requires fresh screenshot evidence or owner visual approval. |

## Current Baseline Notes

- Previous live/public build had partial policy progress: `/privacy/` existed and contained policy text, but the home page still loaded Flutter web after the static fallback.
- Previous mobile first viewport had clipped horizontal nav, repeated CTAs, and product proof too low in the screen.
- Previous source `web/_headers` included `X-Robots-Tag: noindex, nofollow`; the new static public generator writes public-specific headers without `noindex` or `no-store`.
- 2026-06-22 local proof: `scripts/public_landing_prepare_build.sh` generated `build/public_web` from `scripts/public_static_site_build.rb`.
- 2026-06-22 local proof: `scripts/public_website_quality_gate.sh --json` passed 34/34 checks, including local sitemap route metadata, sitemap `lastmod` coverage, and English-only output checks.
- 2026-06-22 local proof: generated `build/public_web` includes `/`, `/group-savings/`, `/diaspora/`, `/credit-readiness/`, `/craas/`, `/community-groups/`, `/protection/`, `/insurance/`, `/partners/`, `/our-partners/`, `/trust/`, `/security/`, `/privacy/`, `/terms/`, `/account-deletion/`, and `/data-deletion/`; it does not generate `/rw/` or `/fr/`.
- 2026-06-22 local proof: generated public JS is 377 bytes, generated public build has no Flutter/CanvasKit critical-path files and no WASM, and total local build size is about 636 KB.
- 2026-06-22 deploy proof: `wrangler deploy --name collect-public --assets build/public_web --compatibility-date 2026-06-22 --message "Restore all original Collect public pages"` deployed Cloudflare Workers static assets version `2ca0058b-bd5f-4e21-9d20-5e0f93d38258`.
- 2026-06-22 live proof: `scripts/public_website_live_gate.sh --json` passed 25/25 against `https://collect.ikanisa.com`.
- 2026-06-22 live sitemap proof: `https://collect.ikanisa.com/sitemap.xml` returns 17 absolute trailing-slash URLs, each sitemap URL returns direct HTTP 200 content, every URL has `lastmod=2026-06-22`, and no `/rw/` or `/fr/` URL is advertised.
- 2026-06-22 content restoration proof: the live static root restores the original Collect positioning, `Get the App` and `Create Group` CTA labels, USSD example, ibimina verified-records flow, diaspora/collateral story, embedded insurance section, CRaaS section, and customer journeys while retaining audit fixes.
- 2026-06-22 page restoration proof: `docs/release/COLLECT_PUBLIC_WEBSITE_PAGE_RESTORE_EVIDENCE_2026-06-22.md` records one-by-one live checks for Group Savings, Diaspora, Insurance, CRaaS, Community Groups, Our Partners, Privacy, Account Deletion, Data Deletion, and Terms.
- 2026-06-22 local proof: the homepage no longer carries the redundant policy fallback section; `/#/privacy` compatibility is handled by `site.js` redirecting users to `/privacy/`.
- 2026-06-22 live proof: expanded live gate passes every sitemap route, performance budget, static accessibility, English-only output check, mobile navigation CSS, route-level HTML metadata checks, and sitemap `lastmod` checks; live critical first-party asset bytes were 187,480.
- 2026-06-22 live proof: `scripts/public_website_audit_evidence.sh` saved `output/public_website_evidence/live_audit_evidence.json`; latest completion audit passed with root response 727 ms, root HTML 15,234 bytes, CSS 12,206 bytes, JS 377 bytes, critical first-party bytes 187,480, valid JSON-LD types `Organization` and `SoftwareApplication`, and Cloudflare cache status `HIT`.
- 2026-06-22 browser visual proof boundary: in-app browser and Playwright/Chrome screenshot automation timed out after the full page restore, so fresh screenshot evidence is not claimed for this restore pass.
- 2026-06-22 external ledger: `docs/release/COLLECT_PUBLIC_WEBSITE_EXTERNAL_EVIDENCE_LEDGER_2026-06-22.md` records remaining evidence for Search Console/Bing indexing and Collect-specific proof.
- 2026-06-22 owner sign-off pack: `docs/release/COLLECT_PUBLIC_WEBSITE_OWNER_SIGNOFF_PACK_2026-06-22.md` provides exact approval fields and evidence destinations for T-1 and U-2.
- 2026-06-22 completion proof: `PUBLIC_WEBSITE_EVIDENCE_DIR=output/public_website_evidence scripts/public_website_completion_gate.sh --json` passes all code-owned checks (`static_quality_gate`, `live_quality_gate`, `live_audit_evidence`) with static 34/34 and live 25/25, and fails on seven missing or invalid evidence artifacts: Google Search Console, Bing Webmaster or deferral, Lighthouse mobile, Lighthouse desktop, Collect product proof or deferral, visual approval/screenshot set, and Play Console proof or deferral.
- 2026-06-22 CI proof: `scripts/public_website_ci_gate.sh` is the reusable local/CI entrypoint; `.github/workflows/public-website.yml` adds a focused public website gate for static public build generation, local quality checks, IndexNow readiness boundary checks, production live gate, live audit evidence, and code-owned completion checks without requiring owner-gated external artifacts to pass.
- 2026-06-22 evidence workflow: `scripts/public_website_external_evidence_audit.sh` prints the remaining accepted artifact paths; `.template.*` files exist in evidence folders but intentionally do not satisfy the completion gate.
- 2026-06-22 completion report: `scripts/public_website_completion_report.sh` generated `docs/release/COLLECT_PUBLIC_WEBSITE_COMPLETION_AUDIT_2026-06-22.md`; current overall status is `NO-GO` until the strict completion gate passes.

## Closure Rule

Do not mark an item `Closed` unless both repo evidence and live/runtime evidence prove it. A passing local test alone is not enough for findings that explicitly concern deployed crawlability, policy URLs, or live headers.
