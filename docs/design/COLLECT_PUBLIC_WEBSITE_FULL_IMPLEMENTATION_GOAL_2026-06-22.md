# Collect Public Website Full Implementation Goal

Generated: 2026-06-22

## Goal

Implement the complete Collect public website remediation plan end to end.

Use these as the source of truth:

- `docs/design/COLLECT_PUBLIC_WEBSITE_WORLD_CLASS_REMEDIATION_PLAN_2026-06-22.md`
- `docs/release/COLLECT_PUBLIC_WEBSITE_COMPLETION_AUDIT_2026-06-22.md`
- Supplied audit: `Collect by IKANISA — Website Audit`, dated 2026-06-22
- Current repo design contract: `DESIGN.md` and `docs/design/DESIGN_SYSTEM.md`

The target is a static-first, crawlable, benchmark-grade fintech public website comparable in discipline to Revolut and Stripe, while remaining fully Collect-owned and legally cautious.

## Non-Negotiable Outcome

The work is not complete until:

- `docs/release/COLLECT_PUBLIC_WEBSITE_COMPLETION_AUDIT_2026-06-22.md` shows `Overall status: GO`.
- `scripts/public_website_completion_gate.sh --json` returns `"status": "pass"`.
- `T-1` through `U-5`, Lighthouse/Core Web Vitals, and Play Console boundary items from the completion audit are closed or explicitly deferred with recorded owner approval.
- The public website no longer requires Flutter, CanvasKit, or WASM for the home page critical path.
- Every public route has content-complete HTML available to plain `curl`.
- Desktop and mobile first viewports pass visual QA against the accepted design.
- Core policy URLs remain compatible with Google Play review.
- Performance, SEO, accessibility, security headers, Cloudflare cache behavior, and localization gates pass.
- Deployment evidence is recorded in repo docs.
- Play Console changes are delegated Codex-owned release actions when account
  access, source-of-truth metadata, and evidence are available. Legal/regulatory
  claims and public partner/regulator claims require separate authority outside
  this website implementation goal.

## Completion Audit Closure Requirements

The implementation must close every `NO-GO` and `missing_or_invalid` row in `docs/release/COLLECT_PUBLIC_WEBSITE_COMPLETION_AUDIT_2026-06-22.md`.

Accepted closure evidence is limited to the paths and approval/deferral formats named by that audit:

- Google Search Console sitemap submission or URL inspection proof for `T-1`.
- Bing Webmaster sitemap submission proof, or owner-approved Bing deferral for `T-1`.
- Owner-approved Collect-specific product proof, or explicit product-proof deferral for `U-2`.

Code-owned gates must remain green while those external artifacts are added:

- static quality gate: `34/34`;
- live quality gate: `25/25`;
- live audit evidence: `pass`;
- visual QA and required screenshots present;
- mobile and desktop Lighthouse evidence present and at target;
- Cloudflare cache/header behavior verified live;
- CI guard remains in `.github/workflows/public-website.yml`.

## Scope

### Public Routes

Required public routes:

- `/`
- `/group-savings/`
- `/diaspora/`
- `/credit-readiness/` or retained `/craas/`
- `/protection/` or retained `/insurance/`
- `/partners/` or retained `/our-partners/`
- `/trust/` or `/security/`
- `/privacy/`
- `/terms/`
- `/account-deletion/`
- `/data-deletion/`
- `/#/privacy` compatibility path
- `/.well-known/assetlinks.json`
- `/sitemap.xml`
- `/robots.txt`

### Language

The public website must remain English-only unless the owner later records a
new language-scope decision. Do not generate `/rw/` or `/fr/` public routes,
language switchers, localized `hreflang`, or translation approval blockers for
the current completion goal.

## Workstreams

### 1. Audit Tracker

Create a tracker for every supplied audit finding:

- `T-1`: Google indexing / crawlability
- `T-2`: true privacy URL resolution
- `T-3`: non-JS fallback and low-bandwidth resilience
- `T-4`: structured data and visible trust/security signals
- `U-1`: self-serve conversion path
- `U-2`: Collect-specific product proof
- `U-3`: credit-readiness explanation
- `U-4`: English-only language scope recorded against the original localization finding
- `U-5`: distinctive brand and visual system

Each tracker item must include:

- status;
- affected route or component;
- implementation owner;
- content/legal approval owner when relevant;
- fix summary;
- validation command;
- live proof;
- residual approval blocker, if any.

### 2. Information Architecture And Copy

Create a crisp public website content model:

- one primary home story;
- group savings journey;
- credit-readiness mechanism;
- diaspora journey;
- protection/insurance journey;
- partner/institutional journey;
- impact proof;
- trust/security;
- policy/legal.

The first viewport must answer:

- what Collect is;
- who it is for;
- what action to take now;
- why it is credible.

Add a plain `How credit-readiness works` section:

1. A group saves consistently through MoMo/app-supported workflows.
2. Collect builds a verified contribution ledger.
3. Group/member consent controls what can be shared.
4. Providers review the record; final credit decisions remain with the provider.

