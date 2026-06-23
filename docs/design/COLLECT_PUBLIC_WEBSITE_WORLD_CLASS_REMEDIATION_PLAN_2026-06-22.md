# Collect Public Website World-Class Remediation Plan

Generated: 2026-06-22

## Objective

Bring `https://collect.ikanisa.com` to a fintech benchmark standard comparable in quality discipline to Revolut and Stripe while keeping the product and brand fully Collect-owned: Rwanda group savings, MoMo-first access, diaspora saving, credit-readiness, protection, and partner trust.

This plan is for the public website only. It does not replace the mobile app release gates, Admin PWA gates, Google Play policy gates, or human approval requirements for external professional submissions.

## Evidence Used

- Live public website: `https://collect.ikanisa.com/`.
- Live public policy route: `https://collect.ikanisa.com/privacy/`.
- Public website code: `lib/main_public.dart` and `lib/features/landing/collect_landing_page.dart`.
- Public static build pipeline: `scripts/public_landing_prepare_build.sh`.
- Current built artifact: `build/public_web`.
- Current design contract: `DESIGN.md` and `docs/design/DESIGN_SYSTEM.md`.
- Current landing tests: `test/landing_page_test.dart`.
- Current deployment metadata: `docs/release/LIVE_DEPLOYMENTS.json`.
- Supplied audit report, fetched from Google Docs on 2026-06-22:
  - Title: `Collect_IKANISA_Website_Audit`.
  - URL: `https://docs.google.com/document/d/1ldq2DZyIwuDZ-Md-tv14DxFl0U_GvAgi8dxC4x6OWRk/edit?usp=sharing`.
  - Audit date inside report: 22 June 2026.
  - Benchmark set inside report: Stripe, Revolut, Wise, M-Pesa, Tala, and MoMo where relevant.
- Current benchmark readback, checked 2026-06-22:
  - Stripe homepage: short financial-infrastructure promise, immediate actions, product/solution navigation, proof metrics, and case-study trust.
  - Revolut homepage: direct banking proposition, app-first CTA, strong product imagery, customer-scale proof, product-section rhythm, and legal footer discipline.
- Current Core Web Vitals targets from web.dev, checked 2026-06-22:
  - LCP good: at or below 2.5s.
  - INP good: at or below 200ms.
  - CLS good: at or below 0.1.
  - Good threshold should hold at the 75th percentile across mobile and desktop.
- Lighthouse scoring target from Chrome docs, checked 2026-06-22:
  - 90-100 is green.
  - Lighthouse 10 weights TBT 30%, LCP 25%, CLS 25%, FCP 10%, and Speed Index 10%.

## Audit Report Reconciliation

The local downloaded Markdown file at `/Users/jeanbosco/Downloads/Collect_IKANISA_Website_Audit.md` still blocks content reads, but the same report was successfully fetched from Google Docs.

The report's major findings are valid as the remediation backbone:

- `T-1`: Collect is not indexed by Google and is an SEO/discoverability outlier within the IKANISA portfolio.
- `T-2`: the Play privacy URL must resolve as a real policy page, not depend on hash routing.
- `T-3`: the site must work as meaningful HTML without JavaScript.
- `T-4`: structured data and visible fintech trust/security/regulatory signals are missing.
- `U-1`: both core CTAs route only to WhatsApp; there is no self-serve in-browser path.
- `U-2`: current proof is macro-market proof, not Collect product proof.
- `U-3`: the site does not clearly explain how credit-readiness works.
- `U-4`: no Kinyarwanda/French localization despite the target audience.
- `U-5`: the visible brand system is not distinctive enough against top fintech benchmarks.

Current live/code verification also shows the site has moved beyond the report's strictest "empty app shell only" description: the live root now returns static fallback content, and `/privacy/` returns a distinct HTML page with policy text. That is useful progress, but it does not close the underlying benchmark gap because:

- the root still loads and swaps into a 2.56 MB Flutter app bundle;
- hash-route `/#/privacy` remains weak as an official crawler target because the fragment is not sent to the server;
- the static fallback and Flutter-rendered experience are visibly different;
- primary public content still depends on a heavy app runtime for the intended experience;
- SEO, structured data, localization, proof, trust pages, and conversion depth remain incomplete.

## Current Verdict

Status: not benchmark-ready.

The site has credible content ingredients and product scope, but the current implementation is not close to a top-tier fintech website because it mixes a heavy Flutter app shell, a separate static fallback, repeated CTAs, clipped mobile navigation, generic hero structure, weak scan hierarchy, inconsistent caching, missing font coverage, and insufficient visual/performance gates.

