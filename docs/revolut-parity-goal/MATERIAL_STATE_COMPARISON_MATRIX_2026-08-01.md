# Collect x Revolut Material-State Comparison Matrix

Date: 2026-08-01  
Checkpoint: E-078  
Target: exact iPhone 17 Simulator, iOS 26.5  
Scope: current working-tree mobile material states in Dark, Light, and System
on an explicitly Light platform appearance

## Evidence boundary

This matrix advances CRP-302 and RT-005 by replacing route-only inference with
deterministic, current-source captures of 16 material Collect states. It does
not create missing Revolut evidence and does not treat pattern similarity as
feature or state equivalence.

The only admissible reference classes are:

- **Direct**: a retained Revolut capture of the same material state. None of
  the new authentication, contribution, deletion, or recovery captures qualify.
- **Pattern-only**: a retained Revolut capture supports hierarchy or geometry,
  while the Collect state and product meaning remain different.
- **No direct analogue**: the state is Collect-owned and must be judged against
  Collect safety, privacy, recovery, and product-language requirements.

The run used fixture-only evidence mode. It did not execute a real payment,
request an OTP, read an SMS, mutate production, or retain customer data. The
dummy review phone is masked after the OTP step and the MoMo receiver is shown
as `078***3456` in contribution review evidence. No personal-local-only
Revolut screenshot is reproduced here.

## Accepted current-source matrix

| Variant | Result | States | Unique screenshots | Summary SHA-256 | Log SHA-256 | Screenshot manifest SHA-256 |
| --- | --- | ---: | ---: | --- | --- | --- |
| Dark | Pass | 16/16 | 16 | `acbadd10b3f48c63aac9ba57998ca381254be82bb4314e8071697dc84e4ec0fe` | `bd7750294f7647d0bd53b9e21739548ccee7925c2fa2397f334b9732f8bab6de` | `44c28f2a7bb56ad3648d8527f47ed752f000bb7defb9c1f1f47757d39d8238e5` |
| Light | Pass | 16/16 | 16 | `c2c31ae574f421ea91bd723e4290d19e45345e6b1e1277fee7c477cb6aa4026b` | `74613d48bfb72827d9232e17669e18eaddc6d085b6e791fd3270194e0ec7d3b0` | `0fd07e67de4add6c2c1cc6d591fccf9a4b78695c23a26ed7266433bb8e5a91bd` |
| System / iOS Light | Pass | 16/16 | 16 | `a0df062fcedf14f7e6c9c566756743d31344b057e96a2e70537fceeff4cbf285` | `84cc1a619a9a5cd67442b38feb5b1ec91adb18fe08fa52e9caafcea4fd9b7cd5` | `0fd07e67de4add6c2c1cc6d591fccf9a4b78695c23a26ed7266433bb8e5a91bd` |

System produced the same screenshot manifest as explicit Light after the
Simulator appearance was explicitly set to Light. That is expected theme
resolution, not duplicate-evidence inflation. Each variant independently
emitted its compiled variant marker, all 16 state-pass markers, the completion
marker, and zero failure keys.

## State dispositions

