# Native keyboard and Android focus — 6 September 2026

The real Android keyboard review passed **32 cases with 60 OS screenshots**. It exposed a green outline around the entire Flutter view after keyboard input. `MainActivity.onCreate` now disables Android's default focus highlight on the Flutter host view on API 26 and later. Collect's individual field and button focus behavior remains active.

The green frame is documented in the [Flutter Android issue](https://github.com/flutter/flutter/issues/146695). The implementation uses the activity's supported [Flutter view identifier](https://api.flutter.dev/javadoc/io/flutter/embedding/android/FlutterActivity.html#FLUTTER_VIEW_ID). It changes only the host view's decorative highlight; it does not disable focus, keyboard input or accessibility services.

## Native verification

Each row ran in portrait and landscape with Android font scale 1 and 2, using the actual system IME. The full action control and focused input were checked separately after scrolling where necessary.

| Scenario | Actual input state | Native cases |
| --- | --- | --- |
| Sign-in | Rwanda phone entry; code not sent | 4 passed |
| Rwanda profile | Existing MoMo number replaced through Android key events | 4 passed |
| Diaspora profile | Existing account number replaced through Android key events | 4 passed |
| Rwanda contribution | Amount entry; `1234` displays as `1,234` | 4 passed |
| Diaspora contribution | Decimal EUR amount entry | 4 passed |
| Group creation | Group name entry; creation not submitted | 4 passed |
| Group invitation | Signed-out `/c/qa-private-group` reaches sign-in and retains the invitation while typing | 4 passed |
| Group search | Opens the actual search control and filters the Rwanda photo cards | 4 passed |

Environment: isolated AVD `Collect_Design_Renderer_QA_20260905`, Android 16 / API 36, `app.cool.mobile.dev`, dark theme, 1080 × 2340 physical pixels at density 440. Logical viewports were approximately 393 × 851 and 851 × 393. Text scaling came from Android settings, without a substituted `MediaQuery` or emulated Flutter text entry.

The driver uses Android input events for focus and text entry, and Flutter scrolling to reveal controls. It verifies native keyboard insets and IME visibility, typed values, field focus and hit testing, route stability, complete action bounds and hit testing, and retained invitation state. The matrix covers input states, not submitted payment or account journeys. All account and group data are synthetic; each scenario has its own fixture intent store.

The final run has no recorded Flutter framework errors or uncaught Android exceptions. A separate raster check found the reproduced green host-view border in the earlier run and **zero matching frame pixels in all 60 final captures**. Thirteen representative final captures were visually inspected, including all eight scenario types and enlarged landscape input/action states; their exact files and hashes are recorded in the verification JSON. This is a scoped keyboard and focus review, not an aggregate design-fidelity score.

## Evidence and provenance

- Current evidence: `.cache/revolut-design-20260906/native-keyboard-focus-final/`.
- Before correction: `.cache/revolut-design-20260906/native-keyboard-verified/` — 32 passing input checks, with the unwanted native frame still visible.
- Current mobile source: `f29944e674a548912d25feb985e1fea90c084bb13c2cf465eda5376b7e842fc5`.
- Retained QA APK: `app-dev-debug.apk`, SHA-256 `ab72d058ca4a8b00fed98fa0fb4bf2507cacff95c6b5d7da5a0c27c8eafdbbf8`.
- Source and harness hashes match before and after the final run. The installed APK hash was independently read during the run and matches the retained APK. Flutter drive's normal teardown subsequently uninstalled its disposable QA package; this is not a currently installed production candidate.
- Original Android font/orientation settings were read back after restoration. Only the disposable Collect AVD was stopped afterward.
- Analysis, source hygiene and whitespace checks passed. The earlier 742-test Flutter suite remains a prior result; the production change in this pass is Android host code, verified by the rebuilt native matrix.

Native form comparators `LIVE-056` and `LIVE-058` from the 5 September 2026 iOS Dark · Glow cohort were opened and inspected. They support component anatomy, required/optional field hierarchy and action placement. Their source build is unverified. Their private pixels remain in the local reference archive; paths and hashes are retained in `provenance.json`. Android's own keyboard appearance is a platform adaptation. The existing owner-selected RevPoints photo-card treatment and Collect's route colour families are retained.

Earlier setup attempts are retained outside the current evidence directory and excluded from the new gallery. Their driver corrections covered Android text deletion timing, RWF formatting, group-search entry and independent invitation storage. They are not additional passing cases.

## Review and remaining acceptance

Open [the native keyboard review](http://collect.localhost:4191/native-keyboard.html) or the [complete gallery](http://collect.localhost:4191/). The gallery lists the new OS keyboard captures separately and marks older source-bound native runs as historical. Browser checks at widths 320 and 1440 decoded all 60 images, verified the six surface tabs, and found no horizontal overflow or browser errors.

`MOBILE-DESIGN-100` remains **blocked**. Complete original-reference/state assessment, native screen-reader work, current iOS keyboard verification and exact production artifact acceptance remain open. No acceptance case or annotation was fabricated, no baseline was refreshed, and no production deployment or distribution was performed. Existing signed-in developer-account evidence and production access controls were preserved.

Machine-readable record: [native-keyboard-verification-2026-09-06.json](native-keyboard-verification-2026-09-06.json).

## Reproduction

Boot only the disposable Collect AVD at `emulator-5558`. From the repository root:

```sh
COOL_SIGN_PRODUCTION_DEBUG_WITH_PLAY_KEY=false \
COLLECT_KEYBOARD_EVIDENCE_DIR=.cache/native-keyboard-rerun \
/Users/jeanbosco/Developer/flutter/bin/flutter drive --no-pub \
  -d emulator-5558 --flavor dev \
  --target integration_test/mobile_native_keyboard_review_app.dart \
  --driver test_driver/mobile_native_keyboard_review.dart \
  --dart-define=COLLECT_MOBILE_EVIDENCE_MODE=true
```

The driver rejects any AVD other than the named disposable target. The fixture app rejects release mode and requires both the `dev` flavor and explicit evidence flag. Production entry points do not import it.

## Later iOS profile correction

The earlier Android results above retain their original source binding. The
subsequent iOS profile candidate fixes the nested-scroll behavior that left
Save below an open landscape keyboard: short viewports now scroll the header,
fields and Save together without dismissing the keyboard. Normal-height chrome
remains pinned, and stable keys retain focus and drafts when the layout changes.

All twelve native profile combinations passed: Rwanda MoMo number, optional
MoMo code and diaspora account number, each at 390 × 844 and 844 × 390 points
with native 100% and approximately 235% text. The field and enabled action were
checked separately after scrolling where needed, giving 24 passing observations.
Two early MoMo landscape screenshots were superseded by settled captures whose
visible keyboard and complete Save control match the measured geometry. The
earlier screenshots and one return-to-portrait observation requiring another
scroll remain retained rather than being counted as passes.

The iOS source fingerprint is
`e7cc34f87d6d49fb0f77f8e30a64588e98259c390722aa870b3f319728c26273`;
all 219 installed files matched its retained debug fixture. The profile suite
passed 21 tests and the mobile interaction suite passed 29 tests. Only synthetic
input was used. The test device's text/orientation settings were restored and
the disposable simulator was shut down after the driver and mirror exited.

See [the iOS profile verification record](ios-profile-keyboard-verification-2026-09-06.json)
for the exact candidate, case reports, screenshot hashes, restoration and scope.
The complete mobile design gate remains blocked with 166 findings. Other iOS
forms, native reader acceptance, full reference/state coverage and production
artifact approval remain open.