The right fix is not small styling polish. The public website needs a dedicated, benchmark-grade marketing/web surface with Flutter kept only where interactive app-like behavior is genuinely needed.

The supplied audit is directionally correct: the strategic problem is not merely aesthetics. It is findability, crawlability, trust, conversion design, localization, and product explanation. The implementation plan below treats the public site as a real fintech acquisition and compliance surface, not as an app-shell side page.

## Key Findings

### P0 - Delivery Architecture Is Wrong For The Public Site

Current evidence:

- The public website is a Flutter web app launched from `lib/main_public.dart`.
- The live bundle is approximately 2.56 MB for `main.0c7fdd583952.dart.js`.
- The build also carries CanvasKit/WASM artifacts, including approximately 6.9 MB `canvaskit.wasm`, 4.9 MB `skwasm_heavy.wasm`, and 3.4 MB `skwasm.wasm`.
- The site serves a static HTML fallback first, then hides it when `flutter-view` appears.

Effect:

- High risk to LCP, TBT, INP, SEO resilience, and perceived quality.
- Public fintech landing pages need immediate, indexable, responsive HTML/CSS with surgical JS, not a full Flutter runtime for primarily static marketing content.

Required direction:

- Move the public marketing website to a static-first implementation.
- Keep Flutter web for admin/app surfaces, not the core public marketing site.

### P0 - Mobile First View Is Not World-Class

Current browser capture at 390x844 showed:

- Header stacks logo, CTA buttons, and a horizontal chip nav.
- Nav chips clip after `Insu...`.
- Hero CTAs repeat below the nav CTAs.
- Product mockup begins too low in the first screen.
- The proposition is readable, but the screen does not feel intentionally composed.

Effect:

- Fails the first-screen bar expected from Revolut/Stripe-class mobile experiences.
- Mobile visitors see clutter and repeated controls before product clarity.

Required direction:

- Replace chip-strip navigation with a compact mobile header and a drawer/sheet menu.
- Keep one primary CTA and one secondary CTA in the first viewport.
- Move product proof into the first screen without forcing a long scroll.

### P0 - Story And Information Architecture Are Not Sharp Enough

Current evidence:

- The hero says `Credit-ready saving for Rwanda's daily economy`.
- Supporting copy tries to cover payment inclusion, ibimina, diaspora, verified ledgers, credit-ready files, collateral rules, and insurance in one paragraph.
- Page sections cover many valid themes but do not yet create a crisp conversion path for a specific visitor.

Effect:

- The user has to work too hard to understand what Collect is, who it is for, and what to do next.
- Stripe and Revolut benchmark pages keep the top promise direct, then unfold depth through controlled sections and proof.

Required direction:

- Rebuild the content model around three primary journeys:
  - Save with a group.
  - Build credit-ready records.
  - Partner with IKANISA.
- Keep diaspora, insurance, and CRaaS as structured solution pages or second-level sections, not competing first-screen ideas.

### P0 - Visual System Is Inconsistent Across Fallback And Flutter App

Current evidence:

- Static fallback first screen differs from the Flutter-rendered first screen.
- Static fallback shows metric cards and policy summary on the home page.
- Flutter app shows more polished product mockups but still uses large generic layout patterns and many card-like sections.
- Public palette adds separate `public*` colors in `CollectColors`, creating a parallel public-site palette outside the core four-primary design discipline.

Effect:

- Users, bots, and browser timing can see materially different experiences.
- The product feels assembled rather than art-directed.

Required direction:

- Create one public-site design system, derived from Collect's approved colors and adapted for web.
- Static fallback and interactive site should be the same surface, not separate experiences.

### P1 - Missing Font Coverage Warning

Current browser logs:

`Could not find a set of Noto fonts to display all missing characters. Please add a font asset for the missing characters.`

Effect:

- Typography may vary across devices.
- Currency, apostrophe, and international text can trigger inconsistent rendering.

Required direction:

- Define a web font policy and ship only needed subsets.
- Use stable fallbacks and test RWF, USSD, apostrophes, and localized terms.

### P1 - SEO And Caching Are Mixed

Current evidence:

- Root page returns `Cache-Control: no-store`.
- `/privacy/` returns `public, max-age=0, must-revalidate`.
- Build script removes `X-Robots-Tag: noindex, nofollow` in generated public output, but `web/_headers` still contains it for the source header template.
- Canonical URLs omit trailing slashes on generated subpages while routes are also served with slash paths.
- Flutter app body text is not ordinary HTML once the app renders.

Effect:

- Crawl, preview, and cache behavior are weaker than they should be for a public fintech website.

