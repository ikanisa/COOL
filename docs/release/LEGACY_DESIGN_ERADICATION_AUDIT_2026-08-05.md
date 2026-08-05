# Legacy design eradication audit — 5 August 2026

## Decision

The member app and authenticated Admin PWA now use one current visual system:
solid neutral canvases, neutral raised surfaces, black/white primary actions,
Inter typography, restrained borders, square black-on-white QR modules, and
semantic colour only for state. The retired blue/purple gradient chrome,
decorative image cards, multicolour QR treatment, split legacy phone control,
six-box OTP treatment, and obsolete store captures are rejected.

This is a source, route, asset, and rendered-evidence audit. It does not claim
that the official four-node Collect logo, a group owner's selected accent, or
semantic success/warning/danger colour is legacy. Those three bounded uses are
intentional product data or state communication, not shared chrome.

## Eradication controls

- Runtime assets are reduced to the hash-pinned official launcher mark and the
  bundled Inter licence/font files. The retired `qr-share.png`,
  `group-momentum.png`, and `mobile-money-ussd-signal.png` files are deleted
  from the product tree.
- Member/Admin source rejects decorative `LinearGradient` use, retired
  gradient tokens, retired media names, purple chrome references, and all
  obsolete paint/glass token vocabulary.
- The old theme fields and aliases were removed, not merely assigned neutral
  values. Reintroduction fails `scripts/revolut_parity_source_hygiene_gate.sh`.
- QR output is generated at runtime with black square modules and finder eyes
  on white. No colour frame or decorative QR bitmap remains.
- Store image packs are regenerated from current fixture-only Flutter renders;
  old iPhone/Android/tablet screenshots are not retained in Fastlane slots.

## Member route ledger

Every row is covered by the 35-route native iPhone, iPad, and Android matrices.
The screenshot filename is `mobile_route_<evidence-name>.png` below the
platform evidence root.

| # | Route | Evidence name | Legacy risk inspected | Current replacement | Result |
|---:|---|---|---|---|---|
| 1 | `/` | `root-redirect` | outgoing splash fragment and blue entry chrome | settled redirect to the solid auth entry | Pass |
| 2 | `/auth` | `auth` | blue gradient, globe/country card, detached input, six OTP boxes | one neutral `+250` phone field and one secure OTP field | Pass |
| 3 | `/settings/profile` | `profile-edit` | decorated profile/form chrome | neutral form surface and current controls | Pass |
| 4 | `/home` | `home` | gradient canvas, tinted hero/cards, legacy media | solid canvas, neutral money hierarchy, functional group accents only | Pass |
| 5 | `/offline` | `offline` | decorative recovery artwork | neutral recovery panel with semantic state | Pass |
| 6 | `/sync` | `sync` | decorative recovery artwork | neutral recovery panel with semantic state | Pass |
| 7 | `/groups` | `groups` | tinted group chrome and image treatments | neutral list surface with group-owned accent circles | Pass |
| 8 | `/contribute` | `contribute-entry` | gradient amount/search chrome | solid chooser and neutral controls | Pass |
| 9 | `/activity` | `activity` | tinted activity canvas/cards | neutral activity list and tabular money | Pass |
| 10 | `/groups/create` | `group-create` | decorative cover placeholder and glass controls | solid placeholder and neutral form controls | Pass |
| 11 | `/groups/scan` | `group-scan` | purple scanner, gradient beam, overlapping guide | black scanner canvas; unavailable state has no fake guide/beam | Pass |
| 12 | `/groups/col-church` | `group-detail` | image/gradient hero chrome | neutral balance/detail hierarchy | Pass |
| 13 | `/groups/col-church/share` | `share` | multicolour framed QR and purple primary action | black-on-white QR and monochrome action hierarchy | Pass |
| 14 | `/groups/col-church/invite` | `invite` | duplicate legacy invite treatment | canonical current share screen | Pass |
| 15 | `/c/st-michel-building-fund` | `shared-group-link` | transitional/blank deep-link capture | settled current group detail | Pass |
| 16 | `/app` | `app-share-entry` | blank compatibility route | settled current home | Pass |
| 17 | `/invite/038491` | `app-invite-link` | blank compatibility route | settled current home | Pass |
| 18 | `/share/invalid` | `share-invalid` | blank/error fragment | settled current groups recovery destination | Pass |
| 19 | `/share/expired` | `share-expired` | blank/error fragment | settled current groups recovery destination | Pass |
| 20 | `/share/expired/request` | `share-expired-request` | blank/error fragment | settled current groups recovery destination | Pass |
| 21 | `/groups/col-church/contribute` | `contribution` | gradient amount/review cards | neutral amount and review surfaces | Pass |
| 22 | `/groups/col-church/ledger` | `ledger` | tinted ledger and filter controls | neutral ledger rows and controls | Pass |
| 23 | `/groups/col-church/manage` | `manage` | glass settings controls | neutral settings/form controls | Pass |
| 24 | `/groups/col-church/profile` | `group-profile` | gradient/media placeholders | solid placeholders and neutral editing surfaces | Pass |
| 25 | `/groups/col-church/members` | `members` | glass chips and tinted member controls | neutral controls and semantic selection | Pass |
| 26 | `/settings` | `settings` | legacy top chrome and tinted sections | solid settings canvas and neutral rows | Pass |
| 27 | `/settings/notifications` | `settings-notifications` | tinted preference controls | neutral preference controls | Pass |
| 28 | `/settings/appearance` | `settings-appearance` | gradient appearance preview and blue info treatment | solid preview and neutral information treatment | Pass |
| 29 | `/settings/security` | `settings-security` | blue information icons/chrome | neutral information roles; warning remains semantic | Pass |
| 30 | `/settings/account` | `account` | glass account controls | neutral account controls | Pass |
| 31 | `/settings/account/delete` | `account-delete` | tinted destructive flow | neutral form with semantic danger only | Pass |
| 32 | `/settings/privacy` | `privacy-alias` | transitional alias capture | settled Privacy Policy | Pass |
| 33 | `/settings/help` | `help` | tinted help cards | neutral help rows | Pass |
| 34 | `/settings/legal/privacy` | `legal-privacy` | legacy legal chrome | neutral readable legal document | Pass |
| 35 | `/settings/legal/terms` | `legal-terms` | legacy legal chrome | neutral readable legal document | Pass |

