# Feature-flag reason correction acceptance

**PASS: 17 production feature-flag UI cases and nine shared default/focus cases.**

The feature-flag consumer supplies an 8–500 Unicode code-point range to the existing shared reason dialog. Other callers retain its 1–1000 default range. Actual production widgets use the locked Supabase SDK with synthetic HTTP responses; invalid reasons dispatch no write, and valid reasons bind the exact trimmed request and acknowledgement.

## Cases

| Feature-flag production UI case | Result |
| --- | --- |
| success | SUCCESS |
| cancel | SUCCESS |
| invalid | SUCCESS |
| revoked-draft | SUCCESS |
| role-draft | SUCCESS |
| loading-draft | SUCCESS |
| error-draft | SUCCESS |
| session-draft | SUCCESS |
| late-ack | SUCCESS |
| unknown-ack | SUCCESS |
| denied | SUCCESS |
| reason-7 | SUCCESS |
| reason-8 | SUCCESS |
| reason-500 | SUCCESS |
| reason-501 | SUCCESS |
| reason-unicode-7 | SUCCESS |
| reason-scalar-8 | SUCCESS |

| Shared default/focus case | Result |
| --- | --- |
| reason rejects 1 code points | SUCCESS |
| reason rejects 1001 code points | SUCCESS |
| reason rejects 1001 code points | SUCCESS |
| reason preserves 1000 code point input | SUCCESS |
| reason preserves 1000 code point input | SUCCESS |
| reason preserves 22 code point input | SUCCESS |
| oversize reason is retained for correction and cancellation | SUCCESS |
| reason remains editable with compact keyboard and large text | SUCCESS |
| reason dialog restores focus to its triggering control | SUCCESS |

## Exact verification scope

- One affected selection: `flutter test --plain-name "featureFlag production UI" test/admin_custom_action_ui_test.dart`.
- Nearest unchanged-default/focus regressions: `admin_reason_dialog_bounds_test.dart` and `admin_reason_dialog_focus_test.dart`.
- Selected nonwriting formatter and fatal-info analyzer passed.
- An isolated declared export used Flutter 3.44.4 / Dart 3.12.2 from the root192 SDK with lock-enforced offline package resolution.
- Consumed application, assets, forks and selected test inputs, exported authored inputs, SDK inputs and resolved package libraries were unchanged.
- No production or test edit was made by this verifier.
- No SQL, hosted/provider, browser or native operation ran. This packet does not certify whole Admin, every runtime-control family or persisted server audit.

## Affected source hashes

| Source | SHA-256 |
| --- | --- |
| lib/admin/core/admin_list_runtime.dart | `86c69da4b84486f8054eb61f0b9a8119888cd21421ad2f6aba67ba0555101921` |
| lib/admin/shared/components/admin_confirm_dialog.dart | `126876be268a2e72dac7a76e4ac156de3e72d15824454615603471c33e0eec4f` |
| test/admin_custom_action_ui_test.dart | `23016c22dab6936681c7ba479648afeabf53181a1cd89001e40a116669767552` |

Validation SHA-256: `887522f1b12ed998c81780cfe27edad5c5577f81a80030851990ba99412f6cc8`. Exact command logs, package/SDK/source manifests, machine events and individual results are retained beside this report.