Required direction:

- Make generated HTML pages canonical, crawlable, cacheable, and content-complete.
- Keep policy pages stable and Play-review friendly.
- Add a public-web live gate that fails on noindex, canonical drift, cache drift, missing sitemap routes, and non-indexable primary copy.

### P1 - Existing Tests Do Not Enforce Quality

Current evidence:

- `test/landing_page_test.dart` checks text, banned terms, public page existence, and some policy requirements.
- It does not catch mobile nav clipping, first-viewport composition, bundle budget, missing font warnings, fallback/Flutter mismatch, visual hierarchy, or benchmark fidelity.

Effect:

- The site can regress while tests stay green.

Required direction:

- Add public website quality gates:
  - visual screenshots at desktop, tablet, and mobile;
  - first viewport assertions;
  - text overflow and clipped-nav checks;
  - bundle budget;
  - live headers/SEO gate;
  - Lighthouse/PageSpeed target recording;
  - accessibility snapshot and keyboard path.

### P1 - Trust And Legitimacy Signals Are Too Thin

Audit report finding:

- No visible regulatory, security, structured-data, or legitimacy story.
- No BNR engagement status, data-protection contact, security/trust page, dispute explanation, or product reliability statement.

Current repo/live evidence:

- The public privacy content exists, but it reads mainly as Play compliance text.
- `web/_headers` has strong security headers, but users do not see a trust model.
- No Organization, FinancialService, or SoftwareApplication JSON-LD was found in the generated public page.

Effect:

- A fintech product asking users to trust savings records, contribution evidence, and payment references needs visible trust architecture, not just a privacy block.

Required direction:

- Add `/security` or `/trust`.
- Add visible statements for data handling, account deletion, dispute handling, payment-reference handling, and partner/regulatory status.
- Add JSON-LD for IKANISA/Collect.
- Avoid unapproved claims. If BNR, banks, insurers, MoMo, or partners are not formally approved for public mention, use precise non-claim language such as `designed for provider review` rather than implying endorsement.

### P1 - Conversion Path Is Too WhatsApp-Only

Audit report finding:

- `Get the App` and `Create Group` both open WhatsApp with different pre-filled messages.

Current repo/live evidence:

- `_LandingButton` handlers route to `_openWhatsApp(...)` throughout the public site.
- Static fallback CTAs also use `wa.me/250795588248`.

Effect:

- WhatsApp is appropriate for Rwanda and should remain prominent, but it cannot be the only acquisition path if the site is meant to scale, measure, and convert like a benchmark fintech site.

Required direction:

- Keep WhatsApp as support/high-touch channel.
- Add at least one self-serve path:
  - app store badge once live;
  - phone-number/email waitlist;
  - group setup form;
  - partner inquiry form.
- Add privacy-safe funnel instrumentation only after data-safety approval.

### P1 - Product Proof Is Market-Level, Not Collect-Level

Audit report finding:

- The homepage stats describe the market, not Collect's own traction or trust.

Current repo/live evidence:

- Existing public pages contain strong public market sizing, but no verified Collect-specific metrics such as groups onboarded, members served, RWF saved, pilot scope, partner quotes, or reliability.

Effect:

- Macro numbers make the opportunity credible, but they do not prove Collect is credible.

Required direction:

- Use real product proof as soon as it exists.
- If early-stage, use honest pilot proof: onboarding targets, pilot geography, founder/operator quote, or internal reliability goals.
- Keep unverified partner logos and institutional claims out until approved.

### P1 - Localization Is Missing

Audit report finding:

- No Kinyarwanda or French language path exists.

Current repo/live evidence:

- `publicWebsitePaths` has no locale route prefix.
- Visible public-site copy is English-only.
- WhatsApp templates are English-only.

Effect:

- The target audience includes ibimina members, daily earners, moto-taxi customers, local group leaders, and diaspora families. Financial trust is materially weaker when the explanation is not in the user's strongest language.

Required direction:

- Add `/rw/` and `/fr/` public route families, or a static language switcher with localized pages.
- Localize WhatsApp prefill messages.
- Localize privacy/deletion summaries carefully, preserving the English legal source of truth where needed.

### P1 - Credit-Readiness Is Not Explained Enough

Audit report finding:

- The strongest differentiator, `credit-ready saving`, is not explained concretely.

Current repo/live evidence:

- The Flutter-rendered page has more credit-readiness sections than the report's plain retrieval captured, but the first viewport still compresses too many ideas into one paragraph and does not give a crisp mechanism.

Effect:

- A visitor cannot tell what record is created, who accepts it, what consent is required, and what result is not guaranteed.

