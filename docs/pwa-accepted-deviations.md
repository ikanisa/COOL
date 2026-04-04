# COOL PWA — Accepted Deviations from World-Class Standards

## Purpose
This document records deliberate deviations from the 97-item World-Class PWA Master Checklist with justification, risk assessment, and mitigation strategies.

Resolved on 2026-04-04 and therefore excluded from this deviations list:

- custom service worker registration via Flutter bootstrap
- offline fallback for deep links such as `/admin`, `/profile`, and `/momo`
- path-based routing for hard refreshes
- manifest shortcuts and maskable icons for installability
- in-app install/update UX for Chromium browsers and guided iOS Add to Home Screen flow

---

## Deviation 1: Bundle Size > 150KB gzip

| Property | Detail |
|----------|--------|
| **Checklist Item** | Performance #7: "Bundle < 150kb gzip" |
| **Priority** | Essential |
| **Current State** | Flutter Web WASM + CanvasKit = ~2–4 MB compressed |
| **Root Cause** | Flutter's rendering engine compiles to WASM and includes CanvasKit (Skia). This is architectural — not reducible via tree-shaking or code splitting. |
| **Risk** | Slower initial load on low-bandwidth connections (3G in rural Rwanda: ~8–12s FCP) |
| **Mitigation** |
| | • Aggressive asset caching via service worker (subsequent loads are near-instant) |
| | • Firebase Hosting CDN with Brotli compression enabled |
| | • Immutable cache headers for static assets (`Cache-Control: public, max-age=31536000, immutable`) |
| | • Native splash screen covers WASM init time |
| | • Consider `--wasm` optimization flags in future Flutter releases |
| **Decision** | **Accepted.** Flutter Web's rendering model provides consistent cross-browser rendering and eliminates CLS entirely. The trade-off (large initial payload) is acceptable for an authenticated utility app where users visit repeatedly. |
| **Review Date** | 2026-Q3 (reassess when Flutter Web compile size improves) |

---

## Deviation 2: No SSR/SSG for App Routes

| Property | Detail |
|----------|--------|
| **Checklist Item** | SEO #1: "SSR or SSG content" |
| **Priority** | Essential |
| **Current State** | Flutter renders to `<canvas>` — crawlers see an empty `<body>` |
| **Root Cause** | Flutter Web does not support server-side rendering. The entire UI is drawn to a canvas element via WebGL/WASM. |
| **Risk** | Search engines cannot crawl app routes; social previews show only static OG tags from `index.html` |
| **Mitigation** |
| | • Static legal/marketing pages served via separate `hosting/` directory (normal HTML, fully crawlable) |
| | • Open Graph + Twitter Card meta tags in `index.html` provide rich social previews |
| | • `robots.txt` and `sitemap.xml` point crawlers to crawlable static pages |
| | • For future share-able routes (group invites), consider a prerender microservice or Firebase Dynamic Links |
| **Decision** | **Accepted.** COOL is primarily an authenticated utility app, not a content/discovery site. SEO for authenticated views is irrelevant. Public-facing content (legal, marketing) is handled via static HTML. |
| **Review Date** | 2026-Q4 (if group invite share links become a growth channel) |

---

## Deviation 3: CWV in Google Search Console Not Registered

| Property | Detail |
|----------|--------|
| **Checklist Item** | SEO #8: "CWV passing in Search Console" |
| **Priority** | Essential |
| **Current State** | Not registered |
| **Root Cause** | The app is behind authentication — Search Console can't access most routes. CWV field data requires real-user traffic to pages that Google indexes. |
| **Risk** | No visibility into real-world CWV metrics |
| **Mitigation** |
| | • Lighthouse CI runs monthly mobile audits against the production URL |
| | • PageSpeed Insights can be run manually for the landing page |
| | • Real User Monitoring (RUM) can be added via Firebase Performance SDK in Flutter |
| **Decision** | **Accepted.** Register GSC for the static hosting domain (`cool.ikanisa.com`) but document that the main app domain (`cool.app`) will have limited CWV data due to authentication wall. |
| **Review Date** | 2026-Q3 |

---

## Deviation 4: Limited Screen Reader Testing Evidence

| Property | Detail |
|----------|--------|
| **Checklist Item** | UX #5: "Screen reader tested (VoiceOver/TalkBack)" |
| **Priority** | Essential |
| **Current State** | `Semantics` widgets applied to key UI components; one accessibility test exists |
| **Root Cause** | Flutter Web canvas rendering has inherent accessibility challenges — the Semantics tree is parallel to the visual tree, and not all screen readers interact perfectly with canvas-based UIs. |
| **Risk** | Screen reader users may encounter navigation issues |
| **Mitigation** |
| | • `Semantics` widget applied to all state views, buttons, text fields, list items |
| | • `MergeSemantics` used for grouping |
| | • Accessibility test coverage for text scaling and touch targets |
| | • Periodic manual VoiceOver testing on macOS Safari + iOS Safari |
| **Decision** | **Partially accepted.** Continue expanding `Semantics` coverage. Conduct quarterly manual VoiceOver/TalkBack audits and document findings. |
| **Review Date** | Quarterly |

---

## Deviation 5: Font Preload for Flutter (Not Applicable)

| Property | Detail |
|----------|--------|
| **Checklist Item** | Performance #10: "Preload critical fonts" |
| **Priority** | Essential |
| **Current State** | `GoogleFonts.config.allowRuntimeFetching = false` — fonts are bundled in the WASM assets |
| **Root Cause** | Flutter bundles fonts into the compiled asset graph. Traditional `<link rel="preload" as="font">` tags in HTML don't apply because Flutter loads fonts via its own asset pipeline after WASM init. |
| **Risk** | FOIT (Flash of Invisible Text) during initial WASM load — but this is covered by the native splash screen |
| **Mitigation** |
| | • Native splash screen covers the entire WASM + font loading period |
| | • `preconnect` hints for Google Fonts APIs added to `index.html` as defensive measure |
| | • Font files will be served from CDN cache on repeat visits |
| **Decision** | **Accepted.** Not technically possible in Flutter Web's rendering model. Splash screen provides visual coverage. |
| **Review Date** | N/A (architectural limitation) |

---

## Summary Table

| # | Checklist Item | Severity | Status | Next Review |
|---|---------------|----------|--------|-------------|
| 1 | Bundle < 150kb gzip | Essential | Accepted | 2026-Q3 |
| 2 | SSR/SSG content | Essential | Accepted | 2026-Q4 |
| 3 | CWV in Search Console | Essential | Partial | 2026-Q3 |
| 4 | Screen reader tested | Essential | Partial | Quarterly |
| 5 | Font preload | Essential | Accepted | N/A |

---

## Review Process
- All deviations are reviewed quarterly by the engineering lead
- If Flutter Web releases reduce bundle size significantly, Deviation #1 should be re-evaluated
- New Essential items failing compliance must be documented here with justification before merging
