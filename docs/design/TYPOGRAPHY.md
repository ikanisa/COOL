# Collect Typography

## Font Strategy

Collect uses open/system fonts only. The Flutter app defaults to system rendering with `Inter`, `Plus Jakarta Sans`, and `Manrope` fallbacks where available. No proprietary reference fonts are used.

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

RWF amounts, Collect IDs, contribution codes, provider references, and ledger
figures use tabular numerals through centralized text styles. This keeps
columns stable and improves scan speed.

## Copy Rules

- Put user impact before process details.
- Use everyday words.
- Avoid humor in risk, admin, payment failure, receiver consent, and SMS review.
- Repeat sensitive boundaries where decisions happen: Collect does not move money; public views do not expose phone, MOMO, or raw SMS.
