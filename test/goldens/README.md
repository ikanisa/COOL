# Collect Golden-Test Protocol

These baselines are deterministic Flutter widget renderings for regression
detection. They are QA evidence, not runtime product assets and not substitutes
for the verified Revolut source/implementation comparisons required by
`design-qa.md`.

## Covered surfaces

- Member: authentication, Home, Groups, global Contribute, Activity, Profile,
  Group Detail, contribution review, Ledger, offline recovery, and Appearance.
- Public: desktop landing page.
- Admin: authenticated desktop operations overview with sanitized fixture data.

Member surfaces render at 390x844. Public and Admin surfaces render at
1440x900. Every test uses the Android platform variant, disables animation,
loads the bundled Inter variable font and Flutter Material Icons explicitly,
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