### 3. Product Design

Before coding the final visual surface:

- generate or select full-page visual concepts for desktop and mobile;
- include the home hero, solution sections, trust/security page, policy template, and mobile menu state;
- define tokens for typography, color, spacing, radius, motion, buttons, forms, nav, cards, product mockups, and trust badges;
- verify that the design is not a copy of Revolut, Stripe, Wise, M-Pesa, Tala, or MoMo.

Design constraints:

- no clipped mobile nav;
- no duplicate CTA clutter in the first viewport;
- no generic card pile;
- no unapproved partner/regulator badges;
- strong visible product signal above the fold;
- accessible focus and contrast states.

### 4. Static-First Architecture

Replace the current Flutter-first public marketing surface with a static-first website.

Preferred target:

- content-complete HTML/CSS for all public pages;
- minimal JavaScript only for navigation, language switching, forms, analytics, or progressive enhancement;
- interactive app/admin surfaces remain separate from public marketing routes;
- BioPay-style split: static landing/privacy/terms/trust pages plus interactive app under an app-specific path.

Hard requirements:

- no CanvasKit or Flutter bundle required for `/` first paint;
- no `flutter-view` swap for primary marketing content;
- policy pages work with JavaScript disabled;
- `/privacy/` and `/#/privacy` both get users and crawlers to policy text.

### 5. Conversion

Keep WhatsApp, but do not make it the only path.

Add at least one self-serve action:

- app store badge when Play listing is live;
- phone/email waitlist;
- group setup form;
- partner inquiry form.

Any analytics or data capture must be privacy-safe and reflected in Data safety/privacy disclosures before production use.

### 6. Trust, Security, And Claims

Add a visible trust/security surface covering:

- what Collect records;
- how payment references and contribution records are protected;
- account deletion and data deletion;
- dispute/support path;
- data protection contact;
- uptime/reliability target or transparent early-stage statement;
- partner/regulatory status only where approved.

Add structured data:

- Organization JSON-LD for IKANISA;
- SoftwareApplication or FinancialService JSON-LD if claims can be made accurately;
- canonical URLs and social metadata for every route.

Claim rules:

- no credit approval promise;
- no insurance coverage promise;
- no deposit-taking or regulated-status claim unless legally approved;
- no partner logo or endorsement unless approved;
- every public metric is real, dated, and sourceable.

### 7. Quality Gates

Create and run a public website quality gate, preferably:

`scripts/public_website_quality_gate.sh --json`

It must fail on:

- missing content in raw HTML;
- accidental `noindex`;
- missing canonical;
- missing sitemap route;
- missing policy route;
- missing structured data;
- unexpected localized route, language switcher, or localized metadata under the current English-only scope;
- CanvasKit/Flutter on the home critical path;
- JS bundle over budget;
- bad cache/header policy;
- missing security headers;
- broken CTA URLs;
- missing Play policy terms.

Required browser/visual checks:

- 390x844
- 430x932
- 768x1024
- 1280x720
- 1440x900

Required quality targets:

- Lighthouse Performance: 90+
- Lighthouse Accessibility: 90+
- Lighthouse Best Practices: 90+
- Lighthouse SEO: 90+
- LCP: <= 2.5s target
- INP: <= 200ms target
- CLS: <= 0.1 target

If field data is unavailable, record lab evidence and add a future RUM task gated by privacy approval.

### 8. Deployment And Evidence

Deploy only after local gates pass.

Verify live:

- route HTTP 200 status;
- raw HTML content;
- sitemap;
- robots;
- headers;
- Cloudflare cache policy;
- social metadata;
- structured data;
- policy URL compatibility;
- desktop/mobile screenshots;
- performance report;
- accessibility report.

Update:

- `docs/release/LIVE_DEPLOYMENTS.json`
- public website QA report under `docs/design/` or `docs/release/`
- audit tracker status

## Stop Conditions

Stop only when one is true:

- `scripts/public_website_completion_gate.sh --json` returns `"status": "pass"` and `docs/release/COLLECT_PUBLIC_WEBSITE_COMPLETION_AUDIT_2026-06-22.md` is updated to `Overall status: GO`;
- an external approval blocker prevents completion and is recorded clearly;
- a legal/regulatory/product claim cannot be made safely and is replaced with approved neutral language;
- deployment credentials or account access are missing and the blocker is recorded with exact next action.

## Final Done Definition

The final implementation response must include:

- changed files;
- route inventory;
- audit finding closure table;
- quality gate command outputs;
- live URL checks;
- desktop and mobile screenshot evidence location;
- performance/accessibility/SEO verdict;
- unresolved delegated-release, evidence, credential, or account-access blockers;
- explicit `GO` or `NO-GO` for the full Collect public website completion audit.

The full completion audit cannot be `GO` while Google Search Console proof, Bing proof or deferral, or Collect product proof or deferral is missing. Code-owned website quality may be reported separately as green, but it does not close the implementation goal by itself.