## Admin route ledger

All routes below are rendered at compact `390x844`, tablet `834x1194`, and
desktop `1440x900`. The browser matrix requires route resolution, semantics,
named interactive controls, minimum target size, keyboard traversal, no
document overflow, and no browser errors.

| # | Route | Specific eradication check | Result |
|---:|---|---|---|
| 1 | `/admin/login` | removed country tile/dropdown; one `+250` inline phone field, one OTP field, neutral card | Pass |
| 2 | `/admin/denied` | neutral denial state; semantic danger only | Pass |
| 3 | `/admin` | no purple workspace/sidebar/metric gradients | Pass |
| 4 | `/admin/groups` | neutral filters, cards, and table | Pass |
| 5 | `/admin/groups/collection-1` | neutral group detail/actions | Pass |
| 6 | `/admin/members` | neutral list and filters | Pass |
| 7 | `/admin/members/user-1` | neutral member detail | Pass |
| 8 | `/admin/payment-intents` | neutral payment queue | Pass |
| 9 | `/admin/payment-intents/admin-row-1` | neutral intent detail | Pass |
| 10 | `/admin/payment-events` | neutral event queue and compact filters | Pass |
| 11 | `/admin/payment-events/event-1` | neutral event detail; semantic statuses only | Pass |
| 12 | `/admin/allocations` | neutral allocation workflow | Pass |
| 13 | `/admin/exceptions` | neutral exception workflow; semantic warning only | Pass |
| 14 | `/admin/ledger` | neutral ledger/table | Pass |
| 15 | `/admin/receivers` | neutral receiver list and privacy gate | Pass |
| 16 | `/admin/receivers/receiver-1` | neutral receiver detail and masked fixture data | Pass |
| 17 | `/admin/sms` | neutral SMS list; raw content gated | Pass |
| 18 | `/admin/sms/sms-1` | neutral SMS detail and privacy gate | Pass |
| 19 | `/admin/audit-logs` | neutral audit table | Pass |
| 20 | `/admin/settings` | neutral settings controls | Pass |
| 21 | `/admin/feature-flags` | neutral feature controls; semantic state only | Pass |
| 22 | `/admin/system-health` | neutral health surface; semantic state only | Pass |
| 23 | `/admin/admin-users` | neutral operator list and role controls | Pass |

## Accepted evidence roots

- iPhone native route matrix:
  `.cache/ios_simulator_route_uat/20260805-legacy-eradication-accepted-iphone/`
  (35/35 screenshots; summary SHA-256
  `bd5b603a652933afa76f3c71c5286790c3c939eb8d0079c180f2e312aad61a37`)
