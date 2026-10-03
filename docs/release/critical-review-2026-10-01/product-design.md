# Collect product, UI/UX and accessibility critical review

> Owner scope amended 1 October 2026: use revolut-design directly as the sole design skill. The separate mandatory mobile checklist and its gates were removed. Changed package bytes are outside previous integrity attestations; dated product observations retain their original scope.

Review date: 1 October 2026, Africa/Kigali; affected-input refresh at 17:36:55 UTC (19:36:55 Kigali). Scope: current dirty COOL checkout, member Android/iOS application, authenticated Admin web/PWA, static public website and Flutter public fallback. This is a source and evidence review with targeted image inspection and two fresh deterministic read-only checks, refreshed only after their inputs changed. It is not a whole-product usability study, WCAG conformance statement, deployment review or release approval.

## Decision and evidence boundaries

**Production UI/UX acceptance is unverified and the public website has confirmed source-level gaps.** The selected `revolut-design` skill remains the sole design authority. Current Android/iOS release-artifact comparisons remain unverified. The product already has useful shared primitives, clear MoMo handoff boundaries, recovery surfaces, responsive Admin tables, and scoped browser accessibility/lifecycle evidence. Those investments should be retained. The required next step is to reconcile the supported product claims, close the specific public/privacy defects, bind current screenshots to current source, then obtain the missing route/state and release-artifact evidence.

Five results remain separate: source fidelity, task usability, accessibility, performance and runtime resilience. No percentage is assigned; this review has neither an accepted all-case denominator nor complete state-matched comparison evidence. Missing evidence is not a proved runtime bug, and a golden match is not visual acceptance.

The product boundary is `docs/PRODUCT.md:1-27`: Rwanda, RWF, MTN MoMo/Airtel USSD; verified WhatsApp sign-in; Android-specific creation/consent/Integrity; no wallet, customer-deposit custody, MoMo PIN or provider OTP collection; independently reconciled settlement or an approved constrained finality policy before production-confirmed contributions. Credit/insurance/partner services appearing in marketing need their own supported-capability and approved-availability evidence.

## Review method and actual coverage

Read the selected skill's entrypoint and `DESIGN.md`, `quality-standard.md`, `operational-checklist.md`, mobile patterns/current native atlas/native findings, web patterns, typography and PWA/accessibility references. Reviewed member and Admin router declarations, public route declarations/static generator, shared themes/typefaces, monetary input and review, confirmation sheet, state/recovery components, Admin table semantics/reflow, authentication entry, Settings/deletion, public legal source and metadata/CSS. Broader file inventory was used to locate relevant code; manual code inspection was targeted, not a claim that every Dart line or generated evidence snapshot was read.

Current declarations: **37 member route patterns**, **28 Admin route patterns**, **9 Flutter-public paths**, and **11 static primary pages plus 4 alias pages and 3 share landing pages**. A route pattern is not a route/state/platform/role acceptance case. Member auth, profile completeness, public/private membership, owner/member, MTN/Airtel, SMS permission and platform capability, loading/error/stale/offline, current/light/dark/system/high contrast, text scale, keyboard and orientation must be added only where applicable. Android-only creation requires iOS unavailable/redirect proof rather than a fabricated iOS creation flow.

Fresh checks executed here:

1. **Original observation, before the new 17:34:05 UTC manifest:** read-only `PublicAppMedia#screens` validation failed, exit 2, `App screenshots need recapturing: runtime changed`. Browser graph fingerprint `f1d2cc0cf15008d3ae7da70ca8610fe70f7330f254b6f419105711f578c28a7f`; published fingerprint then `633f345f03320b803f45f2f594d2a212d8c32adb42318ccd25a88b73eb91bcb6`. **Refreshed at 17:36:55 UTC after external publication:** validation now passes, exit 0, both fingerprints are `f1d2cc0cf15008d3ae7da70ca8610fe70f7330f254b6f419105711f578c28a7f`, and all seven registered screens validate. The original stale-input build prerequisite has been locally corrected. This does not certify fresh static build/rendered/browser/native acceptance. Original command wall-clock time was not separately retained; it must not be invented from later report timestamps.
2. Evaluated only the static generator's definitions, stopping before its build/mutation boundary, then called `legal_page_html` for deletion/privacy. **Original and refreshed 17:36:55 UTC output agree:** deletion copy promises a form and contains the request-submit label, but the generated section contains **0 form tags and 0 input/select/textarea tags**. Privacy section emits `/subprocessors/`, `/privacy-request/`, `/cookies/` and `/account-deletion/` internal links. Three destinations remain explicitly retired in the quality gate. Current static builder hash `4e744b453e1ac3ddaa7c0032eda548ee94007a486a7fe18971ce3b3ae8d71f90` differs from root's 17:28 baseline `af090a720ec41f40f225e09f1d9be2750ad8794481fc46e56e2d658c70733e6a`, and matches this review's original stored source readback. Only baseline hashes were available; no reconstructed old source or textual delta is claimed. Current applicable claim text was reread. No browser permission denial was bypassed, no credentials were used, and no provider/network action was sent.

Fresh analyzer, release gates and regression execution are owned by the integrating reviewer. Its analyzer passed; the selected regression suite recorded 123 passes and one desktop public golden failure (302,702 differing pixels, approximately 23.36%). That regression mismatch needs visual review against current product/selected source; it is not a Revolut-fidelity percentage and should not be dismissed by automatically regenerating the baseline. The current prior-evidence readback found that eight Flutter/theme/table/landing/font inputs differ from the latest integrated packet; its old visual and lifecycle passes must not be represented as a current all-source pass.

