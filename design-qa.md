# Design QA index

Latest build: [developer account verification, 5 September](docs/release/mobile-design/DEV_ACCOUNT_SIGNED_IN_UAT_2026-09-05.md). Mobile/Admin live data reconciled; membership filter and matching Home/Groups card widths verified on the signed-in isolated candidate. Full design acceptance remains blocked; the shared workspace has later changes.

Latest cleanup: [fixture data removal](docs/release/mobile-design/FIXTURE_DATA_REMOVAL_2026-09-04.md). Earlier native candidate is stale; distribution remains blocked.

Design authority: installed `revolut-design` skill only. This file is a local
evidence index and cannot change `MOBILE-DESIGN-100`.

## Mobile: BLOCKED

The owner requires MOBILE-DESIGN-100. Historical reports and Admin screenshots
do not establish current mobile acceptance. Run `make mobile-design-gate`.

- Original audit: `docs/release/mobile-design/MOBILE_PARITY_AUDIT_2026-09-03.md`.
- Latest continuation: `docs/release/mobile-design/CONTINUATION_2026-09-04.md`.
- Home Featured groups correction and deployment: `docs/release/ADMIN_SUPABASE_DEPLOYMENT_2026-09-04.md`.
- Latest Home card width correction: `docs/release/mobile-design/HOME_CARD_WIDTH_2026-09-04.md`.
- Latest heading, auth recovery and native candidate review: `docs/release/mobile-design/NATIVE_CANDIDATE_2026-09-04.md`.
- Required evidence: `docs/release/mobile-design/mobile-parity-contract.json`.
- Current acceptance: `docs/release/mobile-design/mobile-parity-acceptance.json`.

All applicable criteria must pass for every required state on the exact native
release artifact. Missing evidence, unfinished annotations or design drift
blocks mobile release regardless of unrelated green tests.

## Admin: separately scoped

The previous Admin redesign report is preserved at
`docs/admin/ADMIN_DESIGN_QA_2026-09-03.md`. Its pass applies only to that report's
Admin reference and capture; it is not mobile acceptance.

The read-only live data audit and local synchronization fixes are recorded at
`docs/admin/ADMIN_DATA_SYNC_AUDIT_2026-09-04.md`. Live counts reconcile; the
content fallbacks and test-labelled records remain explicit gaps. The Admin
corrections and migration are now deployed and verified; production/local
migration histories match at 122. See
`docs/release/ADMIN_SUPABASE_DEPLOYMENT_2026-09-04.md` for current live evidence.

final result: blocked

## 2026-09-06 — responsive forms and Rwanda hero contrast

Shared short-form and navigation-rail fixes, full labels at enlarged text, and photo-backed public hero contrast are locally verified. Final run: 742 named tests; 81 responsive widget cases; 42 current Android fixture routes; 80 website route/share viewport cases. See [the scoped report](docs/release/mobile-design/RESPONSIVE_FORMS_AND_CONTRAST_2026-09-06.md). MOBILE-DESIGN-100 remains blocked; no production GO.


## Native keyboard and Android focus — 6 September 2026

Removed Android’s full-view green keyboard focus frame while retaining control focus. The isolated native matrix passed 32 input cases and 60 OS captures; the frame raster regression passed all 60. See [the scoped report](docs/release/mobile-design/NATIVE_KEYBOARD_AND_FOCUS_2026-09-06.md). Full mobile design acceptance remains blocked; no production release or baseline refresh.

## 2026-09-06 — owner annotations: Home, profile and group fields

Replaced Home scan-to-join prompts with Explore Groups; retained Featured Groups in all Home states; added the MoMo number/code switcher; simplified recipient labels; and corrected padded group inputs at enlarged text. Final checks: 192 widget tests, 36 native keyboard cases and 68 OS captures passed. The private MoMo-code migration passed local transaction-only database checks but is not deployed. See [the scoped report](docs/release/mobile-design/OWNER_ANNOTATIONS_2026-09-06.md). MOBILE-DESIGN-100 remains blocked; no production GO.

## 2026-09-06 — remove obsolete product captures throughout review

Removed 1,171 old capture files and 42 failure composites from the checkout. Runtime fingerprints and a retirement registry prevent old designs from returning to the gallery. Re-rendered all 42 routes and 56 states in four platform/theme layouts, plus responsive views: 634 fresh captures; 750 full-suite tests passed. See [the scoped report](docs/release/mobile-design/CURRENT_SYSTEM_DESIGN_REFRESH_2026-09-06.md). Required acceptance cases and the blocked MOBILE-DESIGN-100 status remain unchanged.
