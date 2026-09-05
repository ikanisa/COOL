# Native candidate verification — 4 September 2026

> Later source update, 4 September 2026: the fixture-removal change supersedes
> this candidate's source binding. The recorded APK/AAB and native screenshots
> below are historical QA evidence and cannot approve the current source. See
> [fixture removal](FIXTURE_DATA_REMOVAL_2026-09-04.md).

Status: **NO-GO for distribution. Local fixes and fixture review pass; exact
production-artifact acceptance remains incomplete.**

Owner: Jean Bosco. Reviewer: Codex. Repository baseline: `474fc32a` with existing
uncommitted work preserved. Evidence root: `.cache/mobile-acceptance-20260904/`.

## Changes and review

- Shared section headings measure the title and action at the active text scale.
  When they cannot share a row, the action moves below the full-width title.
  Native 320dp / 200% captures show “Featured groups” wrapping between words,
  with a reachable “View all” action. Both Home sections retain the same card
  width, height and insets as Groups.
- Failed sign-in now reveals the inline error instead of returning the lazy
  list to its top. The error remains a semantic live region. The old four-line
  limit is removed, so enlarged recovery text can be read to its end.
  “Change number” retains the entered phone number.
- The first installed production candidate exposed a native accessibility
  defect in the country picker: country buttons had no activation action and
  the search field was unlabelled. Country rows now expose their tap action,
  and search uses the existing accessible text-field component. The regression
  test searches and selects Rwanda entirely through semantics. The first
  candidate is retained as rejected evidence under `candidate-initial/`.
- Only the Home regression image was refreshed in this continuation, after
  reviewing the old narrow card and the requested full-width card side by side.
  This baseline is a regression reference, not a production approval.

The relevant implementation is in `collect_display_primitives.dart`,
`auth_screen.dart`, `auth_input_panel.dart`, and `auth_country_picker_sheet.dart`.
`DESIGN.md` records the heading and error-reveal rules. Tests cover LTR/RTL heading behavior, complete error
guidance, dark/light modes and native recovery traversal.

## Verification

| Check | Result | Evidence |
| --- | --- | --- |
| Full unit, widget and golden suite, final source | 624 passed | `full-tests-candidate-final.txt` |
| Flutter analysis | No issues found | `analyze-candidate-final.txt` |
| Gate regression suite | 33 tests, 131 assertions passed | `gate-tests-final.txt` |
| Contract and diff checks | Passed | `contract-final.txt`, `diff-check-final.txt` |
| Native normal phone routes | 42/42 passed; all 42 images inspected | `native-routes/`, `routes-visual-review.json` |
| Native compact, 200% text, reduced motion | 31/31 states passed; 47 images inspected | `native-compact-states-r2/`, `compact-visual-review.json` |
| Final native OTP recovery | Passed; complete guidance and retained phone after Change number | `native-otp-final/`, `otp-visual-review.json` |
| Country-picker semantic interaction | Search label, search text entry, country activation and sheet dismissal passed | `country-a11y-final.txt` |

The 31-state run exposed the error-message line limit during visual inspection.
The later focused native OTP run verifies its removal, with two overlapping
captures showing the complete recovery message. Runs overlap; these counts are
not a count of accepted release cases. Native fixtures used only
`app.cool.mobile.dev` on the isolated Android 16 emulator.

Failed intermediate evidence is retained: `full-tests.txt` found the old Home
baseline, `native-compact-states/` stopped at the hidden OTP error,
`otp-error-before.txt` reproduced four error-reveal failures, and
`otp-guidance-before.txt` reproduced two clipped-guidance failures. None is
counted as a passing run.

## Production candidate

The controlled Android wrapper completed **1.2.4+23** at
`2026-09-04T07:21:32Z` with production runtime configuration and
`COLLECT_MOBILE_EVIDENCE_MODE=false`. Signing verification passed against the
configured Google Play upload certificate. The current source fingerprint
matches the wrapper provenance; no source changed during the build.

| Identity | SHA-256 |
| --- | --- |
| Source | `214ce09f8f1b698d21f156b21cc718622407a546c4d3c49fbfd167e7618ed698` |
| APK | `4e7a7335579b76c9daec8a4541e623a12f25500aeb62d545f4834403cfef70cb` |
| AAB | `6636261824f8fc02603471b86236f8a83f8c9dac63405cfc591ecb3452435106` |

The replacement APK was installed on the isolated Android 16 emulator as
`app.cool.mobile`; pulling the installed package confirmed the identical APK
hash. Native readback passed cold start, the search field label, country button
activation actions, searching Rwanda using the native keyboard, selecting
Rwanda, and keeping Send disabled for an incomplete phone number. All four
production smoke images were visually inspected. No Flutter or fatal errors
were found in the captured current-process log. No real OTP was sent.
This checks Android's accessibility structure and native interaction; spoken
TalkBack traversal remains untested.

Evidence: `android-candidate-build-final.txt`, `installed-candidate.json`,
`apk-signature-final.txt`, `production-smoke.json`, and
`.cache/mobile-design-build/android.json`. The APK and AAB remain local QA
artifacts; neither was distributed or uploaded to a store.

`make mobile-design-gate` still returns **BLOCKED** (exit 2); the underlying
JSON gate returns exit 1. The approval record has no accepted cases or bound
approval hashes, and the four open findings remain. This is recorded in
`mobile-design-gate-final.txt` and `mobile-design-gate-final.json`. The missing
approval identities do not mean the new build provenance is missing; approval
binding remains incomplete until the required review is complete.

The first candidate (`dd6361e0…`) built, passed signing verification, installed
with an identical APK hash, and cold-started successfully. Its country-picker
accessibility defect prevents its acceptance; the replacement build includes
the semantic action and search-label corrections.

## Remaining acceptance

The contract retains **134 required cases per platform** and all 22 annotations.
`exact-candidate-case-register.csv` records every required case as pending exact
production-artifact acceptance. Fixture images cannot close those entries.
The actual signed-in sessions, full native accessibility/keyboard/permission
and recovery coverage, original-reference comparisons and final case reviews
remain necessary under `AGENTS.md` / `DESIGN.md` MOBILE-DESIGN-100.

An authorized test account was requested for signed-in candidate checks.
The physical Pixel and its signed-in data remain untouched. No live payment,
message, group membership or production data was changed by this continuation.

Admin and Supabase deployment was completed earlier; see
[the deployment evidence](../ADMIN_SUPABASE_DEPLOYMENT_2026-09-04.md).
Home uses live membership and public-group records; fixture datasets were used
only for the diagnostic runs. The separate data audit still documents bundled configuration/content
fallbacks, so this report does not claim that every application constant is
backend-managed.