Required direction:

- Add a plain `How credit-readiness works` section near the top:
  - Save consistently through a group.
  - Collect builds a verified contribution ledger.
  - Group/member consent controls what is shared.
  - Providers review the record; final credit decisions remain with the provider.

## Remediation Goal

Ship a public Collect website that passes these gates:

- Design: senior fintech landing quality, with a first viewport that clearly communicates Collect, shows a real product/use-case signal, and exposes one primary conversion action.
- Benchmark: comparable in discipline to Revolut and Stripe, without copying their assets, trademarks, product claims, or layouts.
- Performance: Core Web Vitals target is LCP <= 2.5s, INP <= 200ms, CLS <= 0.1 at the 75th percentile for mobile and desktop; Lighthouse target is 90+.
- Bundle: public home page critical path should be static HTML/CSS with a strict JavaScript budget. Flutter runtime must not be required for first paint or basic content.
- SEO: all public pages have stable canonical URLs, title, description, OG/Twitter metadata, crawlable primary content, sitemap coverage, and no accidental noindex.
- Accessibility: keyboard navigation, visible focus, semantic landmarks, CTA names, sufficient contrast, no clipped text at mobile or large text, and no color-only status.
- Trust: public claims are evidence-backed, privacy and deletion pages remain Play-compliant, and partner/legal claims avoid unapproved regulated promises.

## Implementation Plan

### Phase 0 - Audit Finding Tracker

Owner: Codex.

Tasks:

- Keep the Google Doc audit URL as the source for the report's exact finding labels.
- Track every report finding through implementation:
  - `T-1` Google indexing / crawlability.
  - `T-2` privacy policy true URL resolution.
  - `T-3` non-JS fallback and low-bandwidth resilience.
  - `T-4` structured data and visible trust/security signals.
  - `U-1` self-serve conversion path.
  - `U-2` Collect-specific proof.
  - `U-3` credit-readiness mechanism.
  - `U-4` Kinyarwanda/French localization.
  - `U-5` distinctive brand and visual system.
- Record for each item: affected route, code owner, content owner, fix PR, validation command, live proof, and residual approval blocker.

Done:

- A report-backed tracker exists and no audit finding is lost during implementation.

### Phase 1 - Define The Benchmark Website Brief

Owner: product/design.

Tasks:

- Lock the target audiences:
  - members and group treasurers;
  - diaspora savers;
  - banks, insurers, cooperatives, and payment partners;
  - Play/privacy reviewers.
- Lock the top-level IA:
  - Home;
  - Group Savings;
  - Diaspora;
  - Credit Readiness;
  - Protection;
  - Partners;
  - Trust / Security;
  - Privacy / Terms.
- Rewrite the first-screen message so it is direct and conversion-oriented.
- Decide CTA hierarchy:
  - primary: self-serve app or group-start action when available;
  - secondary: WhatsApp support;
  - tertiary: partner inquiry;
  - policy CTAs only on policy pages.
- Define claim rules:
  - product metrics must be real and dated;
  - partner/regulator references require approval;
  - no credit approval, insurance coverage, deposit, return, or regulatory authorization claim unless legally approved.

Done:

- Approved copy deck and IA map.

### Phase 2 - Generate A New Visual Direction

Owner: product design.

Tasks:

- Use Image Gen concepts for the full surface, not only the hero.
- Generate section concepts for:
  - home hero;
  - product proof / app interaction;
  - group savings;
  - credit-readiness;
  - diaspora;
  - protection;
  - partner trust;
  - impact/proof;
  - policy/legal template;
  - mobile header/menu state.
- Extract tokens:
  - typography;
  - color;
  - spacing;
  - motion;
  - image/product mockup rules;
  - button and nav states.

Done:

- Accepted concept set and design-system inventory before coding.

### Phase 3 - Rebuild Public Site Static-First

Owner: frontend.

Preferred technical direction:

- Replace the public marketing surface with static-first HTML/CSS generated by a small build script or a lightweight web framework.
- Keep Flutter web for app/admin surfaces.
- Keep deep links and policy pages intact.
- Preserve `https://collect.ikanisa.com/#/privacy` compatibility while also serving clean `/privacy/`.
- Use the BioPay-style separation named in the audit as the target architecture: static landing/privacy/terms/trust pages, interactive app isolated under a dedicated app path.

Tasks:

- Create a public website source tree that does not require CanvasKit for first paint.
- Generate one content-complete HTML file per public route.
- Ensure `/privacy/`, `/terms/`, `/account-deletion/`, `/data-deletion/`, and `/#/privacy` all land users and crawlers on policy text.
- Implement responsive header:
  - desktop: concise nav plus one primary CTA;
  - mobile: logo, CTA, menu button, accessible menu drawer/sheet.
