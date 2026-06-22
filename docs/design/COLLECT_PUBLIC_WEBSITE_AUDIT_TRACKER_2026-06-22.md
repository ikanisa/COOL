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
| T-1 | Critical | Site is not indexed by Google / weak crawlability. | Static-first route HTML, canonical URLs, sitemap, robots allow, Search Console/Bing submission evidence. | `scripts/public_website_quality_gate.sh --json`; raw `curl` route checks; sitemap submission evidence. | In progress | Search Console/Bing account access may require owner action. |
| T-2 | Critical | Privacy policy must be a true retrievable URL, not hash-router-only. | Serve `/privacy/`, `/terms/`, `/account-deletion/`, `/data-deletion/`; preserve `/#/privacy` compatibility with visible policy text. | Raw HTML contains policy/deletion content; live `/#/privacy` and `/privacy/` checks. | In progress | Play Console resubmission requires explicit owner approval. |
| T-3 | High | Hard JavaScript dependency and weak low-bandwidth resilience. | Remove Flutter/CanvasKit from public home critical path; primary content works without JS; minimal progressive JS only. | Gate proves no `flutter_bootstrap.js`, `flutter-view`, `main.dart.js`, `canvaskit`, or WASM on `/` critical path. | In progress | Live deployment verification still required. |
| T-4 | Medium | No structured data or visible fintech trust/security signal. | Add JSON-LD, `/trust/` or `/security/`, data handling, deletion, dispute, reliability, and approved regulatory/partner status language. | Gate checks JSON-LD and trust route; claim review log. | In progress | Any regulatory, partner, or compliance status claim requires owner/legal approval. |
| U-1 | High | CTAs funnel only to WhatsApp. | Keep WhatsApp but add a self-serve app/group/partner path and privacy-safe instrumentation plan. | Gate detects non-WhatsApp conversion link or form; privacy review for analytics/data capture. | In progress | App store badge and data capture depend on Play/privacy approval. |
| U-2 | High | Proof is macro-market proof, not Collect product proof. | Add real Collect traction, pilot, reliability, or transparent early-stage proof. | Dated source notes in content; claim review log. | Open | Product metrics, partner names, and testimonials require owner approval. |
| U-3 | Medium | Credit-readiness mechanism is not clear enough. | Add a near-top `How credit-readiness works` section with consent and no-credit-approval-promise language. | Raw HTML and visual QA show section; banned-claim tests pass. | In progress | Legal/product approval for exact provider-sharing language. |
| U-4 | Medium | No Kinyarwanda/French localization. | Add `/rw/` and `/fr/` or equivalent static localized pages; localize WhatsApp prefill templates. | Gate checks localized routes and language links. | In progress | Translation approval required before final public claim. |
| U-5 | Low | Brand system is not distinctive enough. | Accepted visual concept and static-first implementation with Collect-owned assets, product mockups, mobile menu, and polished first viewports. | Desktop/mobile screenshots at required viewports; visual QA ledger. | In progress | Final design approval. |

## Current Baseline Notes

- Previous live/public build had partial policy progress: `/privacy/` existed and contained policy text, but the home page still loaded Flutter web after the static fallback.
- Previous mobile first viewport had clipped horizontal nav, repeated CTAs, and product proof too low in the screen.
- Previous source `web/_headers` included `X-Robots-Tag: noindex, nofollow`; the new static public generator writes public-specific headers without `noindex` or `no-store`.
- 2026-06-22 local proof: `scripts/public_landing_prepare_build.sh` generated `build/public_web` from `scripts/public_static_site_build.rb`.
- 2026-06-22 local proof: `scripts/public_website_quality_gate.sh --json` passed 31/31 checks.
- 2026-06-22 local proof: generated `build/public_web` includes `/`, `/group-savings/`, `/diaspora/`, `/credit-readiness/`, `/craas/`, `/protection/`, `/insurance/`, `/partners/`, `/our-partners/`, `/impact/`, `/trust/`, `/security/`, `/privacy/`, `/terms/`, `/account-deletion/`, `/data-deletion/`, `/rw/`, and `/fr/`.
- 2026-06-22 local proof: generated public JS is 377 bytes, generated public build has no Flutter/CanvasKit critical-path files and no WASM, and total local build size is about 636 KB.

## Closure Rule

Do not mark an item `Closed` unless both repo evidence and live/runtime evidence prove it. A passing local test alone is not enough for findings that explicitly concern deployed crawlability, policy URLs, or live headers.