| State | Collect evidence | Comparator class | Retained pattern | Confidence | Mismatch severity | Disposition and owner |
| --- | --- | --- | --- | --- | --- | --- |
| Phone entry, empty | `auth-phone-empty` | Pattern-only | R-INVEST compact state geometry | High for Collect; low for parity | P1 evidence gap | Current Collect hierarchy accepted; direct reference remains RT-002, Product Design/user. |
| Phone entry, valid | `auth-phone-valid` | Pattern-only | R-INVEST geometry only | High for Collect; low for parity | P1 evidence gap | Enabled action is visible and distinct; direct reference remains RT-002. |
| OTP, empty | `auth-otp-empty` | No direct analogue in retained set | None | High for Collect; none for parity | P1 evidence gap | Masked destination, change/resend, and disabled verify state are verified; direct reference remains RT-002. |
| OTP, invalid | `auth-otp-invalid` | No direct analogue in retained set | None | High for Collect; none for parity | P1 evidence gap | Error, recovery actions, and enabled verify state are visible; direct reference remains RT-002. |
| Groups, empty | `groups-empty` | Pattern-only | R-INVEST focused empty-state geometry | High | P3 | One thesis and one next step; Product Design confirms pattern disposition under RT-005. |
| Activity, empty | `activity-empty` | Pattern-only | R-PAYMENTS list rhythm; R-INVEST empty geometry | High | P3 | Truthful zero-state retained; no fabricated transaction or parity claim. |
| Contribution entry, empty | `contribution-entry-empty` | No state-matched direct reference | R-PAYMENTS selection rhythm only | High for Collect; low for parity | P1 evidence gap | Amount zero and disabled review action verified; direct amount reference remains RT-001. |
| Contribution entry, valid | `contribution-entry-valid` | No state-matched direct reference | R-PAYMENTS selection rhythm only | High for Collect; low for parity | P1 evidence gap | Formatted RWF value and enabled review action verified; direct amount reference remains RT-001. |
| Contribution review, new | `contribution-review` | No state-matched direct reference | R-CRYPTO summary/status rhythm only | High for Collect; low for parity | P1 evidence gap | Group, amount, masked receiver, MoMo handoff, and edit path verified; direct review reference remains RT-001. |
| Contribution review, reused | `contribution-review-existing` | No state-matched direct reference | R-CRYPTO status rhythm only | High for Collect; low for parity | P1 evidence gap | Duplicate-intent explanation and reuse action verified; lifecycle correctness remains governed separately. |
| Delete request, disabled | `account-delete-disabled` | Pattern-only | R-SECURITY destructive hierarchy | High for Collect | P2 safety review | Disabled danger state is visibly quiet; Product Design confirms Collect-owned deletion disposition. |
| Delete request, enabled | `account-delete-enabled` | Pattern-only | R-SECURITY grouped controls | High for Collect | P2 safety review | Reason-selected state and enabled destructive action are distinct. |
| Delete confirmation | `account-delete-confirmation` | No direct analogue in retained set | R-SECURITY hierarchy only | High for Collect | P2 safety review | Retention warning and cancel/submit decision remain explicit; no Revolut deletion parity claim. |
| Offline recovery | `offline-recovery` | Pattern-only | R-INVEST recovery geometry | High for Collect | P2 device/live gap | Saved/read-only boundaries and recovery action verified visually; live transition evidence remains separately governed. |
| Sync recovery | `sync-recovery` | Pattern-only | R-INVEST recovery geometry | High for Collect | P2 device/live gap | Pending/protected state and recovery action verified visually; this is not production sync proof. |
| Missing group | `missing-group` | No direct analogue | None | High for Collect | P2 deep-link recovery | No stale membership is implied; safe routes to Groups/Profile remain visible. |

## Visual review

All 12 contact sheets were visually reviewed at their original rendered size.
The accepted captures have no visible Flutter overflow, clipping, unsafe-area
collision, obscured primary action, or unmasked MoMo receiver. Disabled and
enabled actions remain distinguishable, the invalid OTP state keeps its error
and recovery controls together, and deletion confirmation preserves a clear
cancel path.

| Variant | Authentication | Contribution | Deletion | Empty/recovery |
| --- | --- | --- | --- | --- |
| Dark | `2bbca31997d527ee71ee8b7323447f573f2fbc1ed14ab8ce3a96dca166612860` | `f738ead502e8a98946e196a1985ede1d502444dc64db424dc7b2fe0941ae3967` | `55f225b78b1427393ff74d313e29548c255b2d4a6b883f2ab493a18ab497cf9f` | `8880164cf670dd8d141580479f1725b116d7408ff65fb3a5315f507f6cdcb1ef` |
| Light | `7cce5cbe1fe0fff0ac50d33fdaebeebf775ac5dbd17877fb3e22593cbc7eed58` | `c4b04bbf9a654dcb37331f1cb5ab74b29dd8f85837519a167564441d0d1eb1e4` | `1a8a2fd35ad36a77e9ee2c916698ab394f69cfc1939a897c550749ff28fb483f` | `ff67010277d6c1f74a5ee8f3ccce0c941418927339c062628c994975ecfaabe0` |
| System / iOS Light | `62e6319b64973c50885378d4646d2ea2add6d6cb3d45afd0662bd60c840f1001` | `691060bad1351df935ceb2b24dc02daa6da2f6ab6620822677e4696e69b1a82d` | `6c5b038ae96f3fe756ccbd8ddf589044ad43f92fd4298445fb5e4c823b616d7f` | `ecbda102e223eae9e0fef589a33a322ac4e6168fd554577d7c7e41d3a999cbc1` |

## Rejected evidence

Calibration variants v1 through v7 are retained but excluded. Early runs
failed the contribution-valid assertion or stalled before an accepted
completion marker. The first technically passing captures exposed the complete
fixture MoMo receiver during visual privacy review. Evidence-mode masking was
then added without changing normal product behavior, and only Dark v8 plus the
subsequent Light and System-Light runs are accepted.

## Critical conclusion

E-078 closes the local absence of a deterministic material-state capture
harness for these 16 states and provides a reviewed three-theme Collect matrix.
It does **not** close RT-001, RT-002, RT-005, CRP-301, or Product Design
acceptance. Direct Revolut authentication/OTP and amount/review references are
still absent, no approved no-direct-analogue decision has been signed off for
every Collect-owned state, and screenshots do not prove spoken assistive
technology, physical-device lifecycle, production recovery, or release
readiness.
