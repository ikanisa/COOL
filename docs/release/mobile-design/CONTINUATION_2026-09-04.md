# Mobile design and Admin data continuation — 2026-09-04

**Later owner instruction:** Admin and the pending Supabase migration were
deployed and verified. Home now retains backend-driven Featured groups after
joining, alongside My groups, with a fresh isolated native capture. See the
[deployment and Home correction report](../ADMIN_SUPABASE_DEPLOYMENT_2026-09-04.md).
The no-production-change statements below describe the earlier diagnostic pass.
The mobile distribution gate remains blocked.

Status: **NO-GO for mobile distribution. Local corrections and diagnostic
verification complete; native release acceptance incomplete.**

This continues the supplied September 3 audit and the owner's additional request
to check Admin/Supabase synchronization and hardcoded data. `DESIGN.md` remains
the design authority. No production data, physical-phone installation, or
release approval is changed by this work.

## Reviewed changes

- Camera and SMS recovery sheets overflowed at 320×640 and 740×360 with 200%
  text, by 228–664 px with the bundled Inter font. The common native sheet now
  scrolls within safe-area and keyboard constraints. Four reproducing widget
  tests failed before the correction and pass after it.
- The first light native run rendered 42/42 routes. Every image was inspected
  in `.cache/design-parity-20260904/light-review/`. Auth still used dark-only
  foregrounds over adaptive pale fields. Central auth color roles now adapt
  the canvas, headings, phone/OTP inputs, picker, confirmation and actions;
  their prior dark values are preserved. Contrast tests cover both themes.

![Native light auth before and after](</Volumes/PRO-G40/Agents/Codex/2026-05-15/Codex Professional Agents/desktop-output/flutter/collect-continuation-2026-09-04/native-light-auth-before-after.png>)

The images above are isolated Android fixture captures, normalized side by side
for review. They show the same empty phone entry state, not production user data.
- Additional native state capture traverses the entire camera/SMS recovery,
  phone confirmation, SMS-consent and deletion-confirmation sheets with overlapping captures and
  a safe secondary action. These explicitly remain fixture interactions, not
  real permission, deletion or transaction tests.
- At 320×640 / 200%, native phone confirmation overflowed by 41 px. Its content
  now scrolls, preserving the complete phone number and both confirmation
  choices. A third auth regression covers the compact sheet. The integration
  traversal selects the outer sheet scroll view, not SelectableText's internal
  scroll view.
- Native landscape contribution entry overflowed by 7.6 px while the keyboard
  reduced the available height below the fixed header/action area. Both RWF and
  EUR flows now retain a minimum content viewport and allow the whole flow to
  scroll above the keyboard. At normal heights the outer view has no scroll
  extent. Four focused tests exercise entry and reachable enabled actions at
  740×360, a 260 dp keyboard inset and 100%/200% text.

## Admin golden review before baseline update

The September 4 full suite passed 608 tests and failed the one Admin overview
golden changed by the data-truth fixes. Codex visually inspected both
`test/goldens/failures/admin_overview_desktop_masterImage.png` and
`admin_overview_desktop_testImage.png` side by side before approving this
regression-baseline change:

- `Awaiting approvals` changes from an invented zero to `Not available` when
  the backend metric is absent. The actual live `admin_overview` response has
  four metrics and does not provide this metric.
- `Oldest item age` changes to `Oldest visible item`, because only three queue
  rows are loaded. It does not claim to measure the entire queue.
- Both changes fit the existing panel with readable, uncut labels; hierarchy,
  spacing, colors and surrounding records are unchanged.

Only the Admin overview golden may be refreshed for these inspected changes.
This is a reviewer decision about a diagnostic baseline, not owner acceptance
or MOBILE-DESIGN-100 approval. The other 12 goldens passed unchanged.

## Evidence locations

- Native, analyzer and test evidence: `.cache/design-parity-20260904/`.
- Read-only live Admin and database audit: `.cache/admin-data-audit-20260904/`.
- Detailed data findings: `docs/admin/ADMIN_DATA_SYNC_AUDIT_2026-09-04.md`.

The results below are diagnostic verification, separate from release approval.

## Verification of local changes

- Full unit/widget/golden suite: **614 passed**
  (`all-tests-final-r4.txt`, after the contribution keyboard correction). This includes the new Admin, auth theme/confirmation
  and native recovery-sheet regressions, including system-bar exclusion and
  landscape keyboard checks. The focused contribution suite passed 11 tests.
- Flutter analyzer: **No issues found** (`analyze-final-r3.txt`, after the final
  contribution keyboard adjustment).
- Mobile gate regression suite: **33 tests / 131 assertions passed**
  (`gate-tests.txt`). Contract validation and `git diff --check` passed.
- Local Admin release build, manifest gate and hosting gate passed. Details and
  production data gaps are recorded in the linked Admin report.
- `make mobile-design-gate` remains **blocked**, as intended: no approved native
  case matrix or current release-artifact acceptance exists. Passing diagnostic
  runs do not change the four open findings or award design scores.

Failed native runs remain in the evidence folder: `compact-states` exposed the
lazy off-screen auth field; `compact-states-r2` exposed the real confirmation
overflow; `compact-states-r3` exposed the test's assumption that selectable text
has no internal scroll view. They are not counted as passing runs.

## Additional native evidence

- `compact-states-r4`: **31/31 states passed**, all 31 primary and nine additional
  scrolling screenshots inspected. Camera recovery, SMS recovery, SMS consent,
  phone confirmation and account-delete confirmation reached their safe secondary
  actions. This run precedes the final recovery-sheet bottom-inset adjustment;
  the focused four safe-area tests cover that adjustment at 200% text.
- `light-states-final`: **31/31 states passed**, every image inspected at about
  393×851 dp / 100% text. This run includes the final bottom-inset correction and
  confirms readable light auth/OTP/confirmation fields, complete recovery text
  and visible action labels. The first 42-route light run remains earlier evidence
  and is not mislabelled as a final-source auth pass.

The light-state run precedes the later contribution keyboard adjustment. Native
`landscape-routes` stopped at contribution entry after 21 routes; it is retained
as failing evidence, not a completed landscape pass.

- `landscape-routes-r2`: **42/42 route entries passed**, every capture inspected
  at 740×360 dp / 100% text. The previously failing contribution route and both
  rails pass after the keyboard correction. These are first-viewport captures;
  they do not establish full landscape journeys or native keyboard acceptance.
- `tablet-routes`: **42/42 route entries passed**, every capture inspected at
  800×1000 dp / 100% text, including the signed-in entry redirect, group grids,
  contribution flows, settings and legal pages. This is the final source's
  default-dark tablet route pass, not every tablet state or accessibility case.

## Remaining release work

`EXACT-NATIVE-CANDIDATE`, `COMPLETE-CASE-MATRIX`, `NATIVE-ACCESSIBILITY` and
`FINAL-VISUAL-REVIEW` remain open. There are still no approved cases, invented
scores or production artifact identities in the acceptance record. The 42-route
and 31-state runs overlap contract cases and must not be summed into a count of
accepted unique cases. Real OS permission denial/retry, screen readers, complete
keyboard/interaction coverage, provider handoffs, and reference comparisons on
the exact release candidate remain unverified.

No production data, signed-in physical phone, deployment or store submission
was changed. The isolated emulator was used for fixture builds only. The Admin
build is prepared locally; its release and the missing database migration have
not been applied. See the Admin report for the configuration fallback and stored
test-record findings.
