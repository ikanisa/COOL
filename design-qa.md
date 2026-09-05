# Design QA index

Latest build: [cleanup candidate, 5 September](docs/release/mobile-design/CLEANUP_CANDIDATE_2026-09-05.md). Installed hash and live data verified; signed-in acceptance remains pending.

Latest cleanup: [fixture data removal](docs/release/mobile-design/FIXTURE_DATA_REMOVAL_2026-09-04.md). Earlier native candidate is stale; distribution remains blocked.

Design authority: `DESIGN.md` only.

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