The integrating reviewer also supplied two fresh packets, which were read directly here: `public-live.json` at 17:31:39 UTC reports 33/36 checks passed, content-evidence drift, four broken privacy/terms links, and one root GET exceeding the script budget at 1,706ms. This single HTTP timing is not LCP/INP/CLS or field Core Web Vitals. `design-authority.json` reports a failure for one obsolete competing declaration in an ignored cache JSON after 65,055 reference files were scanned; it does not show a competing current runtime palette and its skill revision check is `not_requested`. Neither packet grants visual acceptance.

## Images actually inspected

All listed product images were opened as images, not judged from filenames. Private source pixels were inspected locally and are not copied into this repository or reproduced in this report. File timestamps are not capture/build proof.

| Image | Evidence age/kind | Actual observation and limit |
| --- | --- | --- |
| `test/goldens/baselines/member_home_dark.png` | Historical Android-flavored widget fixture at 390×844; Sept updates documented in golden README | Blue Home, prominent whole-RWF total, three quick actions, grouped activity, photographic group card and floating four-tab navigation. No native/current-release proof. |
| `test/goldens/baselines/member_groups_dark.png` | Historical Android widget fixture; group photography reviewed September | Teal family, pill search, create/filter commands, full-width photo cards and overlaid title/value/member count. Scroll/recovery and current membership branches unverified by the still. |
| `test/goldens/baselines/member_contribution_review_dark.png` | Historical Android widget fixture | Quiet black review, exact RWF amount, payee/number, PIN safety message, USSD action and Edit amount. Good financial-review anatomy; current provider execution/finality unverified. |
| `test/goldens/baselines/member_auth_dark.png` | One of five reviewed refreshes dated 1 Oct in README; fixture, not release | Blue-indigo login, Rwanda prefix, stable disabled action. Keyboard, OTP paste/autofill, timeout/resend and spoken guidance need separate evidence. |
| `test/goldens/baselines/member_offline_dark.png` | One of five refreshes dated 1 Oct; fixture | Refresh/view groups, unavailable last-refresh timestamp, explicit refresh-does-not-resend-payment/SMS guidance. This is a synthetic state, not an observed network outage. |
| `test/goldens/baselines/member_profile_dark.png` | Historical Android widget fixture | Bright violet/blue identity with grouped Account details, Notifications, App permissions, Appearance, Security, Privacy policy, Terms, Help. Confirms public deletion instructions use different menu terminology. |
| `test/goldens/baselines/member_appearance_dark.png` | Historical Android widget fixture | Miniature Home preview and Dark/Light/System choices. The intentionally non-scaling illustrative preview is not evidence that actual app text scaling is disabled. |
| `test/goldens/baselines/admin_overview_desktop.png` | 1 Oct refreshed fixture, 1440×900 | Persistent operator workspace, navigation, unavailable/access-denied operational measurements with refresh actions, queue summaries. Coherent operator adaptation; no authenticated Business table comparator or all-route proof. |
| `test/goldens/baselines/public_home_desktop.png` | 1 Oct refreshed **Flutter-public** fixture, 1440×900 | Rwanda MoMo proposition over local editorial image, app/group CTAs. It depicts the Flutter fallback, not the static website whose current source advertises broader microsavings/insurance/credit services. |
| Private `native-current-20260905/020-home-current-clean.jpg` | 5 Sept 2026 iPhone Mirroring, Dark · Glow; installed build and region unknown | Blue hero, compact commands, dominant value, actions, grouped widgets and floating tabs. Original raster includes phone/Mirroring frame; do not treat its pixels as logical units or export account content. |
| Private `native-current-20260905/030-revpoints-editorial-lower.jpg` | Same source cohort | Full-width photographic cards, over-image content, continued scroll and persistent navigation support the editorial-card pattern. Different route/business purpose is a required Collect adaptation. |
| Private `assets/public-business/enterprise.png` | Official Business promotional asset preserved Sept 5 | Bulk-transfer pending-review composition. It does not show a working Admin table or prove selection, approval, sorting, focus, permissions or narrow-layout behavior. |