- iPad native route matrix:
  `.cache/ios_simulator_route_uat/20260805-legacy-eradication-accepted-ipad/`
  (35/35 screenshots; summary SHA-256
  `c032cb995a469c8fc885054020daa50bd0ddaa5966a9e26cc2d051e8513a5cd4`)
- Android native route matrix:
  `.cache/android_device_uat/20260805-legacy-eradication-accepted-emulator/`
  (35/35 screenshots; summary SHA-256
  `dc6f2e2e39fa39ceff1b7df9e236f980b7b2fdbcee73c9a713977112c5645247`)
- Android material-state matrix:
  `.cache/android_device_uat/20260805-legacy-eradication-accepted-states/`
  (17/17 screenshots; summary SHA-256
  `9148b28b9390ebd3d2daa861a060fb9e7d254c581747e4a2b03f040319daefd9`)
- Admin authenticated browser matrix:
  `.cache/admin_pwa_authenticated_render_smoke/20260805-legacy-eradication-accepted/`
  (23 routes x 3 viewports, 69 browser screenshots; summary SHA-256
  `d4aa965fba702fad42e95c3441369de34782e563fa0ce426eb4b9fb517a27315`)
- iOS enlarged-text/high-contrast/reduced-motion matrix:
  `.cache/ios_simulator_route_uat/20260805-legacy-eradication-accepted-accessibility-iphone/`
  (35/35 screenshots at 200% text, high contrast, and reduced motion; summary
  SHA-256
  `4ee9dc5f66c7cd36a8ca786be930da91fbabb7667545b450f685b234f3949711`)
- iOS material-state matrices:
  `.cache/ios_simulator_material_state_uat/20260805-legacy-eradication-accepted-dark/`,
  `.cache/ios_simulator_material_state_uat/20260805-legacy-eradication-accepted-light/`,
  and
  `.cache/ios_simulator_material_state_uat/20260805-legacy-eradication-accepted-system-light/`.
  The accepted Dark, Light, and System-Light sets contain 17/17 screenshots
  each. Their summary SHA-256 values are
  `f85304f86e73cd6f98f9be228357bdc54507ec831b87f7fea653bfe91ca8e219`,
  `6032a728940fa361d5b3fa99a2e17dcbf6d6453000611ba0338782137a8e0673`,
  and `ca1079ab774815a15e30314f067369dfa8118bd835b57d81dddf41217b525640`.
- Current store-artwork generation:
  `.cache/app_store_ios_screenshots/20260805-legacy-eradication-accepted/` and
  `.cache/google_play_store_screenshots/20260805-legacy-eradication-accepted/`.
  Fastlane now holds 5 iPhone, 5 iPad, 6 Android phone, 5 seven-inch Android,
  and 5 ten-inch Android captures from the accepted current source.

## Final automated acceptance

- `flutter analyze --no-pub`: pass with no issues.
- `flutter test --no-pub`: pass, 456 tests.
- Approved golden suite: 14/14 tests; all 13 checked-in baseline hashes match
  `test/goldens/GOLDEN_MANIFEST.sha256`.
- `scripts/revolut_parity_source_hygiene_gate.sh`: pass, 13/13 controls.
- `scripts/ios_app_store_readiness_gate.sh --json`: pass for 10 screenshots,
  15 icons, 4 property lists, 8 metadata fields, and 8 privacy types.
- `scripts/google_play_optimization_gate.sh --json`: the current phone,
  seven-inch, and ten-inch screenshot sets pass exact count, hash, and PNG
  dimension checks. Reporting authorization and live Console review remain
  separate account-controlled release checks.

The exact physical iPhone staging rerun installed, launched, attached, and
passed the first 3 routes before the CoreDevice wireless connection was
invalidated on Home. The harness rejected it because the completion marker and
32 route passes were absent; no physical pass is claimed. Rejected summary/log
SHA-256 values are
`2bf4f708a3cf6cb2e4bae7e72a25cf79068cef0b5d6d4c4a6d5c0b15b1afb861`
and `46ebd77c8fe0bde096fe11132396cbc4ad31e4990c5ce5766325f534078fdde2`.

## Acceptance boundary

Passing rendered evidence means the declared current-source route/state and
viewport rendered without the rejected legacy system. It does not manufacture
provider transaction evidence, store review decisions, or production approval.
Those operational decisions remain separately evidenced.