- Implement home with controlled section rhythm and product-led proof.
- Implement solution pages using shared section primitives.
- Implement privacy/account deletion/data deletion/terms as stable static pages.
- Implement `/trust/` or `/security/` as a visible fintech trust surface.
- Implement localized route strategy for Kinyarwanda and French.
- Add canonical, OG/Twitter metadata, sitemap, robots, and structured data where appropriate.

Done:

- Public site works with JavaScript disabled for primary content and policy content.
- Basic CTA links still work without JS.

### Phase 4 - Performance And Cloudflare Hardening

Owner: frontend/platform.

Tasks:

- Create a public-web build gate:
  - fail if JS exceeds budget;
  - fail if CanvasKit/WASM is required for home first paint;
  - fail if generated HTML lacks primary content;
  - fail if canonical/sitemap/robots headers drift.
- Replace root `no-store` with appropriate short revalidation or immutable asset policy.
- Keep immutable hashing for static assets.
- Add compression verification for Brotli/gzip over Cloudflare.
- Add Cloudflare headers for security without blocking required assets.
- Add a web-vitals RUM option only after privacy/data-safety approval, or keep lab-only performance gates until approved.
- Verify the root and policy pages are crawlable through plain `curl`, not only through a browser that runs JavaScript.

Done:

- Lighthouse mobile and desktop are recorded at 90+.
- LCP/INP/CLS targets are met in lab and ready for field monitoring.

### Phase 5 - Accessibility, SEO, And Trust Gates

Owner: frontend/product/legal review.

Tasks:

- Add keyboard and focus-state tests for nav, menu, CTAs, and legal pages.
- Add no-clipped-text checks at 390x844, 430x932, 768x1024, 1280x720, 1440x900.
- Add contrast checks for hero, buttons, cards, footer, and policy pages.
- Add policy-page regression checks for Play requirements.
- Add indexability checks:
  - Search Console sitemap submission evidence;
  - `robots.txt` allow status;
  - no public page has accidental `noindex`;
  - primary H1/body content appears in raw HTML.
- Add claim review:
  - no unapproved lending, insurance, bank, return, or approval promises;
  - public numbers must have source notes;
  - partner language must not imply signed partnerships unless recorded.

Done:

- Public website QA report is green.

### Phase 6 - Deploy And Verify Live

Owner: frontend/platform.

Tasks:

- Build public website.
- Deploy to Cloudflare Workers static assets or the current public project.
- Verify:
  - `/`;
  - `/group-savings/`;
  - `/diaspora/`;
  - `/credit-readiness/` or `/craas/`;
  - `/protection/` or `/insurance/`;
  - `/partners/` or `/our-partners/`;
  - `/privacy/`;
  - `/trust/` or `/security/`;
  - `/#/privacy`;
  - `/.well-known/assetlinks.json`;
  - `/sitemap.xml`;
  - `/robots.txt`.
- Capture desktop and mobile screenshots.
- Record headers, bundle sizes, Lighthouse, accessibility, and SEO evidence.

Done:

- `docs/release/LIVE_DEPLOYMENTS.json` is updated with deployment evidence.
- Public website verdict is `GO` for web quality, with any external/legal approval blockers separated.

## Acceptance Gates

The website is not done until all of these pass:

- First viewport desktop and mobile screenshots approved.
- No clipped mobile navigation.
- No duplicate CTA clutter in the mobile first viewport.
- Static HTML contains the primary content for every public route.
- No CanvasKit/WASM on the public home critical path.
- JS bundle budget passes.
- Lighthouse performance, accessibility, best practices, and SEO are 90+.
- Core Web Vitals lab targets are met or field monitoring is installed and passing.
- Root and route headers pass public-web live gate.
- Policy URLs remain Play-review compliant.
- Landing tests cover first viewport, nav, public routes, banned claims, and policy text.
- Current audit report findings are mapped and closed or explicitly deferred with owner approval.

## Immediate Next Actions

1. Add a report finding tracker for `T-1` through `U-5`.
2. Add a `scripts/public_website_quality_gate.sh --json` gate for current failures: bundle size, CanvasKit presence, raw HTML content, noindex/canonical/caching drift, sitemap routes, structured data, and policy content.
3. Draft the new IA and copy deck with trust, localization, and credit-readiness explanation included.
4. Generate full-page visual concepts for desktop and mobile before implementation.
5. Implement the static-first public site and keep Flutter app/admin separate.
