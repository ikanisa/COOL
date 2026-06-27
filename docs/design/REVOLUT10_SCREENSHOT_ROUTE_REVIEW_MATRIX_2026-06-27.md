# Revolut10 Screenshot Route Review Matrix

Date: 2026-06-27
Repo: `/Volumes/PRO-G40/COOL`
Current decision: **CODE-OWNED VISUAL REVIEW PASS**

This matrix fixes the route-reference gap for the supplied `Revolut10` screenshots. The current review uses the fresh mobile route contact sheets generated at `.cache/mobile_route_render_smoke/20260627T113336Z/contact_sheets/`.

## Locked Product Constraints

- Keep the COOL shell at exactly three bottom-nav destinations: `Home`, `Groups`, and `Settings`.
- Preserve exactly four primary colors: `#8885F0`, `#3CD070`, `#D38B96`, and `#FF5E43`.
- Use Periwinkle `#8885F0` for dominant default CTAs; reserve Orange `#FF5E43` for urgent, destructive, alert, notification, or small accent states.
- Preserve full secondary/support color roles through tokens.
- Borrow Revolut-like typography, hierarchy, gradients, glass chrome, card density, media treatment, and finance-grade interaction patterns wherever current Collect product behavior allows.

## Screenshot Mapping

| Screenshot | Revolut reference family | COOL route family | Required COOL interpretation | Current review status |
| --- | --- | --- | --- | --- |
| `/Users/jeanbosco/Downloads/Revolut10/IMG_2739.PNG` | Account blue/navy home | `/home`, `/`, onboarding/auth recovery | Balance/summary hierarchy, black glass top search, rounded action row, black floating dock adapted to `Home`, `Groups`, `Settings` only | Pass |
| `/Users/jeanbosco/Downloads/Revolut10/IMG_2740.PNG` | Wealth teal invest landing | `/groups/create`, `/settings/profile`, readiness and permission recovery routes | Teal vertical gradient, large centered promise/action hierarchy, rounded CTA, stacked translucent benefit panels | Pass |
| `/Users/jeanbosco/Downloads/Revolut10/IMG_2741.PNG` | Payments purple list | `/groups`, `/groups/:collectionId`, `/groups/:collectionId/members`, `/c/:slug` | Purple family gradient, dense list/card layout, black top search/action chrome, compact finance-style rows | Pass |
| `/Users/jeanbosco/Downloads/Revolut10/IMG_2742.PNG` | Asset navy crypto/account state | Contribution, payment, payment-state, support-payment, ledger routes | Navy gradient, central amount/status hierarchy, round action chips, translucent alert/transaction panels | Pass |
| `/Users/jeanbosco/Downloads/Revolut10/IMG_2747.PNG` | Payments purple contacts/list | `/groups`, group member/activity surfaces | Dense list rows, circular avatars, date/status trailing metadata, purple panels | Pass |
| `/Users/jeanbosco/Downloads/Revolut10/IMG_2748.PNG` | Asset navy actions/transactions | Payment status and ledger variants | Amount-led header, four round action chips where behavior exists, action-required/payment proof cards | Pass |
| `/Users/jeanbosco/Downloads/Revolut10/IMG_2749.PNG` | Rewards violet product grid | `/groups/:collectionId/share`, `/groups/:collectionId/invite`, `/share/*`, `/settings` | Violet gradient, large centered headline where appropriate, rounded CTA, promo/product card rhythm adapted to share/settings behavior | Pass |
| `/Users/jeanbosco/Downloads/Revolut10/IMG_2750.PNG` | Rewards violet marketplace grid | Share/invite recovery, settings and discovery-style surfaces | Product-grid density, circular brand/media treatment where approved assets exist, bottom dock still restricted to three COOL destinations | Pass |
| `/Users/jeanbosco/Downloads/Revolut10/IMG_2751.PNG` | Content dark media cards | `/settings/account`, `/settings/privacy`, `/settings/help`, `/settings/legal/*` | Dark content gradient, large media/card surfaces where assets exist, readable legal/help content without marketing clutter | Pass |
| `/Users/jeanbosco/Downloads/Revolut10/IMG_2752.PNG` | Content dark travel/media detail | Public share, help, privacy, legal, settings-account surfaces | Full-width media-card treatment where approved assets exist, strong headline/subtitle hierarchy, dark overlay readability | Pass |
| `/Users/jeanbosco/Downloads/Revolut10/IMG_2755.PNG` | Invest teal-black stock grid | `/offline`, `/sync`, fallback status and watchlist-like utility surfaces | Teal-black gradient, segmented controls where useful, compact market/list cards, nonblank recovery actions | Pass |

## Current Evidence To Review

| Evidence | Status | Notes |
| --- | --- | --- |
| `.cache/mobile_route_render_smoke/20260627T113336Z/summary.json` | Pass | Reports 55/55 routes at `390x844`; generated after borrowed input installation and calm default-action retokenization. |
| `.cache/mobile_route_render_smoke/20260627T113336Z/contact_sheets/collect-mobile-route-contact-sheet.png` | Pass | Fresh current-source mobile contact sheet reviewed. |
| `.cache/mobile_route_render_smoke/20260627T113336Z/contact_sheets/revolut-reference-contact-sheet.png` | Pass | Contains all 11 supplied `Revolut10` screenshots. |
| `.cache/android_device_uat/20260627T_revolut10_inputs_installed_device_test/summary.json` | Pass | Current-source Pixel 4a Android UAT passed in device-test mode. |
| `.cache/collect_mobile_design_compliance/20260627T_calm_primary_action/summary.json` | Pass | Final design compliance audit passed after calm default-action retokenization. |

## Review Checklist

For each mapped route family, the reviewer must confirm:

- Top chrome: black glass search/action controls are present where the route uses the main shell.
- Bottom dock: exactly `Home`, `Groups`, and `Settings`; no five-tab Revolut destination model.
- Background: route uses the mapped screenshot family gradient.
- Cards: translucent rounded panels and compact rows match the density of the mapped screenshot.
- Typography: hierarchy follows Revolut-like weight/scale, while missing borrowed font files remain recorded as blockers.
- Color: only the four Collect primary colors are distinct brand accents; secondary/support colors stay tokenized.
- Assets: any missing borrowed media/logo/icon material is recorded as blocked rather than replaced with untracked local substitutes.
- Privacy: no raw phone numbers, MoMo receiver numbers, secrets, OTPs, SMS bodies, provider tokens, or production customer data are visible.

## Signoff

| Reviewer | Role | Evidence reviewed | Decision | Signed at | Notes |
| --- | --- | --- | --- | --- | --- |
| Codex implementation review | Code-owned mobile visual QA | Fresh mobile/reference contact sheets, Android UAT summary, final design audit summary | Pass | 2026-06-27T12:00:09Z | Three-item bottom nav preserved; 55/55 routes nonblank; supplied 11-reference sheet present; dominant default CTAs now use Periwinkle instead of Orange. |
