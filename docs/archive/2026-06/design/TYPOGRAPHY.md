# Collect Typography

## Font Strategy

The current Flutter implementation names `Hanken Grotesk`, `Inter`, and `Roboto` as fallback families in `lib/app/theme/collect_typography.dart`, but it does not bundle those font files and it does not yet use the borrowed Revolut typeface.

The 100 percent borrowed Revolut alignment target is to install the approved Revolut font files, register them in `pubspec.yaml`, and make the borrowed Revolut family the primary app font across member, admin, and public surfaces. Fallback fonts are allowed only as resilience after the approved Revolut family is configured.

## Scale

- Display: first-screen brand or large money moments.
- H1/H2/H3: screen and section hierarchy.
- Title: cards, dialogs, bottom sheets.
- Body: default reading copy and form guidance.
- Compact: dense admin rows and metadata.
- Caption: secondary labels.
- Micro: badges and short status details.
- Amount hero: RWF totals and payment amounts.

## Numeric Rules

RWF amounts, Collect IDs, provider references, and ledger
figures use tabular numerals through centralized text styles. This keeps
columns stable and improves scan speed.

## Copy Rules

- Put user impact before process details.
- Use everyday words.
- Avoid humor in risk, admin, payment failure, receiver consent, and SMS review.
- Repeat sensitive boundaries where decisions happen: Collect does not move money; public views do not expose phone, MOMO, or raw SMS.
