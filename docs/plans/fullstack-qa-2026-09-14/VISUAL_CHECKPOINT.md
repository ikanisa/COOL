# Visual regression checkpoint — 14 September 2026

Scope: implementing-agent review of two existing 390 × 844 Flutter golden
differences and two existing website app screenshots. This is not independent
review, owner acceptance, native acceptance or a full-surface fidelity result.

The Home and Groups candidate PNGs and previous baselines were opened at
original resolution. The owner-selected group-card comparator
`/Users/jeanbosco/Desktop/Revolut/Cards.png` was also opened; its SHA-256 matches
the governed `owner-revpoints-cards` registry entry
`a724ba36d5b486141dde9419b4fd9702eee3562f0fd7cdf5b5f3b40fb8ba67c7`.
It governs the photo-card component, not all surrounding native UI.

The only changed pixels are within existing group photos: Home bounds
`[16, 694, 374, 772)` and Groups bounds `[16, 116, 374, 772)` in physical pixels.
Header, footer, navigation, labels and task geometry are unchanged. The
current deterministic fallback selects photos from the already-integrated
Rwanda group bank instead of repeating the former universal photo. Card
composition retains the full photograph, upper category caption, rounded
outline and lower contrast treatment of the selected comparator, with Collect
terminology and data. The reviewed photos have readable captions and no
observed clipping of their visible primary subjects.

Only these two regression baselines are refreshed to the exact reviewed
candidate bytes; no tolerance is changed and no new product image is made.
The old baseline bytes are retained under the ignored run's
`goldens-before/`. The remaining baselines are unchanged. Broader cultural,
localization, platform/state and owner reviews of the full asset bank are
still outside this checkpoint.

The current website Home and Groups PNGs were visually inspected. Full
resolution confirms all four Groups navigation destinations are present;
the initial reduced preview's apparent missing icons were a false positive.
The product-asset hash inventory is reconciled to these two existing captures
and the checked-in capture manifest. This only verifies the identified asset
bytes. `PublicAppMedia` still reports that screenshots need recapturing because
the runtime fingerprint changed; its freshness check is preserved.

Raw evidence: `.cache/fullstack-qa/20260914T151002Z/`, including
`golden-difference-analysis.json`, `golden-baseline-refresh.json` and
`checkpoint-checks.json`. All values are current local observations; earlier
repository reports were used only to trace the intended asset change.
