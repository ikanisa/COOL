# Collect Before/After UI Audit

## Before

- Theme had a small token set with limited colors, typography, radius, and spacing.
- Screens used direct `SizedBox`, `EdgeInsets`, Material buttons, `ListTile`, and localized status styling.
- Money cards existed, but amount hierarchy was inconsistent across home, detail, ledger, and payment screens.
- Empty, loading, and error states were not consistently available.
- Admin screen was missing from the active root Flutter tree while the router still referenced it.
- Receiver and payment boundaries existed in copy but were not expressed as reusable trust components.

## After Target

- Theme is centralized under `lib/app/theme/collect_*.dart`.
- Screens compose shared fintech components and tokenized spacing.
- RWF totals, progress, and payment states are visible first.
- Privacy and MOMO boundaries appear at relevant action points.
- Debug-only `/dev/design-system` demonstrates tokens and components.
- Admin, ledger, MoMo SMS, payment intent, share, invite, and profile screens use consistent state and review surfaces.

## Implementation Limitations

- No proprietary reference assets, exact screens, trademarks, or fonts are used.
- Golden tests are optional and should only be added after the sequential Flutter test runner is stable.
- This pass keeps payment execution outside the app; it redesigns payment-intent creation, MoMo USSD launch, and automated receiver-SMS verification.
