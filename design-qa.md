# Design QA — legacy Collect chrome cleanup

Date: 2026-08-04

## Scope

- authentication phone, confirmation, OTP, invalid-code, and recovery states;
- shared customer gradient, cards, sheets, headers, status surfaces, and inputs;
- bottom navigation and tablet rail;
- Home, Groups, Contribute, Activity, Ledger, Settings, and recovery routes;
- six-state interactive contribution prototype.

## Visual comparison

- Compared the retained Revolut phone, confirmation, OTP, and invalid-code references with the current Collect captures in the same review pass.
- Compared the two user-supplied legacy screenshots with the current native phone and OTP captures.
- Inspected all 13 core goldens, all 6 prototype goldens, the 17-state native matrix, and representative screens from the 35-route matrix.
- Applied the product owner's explicit reference boundary: publicly accessible and retained unblurred references are sufficient, while Collect-only amount, MoMo, deletion, and recovery states use documented no-direct-analogue dispositions instead of requiring personal-account captures.

## Acceptance checks

- No boxed WhatsApp panel, custom `RW` badge, masked-phone anchor panel, floating blurred nav, route-specific gradient, or backdrop-blur customer card remains.
- Phone entry, number confirmation, OTP, invalid-code, bottom actions, and keyboard recovery remain reachable and readable.
- Shared cards and sheets use solid hierarchy without broad shadows or ornamental borders.
- Bottom navigation is edge-to-edge and no longer floats in a capsule.
- No observed clipping, unsafe-area collision, overflow stripe, missing primary action, or broken back navigation in retained captures.
- Empty, error, offline, sync, and deletion states retain semantic state and recovery actions.
- Evidence contains fixture data only and is not represented as production or physical-device proof.

## Validation

- `flutter analyze`: passed.
- Full Flutter suite: 449/449 tests passed on the current source after the final auth scroll guard; the release-wide completion sentinel remains fail-closed below.
- Core golden suite: 14 tests passed after repinning 11 intentionally redesigned customer baselines.
- Prototype golden and interaction suite: 7 tests passed.
- iPhone 17 fixture-only material-state matrix: 17/17 states passed.
- iPhone 17 fixture-only route matrix: 35/35 routes passed.

final result: passed
