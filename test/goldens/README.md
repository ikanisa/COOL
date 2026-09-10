# Collect Golden-Test Protocol

These baselines are deterministic Flutter widget renderings for regression
detection. They are QA evidence, not runtime product assets and not substitutes
for the verified Revolut source/implementation comparisons required by
`design-qa.md`.

## 5 September 2026: owner-selected RevPoints group cards

The implementing agent opened the new Home and Groups test images and compared
the photo-card composition with the owner's `Desktop/Revolut/Cards.png`.
Only those two baselines were refreshed for this change. Their previous copies
are retained in `.cache/revolut-design-20260905/revpoints-group-cards/goldens-before/`.
Visible image providers are now precached before captures so the regression
images contain decoded photos, rather than an incidental loading frame.
The cards retain Collect's page colours, real data and contribution actions.
This records agent visual review, not owner acceptance or mobile release approval.

## 10 September 2026: current Rwanda group-cover defaults

The implementing agent opened the previous and candidate Home and Groups
images side by side. Only the group-card photographs changed: the current
Rwanda cover bank replaces the repeated older photograph with category-specific
community scenes. Card geometry, blue Home and teal Groups backgrounds, labels,
balances, actions and navigation are unchanged. Only these two baselines were
regenerated, with the existing comparison tolerance retained. This is agent
review of widget regression expectations, not owner or native release approval.

## Covered surfaces

- Member: authentication, Home, Groups, global Contribute, Activity, Profile,
  Group Detail, contribution review, Ledger, offline recovery, and Appearance.
- Public: desktop landing page.
- Admin: authenticated desktop operations overview with sanitized fixture data.

Member surfaces render at 390x844. Public and Admin surfaces render at
1440x900. Every test uses the Android platform variant, disables animation,
loads the bundled Inter variable font, public-only Aeonik Pro faces and
Flutter Material Icons explicitly,
and uses fixture-only local data.

## Verification

Run:

```sh
flutter test --no-pub test/goldens/collect_core_surfaces_golden_test.dart
```

Only update baselines after opening and reviewing every changed image:

```sh
flutter test --no-pub --update-goldens \
  test/goldens/collect_core_surfaces_golden_test.dart
```

After an approved update, refresh `GOLDEN_MANIFEST.sha256` and record the
review in the evidence register. Never accept an update merely because the
command generated PNG files.


## 5 September 2026: explicit route palette follow-up

The implementing agent opened all twelve changed test images before copying
those pixels into the regression baselines. Home, Groups, Activity, Profile and
WhatsApp login were compared with DESK-003/004/005/007/001 respectively. Embedded
HP 524sf colour profiles were converted to sRGB for token measurements; source
images remain unchanged. Focused tasks remain neutral. Generated group artwork
uses the new palette, while Collect logo pixels stay unchanged. Appearance was
reviewed again after its Activity panel adopted the actual Home panel token.
The contribution-review baseline did not change in this follow-up.

This is agent review of local widget regression expectations. It does not grant
owner acceptance or native release approval. The twelve previous baselines are
retained in `.cache/revolut-design-20260905/goldens-before-palette/`. Measurements
and limitations are in `REVOLUT_PALETTE_MEASUREMENTS_2026-09-05.json` under the
mobile-design release evidence directory.

The exhaustive surface pass on 5 September also reviewed the Admin overview
image after exposing its persistent header controls to accessibility tools and
expanding the country/operator hit regions. The first reviewed change was inside the header; a subsequent review also
covered the 48px overview control and its one-pixel effect on the header height.
Both new 1440×900 images were opened before refreshing this single baseline. All mobile goldens stayed
unchanged. This remains agent review of a local regression expectation.

The owner-requested Rwanda image follow-up replaces the public portrait and
background with the generated Kigali woman and hillside assets. The implementing
agent opened the new 1440×900 public test image and reviewed its composition,
copy contrast and crop before copying only that image into the public baseline.
The preceding public baseline is retained in
`.cache/revolut-design-20260905/goldens-before-rwanda/`. This visual review does
not grant owner acceptance or mobile release approval.

### 6 September 2026 — public hero contrast

Only `public_home_desktop.png` was refreshed after agent visual review of the stronger photo scrim. The previous PNG is retained in `.cache/revolut-design-20260906/goldens-before/`. The final 742-test suite passes. This baseline review does not grant complete surface or release acceptance.

## 6 September 2026: current Home and recipient labels

The implementing agent opened the two changed candidate images before promoting them: Home now uses Explore Groups, and contribution review shows the beneficiary and number without the redundant network prefix. All 14 checks then passed at the original tolerance. Earlier product baselines and failure composites referenced above have been retired outside the checkout; consult `docs/release/mobile-design/retired-design-assets.json` and the current-system refresh report. This is local regression review, not owner or native release acceptance.
