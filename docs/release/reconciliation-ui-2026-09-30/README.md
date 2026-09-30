# Reconciliation operator workflow — local validation

Date: 30 September 2026. Scope: the Admin reconciliation route, its repository calls, existing-factor authenticator step-up, and the trusted finalization Edge handler. All data and network responses used here are synthetic. Database writes, hosted Auth requests, provider calls and deployments performed by this validation: **zero**.

## Implemented

- The existing `/admin/reconciliations` route opens the protected review queue. Payment review history and all-payment evidence history use explicit server limits, offsets and totals. Both queues recover to an existing page when results shrink.
- Operators can propose independent evidence, obtain approval from a different operator, and finalize as the recorded reviewer. Every sensitive action requires the existing verified TOTP authenticator. Missing factors, multiple factors, rejected codes, throttling, expired reviews and revoked authorization have safe recovery messages. Enrollment policy is unchanged.
- Finalization acknowledgements must match the requested review and payment UUIDs, contain an actual boolean replay flag, use the exact `independently_reconciled` evidence level, and report `posted` or a replayed `reversed` payment. A reversal replay never claims a new posting.
- The complete returned evidence lineage is accessible. Receiver routes, ledger journals and audit records have separate ten-record display pages; these are pages of the full detail response, not server pagination. Session IDs and unknown audit metadata are not rendered.
- Read and write results are bound to the initiating user and Auth session. Visible modal content disappears when that scope changes or confirmed permissions are revoked. Superseded responses cannot overwrite the new session's view. Permission refresh hides cached content until access is confirmed, and expiry is rechecked every 30 seconds.
- The MFA transport uses the pinned Auth HTTP contracts and adopts the verified session through the main SDK only after ownership, AAL2 and expiry checks. This avoids the pinned GoTrue MFA verifier's unconditional session mutation and shared web BroadcastChannel. The SDK bridge requires review on a dependency upgrade.

## Retained validation

| Check | Result | Evidence |
|---|---:|---|
| MFA dependency, response, account-switch and provider tests | 30 passed | `logs/focused-flutter.stdout.txt` |
| Repository request, response, denial and delayed-result tests | 36 passed | `logs/focused-flutter.stdout.txt` |
| Route, role, forms, paging, lineage, MFA, expiry and session widget tests | 22 passed | `logs/focused-flutter.stdout.txt` |
| Existing Admin paging, routes, sessions, reason-dialog and PWA regressions | 156 passed | `logs/admin-regression.stdout.txt` |
| Shared runtime component and typography contract | 47 passed | `logs/style-contract.stdout.txt` |
| Reconciliation Edge handler | 25 passed | `logs/edge-handler-tests.stdout.txt` |
| Edge entrypoint type check | Passed | `logs/edge-entrypoint-check.stderr.txt` |
| Targeted Flutter analysis | No issues | `logs/analyze.stdout.txt` |

The command manifests retain exact arguments and exit codes. `tested-source-before.json` and `tested-source-after.json` identify 51 scoped source, test, contract and font files; they are identical. `runtime-fingerprints.json` records Flutter 3.44.4, Dart 3.12.2, Deno 2.5.6, pinned Auth implementation hashes and package configuration. `validation.json` indexes the final evidence and SHA-256 values.

The final Flutter runs include the typography correction identified by the combined regression: the two reconciliation error messages now inherit `Theme.textTheme.bodyMedium`, with their existing semantic error colors. The 88 focused tests, 156 Admin regressions, 47 shared component tests and nine-file analyzer were rerun after that correction. Before-correction source manifests, validation and replaced logs remain in files named `before-typography-fix`. The 25 Edge handler passes and entrypoint check were retained from the earlier run; their source and pinned Deno runtime are unchanged. `typography-correction.json` records the exact source hash transition and validation scope.

Earlier attempt logs remain available. They record the role-refresh test and test-harness corrections; only the final named logs above establish the reported passes. The first capture attempt was interrupted after a fake-async capture stall. Final captures use real async rendering and the bundled fonts.

## Design evidence and limits

Authority: the owner-selected `revolut-design` skill, specifically its Business/operator patterns, brand adaptation and shared-component guidance. This is Collect's independent reconciliation workflow, implemented with its existing Admin page, theme, rounded neutral surfaces, text styles, pill actions and modal controls. No source branding or unsupported provider functionality was introduced.

The source context is the skill's Business 5/operator reference and public Business receipt-matching imagery. Those references support operational hierarchy and contextual review; they do not establish a measured, authenticated reconciliation screen. This route is an explicit product adaptation, not a claim of exact visual equivalence.

Inspected widget captures:

- `screens/approved-review-desktop.png`: 1200 × 950, light theme, approved synthetic review.
- `screens/evidence-form-narrow-text-200.png`: 390 × 844, light theme, 200% text, scrollable evidence form. Labels stay visible; the form scrolls to further fields while actions remain reachable.

These isolated widget captures do not establish installed-browser behavior, spoken screen-reader navigation, a full route/state visual comparison, or production approval.

## Remaining acceptance

F10 and S09 are not closed by these local passes. The separate `governed-reconciliation-2026-09-30` packet records the guarded 140 upgrade, 58 rollback assertions and both staged/numbered installation orders at version 140. Integration with the later revocation-lock migration, real two-session reconciliation-versus-role/session-revocation races and the post-141 staged-installer refusal are separate acceptance checks tracked in the current production register. Recheck the deployed endpoint, actual AAL2 Auth sessions, approved evidence provenance and the full operator dispute/reversal journey. Complete installed/web session switching, keyboard and screen-reader acceptance, and the broader Admin sensitive-action matrix.

F02 still needs an authorized authentic independent provider/statement source or an explicitly approved constrained finality policy. Evidence hashes and maker/checker reviews alone do not establish provider authenticity. Multiple verified TOTP factors currently require owner assistance to identify the approved factor; this change does not invent enrollment or factor-selection policy.