The old `/Users/jeanbosco/Desktop/Revolut/Cards.png` location was checked and is absent. Available current private originals were used without silently substituting them for a missing historical comparator. Public [Business 5 source](https://www.revolut.com/business/rb5/) was read for the operator context. Exact native fonts, authenticated source desktop geometry, source interaction timings and complete unseen state/theme references remain unknown. These observations do not establish a measured material mismatch for each Collect screen.

## Findings with actionable closure

Severity describes the consequence within the declared scope. “Confirmed source defect” means deterministic source/generated-output evidence; “evidence gap” means the needed runtime or external proof is absent/stale; “candidate risk” means a specific code mechanism warrants a focused reproduction.

### PD-01 — High: complete mobile and cross-surface visual acceptance is still unverified

**Evidence gap.** `docs/release/revolut-design/acceptance-status.json:8-38` leaves all ten mobile dimensions, complete Admin/public comparison, independent review and owner acceptance unverified. `verification/RECOVERED_NATIVE_CAPTURE_88F.md:7-11` says seven recovered iOS fixture images have 116 changed exported inputs, 76 conservatively native-related changes, 52 new Dart files, and no installed/retained equality. Current native release candidates cannot inherit those captures. The owner requirement cannot be closed with route lists or 13 fixture goldens.

**Effect:** supported device/state combinations can differ materially even when a sampled fixture looks coherent; an exact-fidelity or production UI acceptance claim would exceed the evidence.

**Recommendation:** generate material cases from current production routes/capabilities; register state-appropriate direct/pattern comparators or explicit adaptations; freeze current source, install/read back the exact release candidate, capture settled renderings and verify target task outcomes. Keep implementer, independent visual review and owner acceptance distinct. **Owner:** design lead, native QA, release owner. **Closure:** review current Android/iOS implementations directly against the selected Revolut skill, supported target tasks and applicable references; record the tested source, artifact and observed differences without a separately named checklist gate.

### PD-02 — High: public screenshot provenance failure was locally corrected during review

**Original confirmed failure; current local prerequisite corrected at 17:36:55 UTC.** The failed fingerprint result remains recorded above. New `web/public/app-screens/manifest.json` generated at 17:34:05 UTC and refreshed provenance now pass `PublicAppMedia#screens` for all seven frames. `scripts/public_app_media.rb:169-184` remains fail-closed; no validation weakening was observed. `scripts/public_static_site_build.rb:1379-1384` consumes those screens for public pages. The scope remains browser fixtures; a current caption/fingerprint cannot establish native release acceptance.

**Effect:** the original stale-input block prevented accepted media/build reuse. That particular local block is resolved by the refreshed publication; separately, current full static rendered proof and native release acceptance remain unverified in this slice.

**Recommendation:** retain the new canonical provenance and original failure; avoid another recapture unless relevant inputs change. **Owner:** product-media/release engineer. **Closure achieved locally:** validator passes on current graph and validates all seven screen/provenance records. **Separate remaining proof:** generated static build, served media/font readback and affected browser-route checks must bind those same files. This report does not assert that those downstream checks were rerun.

### PD-03 — High: selected marketing font distribution rights remain unverified, and native declaration widens its payload

**Evidence gap with confirmed bundle declaration.** `pubspec.yaml:82-87` declares Aeonik Pro 400/500 globally, `collect_runtime_typography.dart:9-11` selects marketing roles, `web/public/revolut.css:1-5` uses them, and the static generator copies them at `:28-33`/`:1940-1952`. `assets/marketing/SOURCE.json:94-125` traces decompressed website WOFF2 files and explicitly says local owner implementation authorization does **not** certify licensing. The local license declaration includes Inter OFL only (`pubspec.yaml:76-77`). These are full Pro faces, not the trial files; trial restrictions are not the reason for this finding.

**Effect:** local implementation authorization/provenance cannot establish external app/web redistribution permission. Global Flutter font registration also puts marketing-only files into native/Admin outputs unless the actual build demonstrably excludes them; family choice alone does not exclude bytes.

**Recommendation:** obtain and retain the exact app/web permitted-use scope or select an explicitly approved licensed fallback under the sole authority; separate marketing-only declarations/build payload where appropriate. Preserve current local work pending the rights decision; do not delete assets based solely on this report. **Owner:** asset-rights owner, design lead, release engineer. **Closure:** documented grant for exact hashes/use scope and actual signed/native/Admin/static artifact readback; or approved fallback plus reviewed geometry and honest fidelity difference.

### PD-04 — High: public deletion page promises a form but renders a specification

**Confirmed generated-output defect.** `content/legal/collect_delete_account.yaml:26-66` tells people to complete a form and declares inputs/submit action. `scripts/public_static_site_build.rb:759-764` and `:825-838` instead render headings, “Optional field” cards and option lists. Fresh pure rendering confirms zero form/control tags. The global footer still offers support, so this is not proof that all deletion requests are impossible.

**Current refresh:** reread current generator and reran pure legal rendering at 17:36:55 UTC after reported source drift; promise, submit-label text and zero actual form/control tags remain. PD-04 is still open.

**Effect:** a person following the prominent no-app deletion instructions cannot submit the promised request and may believe the descriptive cards are a broken interface. The page cannot provide the claimed self-service outcome.

**Recommendation:** either implement a real accessible, protected request flow with identity verification/acknowledgment/receipt/status and explicit retention, or make the currently supported support channel the primary truthful action and remove form promises. Do not collect sensitive identity documents without the actual protected workflow. **Owner:** privacy/product, web engineer. **Closure:** observed no-app synthetic request completes or reaches an explicit supported support channel; failure and duplicate-submit recovery work; confirmation identifies request vs completed deletion; applicable labels/error/privacy tests pass.

### PD-05 — High: privacy policy emits links to intentionally absent destinations

**Confirmed generated/source inconsistency.** Fresh privacy rendering emits `/subprocessors/`, `/privacy-request/`, `/cookies/`. `content/legal/collect_privacy_policy.yaml:244` includes the subprocessor path. Link rendering preserves internal destinations at `scripts/public_static_site_build.rb:776-791`. The quality gate explicitly requires these routes absent at `scripts/public_website_quality_gate.sh:164-171`; the static page catalogue defines none of them and redirects at builder `:1933-1935` do not repair them.

**Current refresh:** the 17:36:55 UTC pure generator output still contains all three retired destinations. PD-05 remains open in current local source. The four live HTTP404 results remain the separately dated 17:31:39 UTC observation; no new deployment or live correction is inferred from a local media refresh.

**Effect:** public privacy information points users toward unavailable notices/request channels. The integrating reviewer's fresh `public-live.json` confirms four published links return HTTP 404: three from Privacy and `/cookies/` from Terms, among 217 links/19 destinations checked. Source and live evidence therefore agree for these destinations.

**Recommendation:** repair destinations to working current pages/anchors/channels and revise the canonical legal bundle consistently, or implement the intentionally supported notices rather than resurrecting retired design references. Add link validation to the generated legal page graph. **Owner:** privacy/content and web engineer. **Closure:** every generated legal link resolves to intended content in the exact served build and public live GET/readback; privacy-request outcome works where promised.

### PD-06 — Medium: deletion instructions use a menu path that the app does not expose

**Confirmed terminology/route mismatch.** Legal source says `Profile → Settings → Privacy and Security → Delete Account` at `collect_delete_account.yaml:14-22`; privacy/terms/bundle repeat it. Current Profile/Settings entries are Account details, Security and Privacy policy (`settings_screen.dart:22-61`). Security's `Delete data` row opens `/settings/account/delete` at `settings_subscreens.dart:376-380`; Help's privacy/deletion row also opens it at `:440-444`. There is no combined Privacy and Security entry in these inspected menus.

**Effect:** a user needing account deletion follows instructions to a nonexistent label. It is avoidable friction in a rights-sensitive task.

**Recommendation:** use the app's actual labels/path in one canonical instruction source, preserving the existing supported route. **Owner:** product/content. **Closure:** an unassisted user follows the published instructions on each supported platform to the real request screen; public/app/legal bundle text agrees.

### PD-07 — High: static marketing's available-service language exceeds the current product contract

**Confirmed source inconsistency; provider availability unverified.** Static home advertises access to loans, readiness services and microinsurance (`public_static_site_build.rb:99-115`), basic-phone/assisted USSD (`:55`/`:80`), and insurance language says Collect “works with licensed insurers” (`:134`) with benefit payout descriptions (`:155-159`). `docs/PRODUCT.md` describes a Rwanda MoMo group-contribution record system and leaves payment/provider acceptance distinct. Flutter-public golden/source presents Rwanda MoMo contributions. No named current licensed-insurer arrangement or working non-smartphone Collect journey was verified in this slice.

**Current refresh:** these applicable home/FAQ/insurance statements were reread from the current builder at 17:36:55 UTC; they remain. PD-07 is still open, subject to product/provider evidence rather than an assumption that all broader partner information is prohibited.

**Effect:** visitors can confuse provider/product direction with a service they can use now. Qualified footer wording does not automatically clarify the availability of each advertised benefit.

**Recommendation:** reconcile current, assisted, planned and provider-dependent claims against one approved capability/availability register with evidence, eligibility, geography and real next action. Retain legitimate broader business information when supported; do not infer that every marketed partner service belongs in the app. **Owner:** product owner, content/partner owner. **Closure:** approved capability facts, named availability evidence where needed, coherent public/fallback/store/help wording, and observed conversion paths for each advertised active service. Accuracy supports store review as well as trust; [Apple's review guidance](https://developer.apple.com/app-store/review/) requires final content and functioning support/privacy links.

### PD-08 — High: new financial pending/error messages lack an explicit announcement and input-error association

**Confirmed source mechanism; spoken failure is not reproduced.** Contribution flow inserts `_NativeMomoStatus` after USSD/failure (`contribution_flow_screen.dart:222-235`); that widget is a plain Container/Row/Text (`:810-851`) without a live status semantic or focus transfer. Amount validation renders separate plain Text (`:550-558`), while the field label is separate (`:536-547`) and InputDecoration has no error association (`:968-975`). Other shared components have dedicated semantics; this specialized flow bypasses them.

**Effect:** screen-reader users may not be informed that a handoff became pending or failed, or why the amount did not progress, while focus remains on the action/field. This is a material access risk in the primary payment journey.

**Recommendation:** use a shared meaningful status semantic, associate the amount error with its field, keep actionable controls independently reachable and prevent duplicate/chattery announcements. Reuse the established component convention rather than building a new accessibility layer. **Owner:** mobile/shared UI engineer, accessibility reviewer. **Closure:** semantic test verifies status/error association, then actual TalkBack/VoiceOver task checks hear each relevant transition once and can correct/retry without re-entering unrelated data. W3C's [status-message explanation](https://www.w3.org/WAI/WCAG22/Understanding/status-messages.html) covers waiting/errors without focus changes; Flutter recommends [actual reader testing](https://docs.flutter.dev/ui/accessibility).

The repository's release-responsibility gate explicitly marks reader traversal removed from its release scope (`native_mobile_accessibility_signoff_gate.sh:194-195`). This report does not reinterpret that choice as a newly mandatory permission gate. It records that a source/semantics pass cannot establish spoken usability or satisfy the selected skill's complete `accessibility_native` claim; the release-scope policy and design-acceptance claims need an explicit reconciliation.

### PD-09 — Medium: amount text can shrink substantially to fit instead of honoring enlargement

**Confirmed code behavior; layout failure remains a focused reproduction task.** `_NativeCurrencyInput` measures current digits and multiplies font size by 0.94 up to 40 times (`contribution_flow_screen.dart:940-959`), without an explicit readable minimum. The RWF formatter accepts up to 16 digits (`collect_financial_amount_entry.dart:340-346`). Currency moves to a separate line at scale ≥1.3 (`contribution_flow_screen.dart:980-984`), but the digits still shrink. The repeated fit loop can counteract the user's larger text preference. App-bar group title also remains one-line ellipsis (`:478-486`); full payee identity must remain discoverable elsewhere.

**Effect:** a long monetary value can fit while becoming difficult to read, undermining material-facts review. Source inspection alone does not prove a specific supported payment-limit case fails accessibility.

**Recommendation:** define the actual MoMo/product amount limits, preserve visible whole-value precision with a readable minimum, and adapt available layout before font reduction. Any justified finite-size fallback needs explicit tested bounds and an honest design adaptation. **Owner:** financial UI/shared components engineer. **Closure:** compact/large phone, 200%/maximum-supported text, keyboard-open and valid-boundary amount cases preserve all digits and useful enlargement. W3C [Resize Text](https://www.w3.org/WAI/WCAG22/Understanding/resize-text.html) requires resize without loss of content/functionality; it is a web baseline, with native checks conducted separately.

### PD-10 — Medium: Flutter/Admin PWA metadata still describes EUR/SEPA

**Confirmed metadata defect.** `web/manifest.json:8` describes EUR group contributions by SEPA bank transfer. The active product is Rwanda RWF MoMo; the static builder creates a different microsavings manifest (`public_static_site_build.rb:1977-1994`). `web/robots.txt` denies crawling, which is appropriate for the private/Admin shell and should not be blindly changed; the static builder generates a separate public allow/sitemap file at `:1937`.

**Effect:** install/accessibility metadata misrepresents the product rail and currency and can confuse operator/member expectations. Static marketing SEO is a separate build.

**Recommendation:** give each produced surface accurate product identity, supported rail/currency and start/scope metadata through its existing build path. **Owner:** web/PWA release engineer. **Closure:** actual generated manifests and installed browser identities read back truthful text, icons, scope and deep-link entry for public and private origins.

### PD-11 — Medium: design case inventory omits three current Admin routes

**Confirmed evidence drift.** Current `adminRoutePaths` includes entity audit, SMS gateway and exceptions (`admin_router.dart:36-42`) and has 28 entries. `docs/release/revolut-design/route-inventory.json:53-79` has 25 entries and omits them. The record correctly says its acceptance is unverified, but it cannot be the complete comparator case source. Member 37 and fallback 9 match declaration counts in this slice.

**Effect:** sensitive operator journeys can be omitted from visual, permission, keyboard, narrow-layout and state testing even when a historical matrix was complete.

**Recommendation:** derive route inventory from the existing canonical router and add material state/platform/role expansions; retain aliases and explicit unsupported states. **Owner:** QA/design integrator. **Closure:** generated inventory matches active router declarations and every supported state links to reviewed evidence; deletion of cases requires a supported-capability reason.

### PD-12 — Medium: typography and public acceptance summaries describe superseded input states

**Confirmed documentation/evidence drift.** `acceptance-status.json:44` calls marketing an Inter fallback while current runtime/static source uses restored Aeonik; `:40-41` records blocked static/browser state without binding later input changes. The public content/font report dated later in the day records a source hash and preserved 15-page copy (`verification/public-content-font-adapter-review.json:3-8`, `:86-88`), yet does not certify fonts/license/native output or whole-surface acceptance. Multiple frozen attempts contain legitimate but different conclusions.

**Effect:** a reader can select an older pass or wrong font story and mistakenly treat it as current readiness. Keeping prior evidence is useful; an ambiguous current index is not.

**Recommendation:** retain historical packets, but produce one current index per candidate that records exact source scope, artifact, result, superseded packet and still-open gates. Amend status rather than rewriting old outcomes. **Owner:** release/QA integrator. **Closure:** current index machine-checks relevant source/transitive inputs and exact artifacts, and identifies independently validated vs unverified areas without contradictory current-state claims.

### PD-13 — Medium: receipt copy does not expose the full production finality boundary

**Confirmed product-copy inconsistency.** `collect_localizations.dart:67-69` says contribution stays pending until consented Android receipt is parsed/allocated or an administrator reconciles an exception. `settings_subscreens.dart:363-366` says confirmed MoMo receipts update contributions. `docs/PRODUCT.md:15-17` separately requires independent settlement evidence or an approved constrained finality policy before production confirmation. The review screen correctly says PIN approval occurs in the network prompt; that distinction should be retained.

**Effect:** users may expect successful receipt parsing to be the complete production-confirmation condition. Changing words cannot repair backend finality, but consistent pending/confirmed language is needed once the financial contract is settled.

**Recommendation:** resolve finality semantics with the backend/product owner, then apply shared truthful received/pending/reconciled/confirmed wording and recovery actions across flow, Activity, notifications, Admin and public copy. **Owner:** financial product/backend and content owner. **Closure:** actual handoff→candidate receipt→settlement/approved-policy→ledger task shows only supported states; duplicate, ambiguous, unmatched, delayed and reversed outcomes remain truthful. [W3C financial error prevention](https://www.w3.org/WAI/WCAG22/Understanding/error-prevention-legal-financial-data.html) supports review/correction of material information; it does not certify payment reconciliation.

### PD-14 — Medium: obsolete cache declaration makes sole-authority hygiene fail

**Confirmed fresh gate failure; scope is ignored evidence.** Root-executed `make revolut-design-authority` scanned 65,055 reference files and `design-authority.json` records a competing declaration in `.cache/revolut-design-20260930/public-current-browser/independent-visual-review-before-structural-fix.json:design_authority`. No competing current runtime design was reported. The gate's skill revision check was not requested, so the current comparator/skill binding was not certified by that run.

**Effect:** required sole-authority hygiene fails while legacy cache metadata can be mistaken for a current design authority. It does not establish that the rendered application follows another palette.

**Recommendation:** remove or retire the obsolete competing reference under the existing reference-cleanup convention, preserving any unique product verification evidence without keeping it as an alternative design system. Verify the current selected skill revision when evaluating acceptance. **Owner:** design/release integrator. **Closure:** required authority hygiene passes, the selected current authority binding is recorded, and visual/interaction acceptance remains independently truthful.

## Full operational checklist coverage

This applies the selected skill's 60-procedure framework without pretending that reading code executes every procedure. Status is for this review's actual envelope. “Unverified; prior scoped pass” credits existing evidence while preserving its source/platform limits. Owner and closure are stated for each item or finding. No blanket WCAG-AA or exact-source-fidelity claim is made.

| ID / criterion | Actual check/result | Owner and missing closure |
| --- | --- | --- |
| F01 Product/task scope | Mismatch: PRODUCT compared with routers/static copy; PD-07 | Product/content: approved capability/availability register |
| F02 Evidence provenance | Unverified overall: originals opened; PD-02 original stale graph now locally validates after17:34publication; native/current all-case binding still open | Design/QA: exact current cohort/artifact/case binding |
| F03 Task completion/recovery | Unverified: code/sample states and prior browser packets; deletion form mismatch | QA/product: full auth/group/payment/Admin/privacy tasks and recovery |
| F04 IA/discoverability | Unverified: menu/route inspection; incorrect deletion instruction PD-06 | UX research: representative locate-and-complete observations |
| F05 Content/financial comprehension | Mismatch: PD-07/13; payee/amount/PIN safety visibly present | Financial/content: finality and comprehension checks |
| F06 Localisation/extremes | Unverified: English-only explicitly supported (`collect_localizations.dart:4-13`), RWF grouping/precision code; PD-09 | Product/QA: English Rwanda comprehension, long names and actual amount limits; translations only if approved scope |
| F07 User-outcome evidence | Unverified: no representative-user sessions executed or cited as current completion | UX researcher: realistic unassisted tasks, errors/recovery/time/sample limits |
| F08 Closure/honest status | Mismatch: stale current index/inventory; honest unverified acceptance retained | Design/QA: PD-11/12 closure |
| V01 Geometry/hierarchy | Unverified: 9 fixtures and 3 source images inspected; no current matched all-case measurement | Design: cohort-matched geometry with documented adaptations |
| V02 Typography/loaded fonts | Mismatch/evidence gap: restored marketing faces, rights unverified; native Inter adapter explicit | Design/rights/release: PD-03, loaded face/whole-value checks |
| V03 Semantic tokens/themes | Unverified visual result; sole-authority hygiene mismatch in ignored cache (PD-14); blue/teal/violet/neutral families visible | Design system: hygiene plus all applicable role/theme/portal state captures and contrast |
| V04 Own identity/logo behavior | Pass for sampled fixture/source inspection only: Collect identity retained | Design/QA: manifest/store/launch/theme sizes and crop readback |
| V05 Component states | Unverified: loading/empty/error/disabled/review recovery components exist | QA: state matrix including route-specific special components |
| V06 Density/overflow | Unverified; prior compact pass; monetary shrink risk PD-09 | Shared UI/QA: max supported text/content/extreme data |
| V07 Motion/interruption | Unverified: CollectMotion respects disableAnimations (`collect_motion.dart:13-22`) | QA: actual reduced-motion/interrupt/resume state check |
| V08 Image boundaries | Pass for this review: private originals inspected locally, fixture/source kind kept distinct | Design: maintain crop/DPR/theme/colour-profile metadata when measuring |
| A01 Text/non-text contrast | Unverified: no current all-state sampled raster/foreground analysis executed | Accessibility: text 4.5:1/qualifying large 3:1; necessary controls/graphics 3:1, actual overlays/photos/focus |
| A02 Reflow/text enlargement | Unverified; prior attempt6 320/1x/2x coverage credited; PD-09 remains | QA: current web 320-equivalent/200%/400% and native scaling/orientation |
| A03 Keyboard/focus/overlays | Unverified; confirmation focus return code and prior keyboard pass credited | Accessibility/QA: current real forward/reverse keys, modal focus, escape/dismissal/return |
| A04 Names/roles/reading order | Unverified: semantic header/table code; status risk PD-08 | Accessibility: actual native/web semantic and speech task traversal |
| A05 Actual hit regions | Unverified: padded Material target preference exists; image artwork alone not hit size | QA: actual platform hit bounds/spacing, iOS/Android separately |
| A06 Auth assistance | Unverified: code/resend/confirmation found; auth golden inspected | Auth/QA: paste/autofill/correction/expiry/resend screen-reader task |
| A07 Labels/errors/redundant entry | Mismatch: specialized amount error association PD-08 | Shared UI: semantic association/retained input and actual correction |
| A08 Preference alternatives | Unverified: reduced-motion/high-contrast adapters exist | QA: actual preference variants on current candidates |
| A09 Pointer/gesture alternatives | Unverified: QR/share/camera and core buttons found; no complete actual gesture-only inventory | QA: alternatives for essential drag/swipe/scanning permission states |
| A10 Conformance boundary | Pass for this report: no unearned conformance/reader/native claim | Accessibility owner: evaluate all applicable WCAG A/AA before any conformance assertion |
| M01 Navigation/safe areas | Unverified: current routes/SafeArea/floating nav sampled | Native QA: exact release back/deep-link/scroll/keyboard-safe-area tasks |
| M02 Platform/adaptive | Unverified: Android-flavored fixtures cannot establish iOS/tablet/landscape | Native QA: Android/iOS supported minimum/large device matrix |
| M03 Permissions/interruption | Unverified: permission/recovery code and device harnesses found, not executed here | Native QA: SMS/camera/notifications denied/permanent/restore and interrupted USSD/auth |
| M04 Full money/account states | Mismatch/evidence gap: precise RWF/payee review present, PD-09/13 | Financial/QA: pending/unknown/settled/failure/reversal/stale/membership/profile tasks |
| M05 Theme/preferences persistence | Unverified: Light/Dark/System preview sampled | Native QA: actual preference persistence/current render/relaunch/accessibility settings |
| M06 Native performance/haptics | Unverified: performance harness found, no fresh trace here | Performance QA: representative devices/startup/frame/scroll/memory/app-size/energy traces |
| W01 Auth shell/workspace | Unverified; persistent operator fixture and prior current-origin packets exist | Admin/QA: current exact source authenticated/role-revoked/logout lifecycle |
| W02 Tables/access data density | Unverified; actual code adapts width<700/enlarged text (`admin_data_table.dart:29-49`) | Admin/accessibility: all table fields/headers/sorting/filters/focus/scroll at supported widths |
| W03 Bulk/partial failures | Unverified: no source artwork used as runtime/approval proof | Admin/QA: selected-row review, partial/unknown outcome, retry/idempotency tasks |
| W04 URL/navigation persistence | Unverified; GoRouter plus prior browser deep/reload evidence | Admin/QA: direct route/history/bookmark/tab recovery current source |
| W05 Permission/concurrent edits | Unverified; backend-specific evidence belongs to main report | Admin/security: revoked capability, stale version, actor/tenant boundaries and race tasks |
| W06 Responsive/performance | Unverified; compact table and prior browser cases do not provide field speed | Web QA: current Chrome/Safari/Firefox supported matrix/zoom plus field data |
| S01 Proposition/conversion | Mismatch: capability ambiguity/deletion form; PD-04/07 | Product/web: observable supported conversions with truthful current availability |
| S02 Responsive editorial | Unverified: CSS 1100/720/360 breakpoints inspected; only Flutter desktop image opened | Design/web QA: current static full scroll, narrow/tablet/desktop and zoom images |
| S03 Navigation/content architecture | Mismatch: four Privacy/Terms links confirmed live404 by root's217-link check; responsive menu focus code/tests exist | Web/content: complete internal/external graph and working legal paths |
| S04 Trust/terms/controls | Mismatch: form instructions and current capabilities; support footer present | Privacy/content: PD-04/05/06/07 and current approval/retention notices |
| S05 Discoverability/metadata | Unverified acceptance: static metadata implemented; root live gate fails source/content binding; private robots distinct | Web/SEO: current content/header/canonical/index eligibility and useful crawlable pages |
| S06 Media/performance | Unverified rendered/performance result: photograph pipeline exists; refreshed screenshot validator passes; no current trace | Web performance: actual current served image/font payloads, responsive crops, field CWV and lab diagnosis |
| P01 Install identity/modes | Mismatch: EUR/SEPA description PD-10; prior Chromium installation scoped | PWA/release: accurate manifest + actual tab/installed launch per supported OS/browser |
| P02 Deep links/external return | Unverified: validated-slug/invite handoff and public fallback code | Mobile/PWA QA: installed/uninstalled/cancel/background/deferred-auth return preserves intended group |
| P03 Offline/stale/reconnect | Unverified: offline fixture and prior lifecycle pass, no current full-device proof | QA: actual cold offline/private API failure/reconnect/stale timestamps without payment resend |
| P04 Account/cache boundaries | Unverified; substantial prior loopback isolation evidence credited | Security/QA: exact current logout/account-switch/origin separation/cache readback |
| P05 Session/draft recovery | Unverified; prior normal production-entrypoint synthetic packet credited | Admin/QA: exact current memory-session/editor/unknown commit task |
| P06 Active-work update | Unverified: prior same-runtime worker-version exercise, not arbitrary schema upgrade | PWA/release: supported version/storage compatibility and actual old/new clients with active work |
| P07 Storage loss/restrictions | Unverified; prior browser-enforced sessionStorage quota check scoped | PWA/QA: supported storage restrictions, eviction, denied write and truthful recovery |
| P08 Capability matrix | Unverified: Chromium installed proof does not cover Safari/iOS/Android/physical device | Product/QA: declare supported pairs and explicit unavailable behavior |
| K01 Skill scope/routing | Pass for this review: mobile/web/operator references selected separately | Review lead: continue sole-authority provenance |
| K02 Evidence discipline | Pass for this review: stale/fixture/promotion/current/source distinctions recorded | Review lead: current inventory/capture closure remains PD-01/02/12 |
| K03 Privacy/portability | Pass for this review: private reference pixels not republished; no private-data/credential operation | Review lead: any report exports continue synthetic-only/rights reviewed |
| K04 Component decisions | Pass for source review: existing shared framework retained; special-flow duplication found | Shared UI: PD-08/09 targeted reuse through actual callers |
| K05 Proportional claims | Pass for this review: fresh targeted checks, no checklist-to-fidelity percentage | Review lead: maintain exact acceptance boundary |
| K06 Reference refresh | Unverified: source cohort older/current unseen states need targeted research | Design: refresh named gaps without replacing every unchanged reference |
| K07 Skill bundle integrity | Full skill-package integrity not applicable to this repository slice; root authority hygiene fails ignored cache PD-14, revision check not requested | Skill/design maintainer: repair hygiene and bind current authority; separate full package task if requested |
| K08 Evaluation/handoff limits | Pass for report: scope, findings, roles, closure proof and unrun tasks explicit | Integration owner: reconcile fresh main-report gates and preserve unique artifacts |

## Existing positive evidence and its limits

`docs/release/shared-ui-accessibility-2026-09-30/attempt6/README.md` records 120 widget tests, actual Chromium 151 **25 route/state cases and 205 assertions** at 320×568 normal/2x text plus 390 group comparison, real Tab/Enter checks, no hosted/provider/database calls and actual inspected screenshots. It explicitly excludes speech, native devices, all routes and full Revolut parity. Its artifact/source are retained in attempt5, not the entire current dirty tree. These are useful regressions, not zero evidence, and should be rebound or rerun only for affected inputs.

`docs/release/local-browser-lifecycle-2026-09-30/README.md` records a synthetic current-source-at-that-time Admin/static split, **16 lifecycle cases / 37 assertions**, Chromium installation/offline launch, SDK/session/account/cache/storage/update recovery and zero uncaught errors on 557 frozen inputs. Its worker update uses changed static metadata with the same compiled runtime and does not certify arbitrary breaking storage upgrades. Later email-memory-auth and integration packets exist; the integrating reviewer's newest source readback must determine which checks remain reusable.

The retained 1 Oct 16:10 UTC corrected Admin browser failure records a login timeout after some route checks and leaves many later lifecycle coverage flags false. A newer 16:21 UTC integrated report is available to the integrating reviewer. The old failure is preserved evidence, not a proved continuing current bug; neither blanket “no browser coverage” nor blind reuse of the newest pass is justified when related runtime inputs have changed.

The sampled review screen has exact payee/number, visible whole-RWF amount, USSD handoff and correction. Confirmations dismiss without commitment and restore prior focus. Shared empty states are scrollable; shared headers/controls carry semantics. Admin unavailable/denied readings do not fabricate healthy service status. These are material strengths to preserve while repairing the gaps.

## Refactoring, restructuring and cleanup recommendations

1. **Canonical product content:** consolidate current capabilities/availability, finality words and deletion navigation into one approved source consumed by static public content, Flutter fallback, legal text and store/help metadata. Use adapters where audience differs. Keep provider/partner direction explicit; do not merge unrelated marketing and app workflows simply to remove duplicates.
2. **Shared high-risk journey components:** replace special amount/status/error rendering with existing semantic financial/control primitives where behavior matches. Keep full receiver/amount review and prevent resend/confirmation claims after unknown network outcomes. Extract only repeated state/format logic, not a broad visual rewrite.
3. **Candidate evidence index:** retain frozen evidence packets and regression captures, add one current source-bound index generated from actual routers/material states. Fix stale current records and explicitly supersede old passes. Avoid a second design specification or a new optional testing framework.
4. **Public deletion/privacy slice first:** choose and implement the real request/support outcome, correct legal links and menu instructions, then run generated graph and actual browser/accessibility task checks. A content hash or rendered field specification cannot close the workflow.
5. **Surface-specific asset declarations:** keep native/operator Inter; decide permitted marketing faces with the asset-rights owner. Verify actual native/Admin/static font/image payloads and license scope. Preserve generated-image provenance and selected Collect artwork; delete only proven obsolete competing design references through existing hygiene tooling.
6. **Responsive/accessibility expansion:** complete narrow/static full-page and Admin financial-queue states before cosmetic tweaks; include actual 200% text/320-equivalent/400% web reflow, supported native maximum scaling/orientation, long names and numeric boundaries. Do not shrink critical values merely to avoid overflow. [W3C reflow guidance](https://www.w3.org/WAI/WCAG22/Understanding/reflow.html) allows genuine two-dimensional-content exceptions, not unrelated page overflow.
7. **Product outcomes and accessibility:** recruit representative Rwanda group members and operators for realistic synthetic sign-in/group/payment/recovery/deletion tasks; measure wrong turns, critical errors, unassisted completion and recovery, with access needs/language comprehension represented. English-only is a current product decision, not automatically a defect; evidence should establish whether it fits the declared audience before expanding languages.
8. **Performance and support:** bind startup/scroll/network/app-size diagnostics to representative hardware and supported browsers; instrument truthfully without collecting OTP/SMS/customer data. Record public field Core Web Vitals by device/window and use lab runs as diagnosis. Ensure support handles pending/duplicate/unmatched receipts and privacy request status with an actual operating process.

Sequence: close content/privacy and asset-rights issues; reconcile canonical routes/status/media; freeze candidate source; rerun affected shared/browser/native checks; conduct current comparator/interaction/accessibility/device review; then independent and owner acceptance. Deployment/store/provider approval remains a separate downstream decision. This report recommends scoped changes; it makes no runtime mutation or external release.

## Primary-source research used

Research was verified during this review; these sources support criteria, not a certification of Collect. The skill remains the design authority. Standards/platform references inform implementation quality without introducing a competing visual reference.

| Source | Concrete use |
| --- | --- |
| [W3C Status Messages](https://www.w3.org/WAI/WCAG22/Understanding/status-messages.html) | PD-08: meaningful waiting/error announcements without moving focus; avoid noisy duplicate alerts |
| [W3C Resize Text](https://www.w3.org/WAI/WCAG22/Understanding/resize-text.html) | PD-09: readable enlargement and function/content preservation |
| [W3C Reflow](https://www.w3.org/WAI/WCAG22/Understanding/reflow.html) | A02/W06: 320-equivalent width/zoom and two-dimensional-content exceptions |
| [W3C Financial/Data Error Prevention](https://www.w3.org/WAI/WCAG22/Understanding/error-prevention-legal-financial-data.html) | Material facts review/correction; it does not certify backend money finality |
| [Flutter Accessibility](https://docs.flutter.dev/ui/accessibility) | Real TalkBack/VoiceOver/control-label/large-text checks and release limitations |
| [Flutter Accessibility Testing](https://docs.flutter.dev/ui/accessibility/accessibility-testing) | Semantics inspection and guideline API are useful but do not replace task/speech checks |
| [Google JavaScript SEO](https://developers.google.com/search/docs/crawling-indexing/javascript/javascript-seo-basics) | Public pre-rendered content, unique titles/descriptions and correct canonical links; private Admin crawl controls stay separate |
| [Apple App Review](https://developer.apple.com/app-store/review/) | Complete final content and functioning support/privacy links; store acceptance not inferred from source |
| [Revolut Business 5](https://www.revolut.com/business/rb5/) | Operator/bulk-review context; static promotional illustration is not an authenticated table comparator |

Coverage limitation: this reviewer performed no live Collect login/provider/store session, physical-device/native candidate install, fresh browser-rendered current static site, actual assistive-reader speech, representative-user study or field performance measurement. The integrating reviewer performed fresh read-only public HTTP checks, incorporated above. Those checks supplement rather than erase the remaining boundaries.
