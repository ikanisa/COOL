# Home group card width — 4 September 2026

Owner request: Home group cards must run edge to edge, matching Groups.

Implemented in both **My groups** and **Featured groups**:

- Full content-width cards stacked vertically on phones, using the same page
  inset, 220 dp card height and 12 dp spacing as Groups.
- The same two-column layout as Groups when content width reaches 640 dp.
- No narrow 274 dp horizontal carousel. Existing group data, membership-aware
  actions and navigation remain intact.

`DESIGN.md` records the owner instruction. The Home regression now compares
rendered card bounds against the actual Groups screen at 320, 393, 430 and
800 dp with 100% and 200% text. It traverses each section so lazy rendering
does not confuse offscreen widgets with missing data.

Validation: 18 focused Home tests pass; Flutter analysis is clean;
`git diff --check` passes. The initial regression failed against the carousel.
The subsequent test adjustment explicitly scrolls to the taller Featured groups
section before checking it. Screenshots of the new Home and Groups cards were
opened and compared at matching widths.

The isolated Android 16/API 36 run passed the joined Home case at 393×851 dp.
`mobile_state_home-joined.png` shows full-width My groups cards, and
`detail_home-joined_featured.png` shows both full-width Featured groups cards.
Both native captures were opened and inspected. The redundant final screenshot
is blank and is retained as a diagnostic artifact, not accepted visual evidence.
The two usable captures independently establish the requested card geometry.

Evidence: `.cache/home-card-width-20260904/`. The 320 dp/200% capture confirms
full-width cards; its existing section-heading word wrapping remains within the
broader open accessibility/visual acceptance review. This change is not a claim
of full mobile visual acceptance.

**Local implementation only.** No production deployment or physical-phone
installation is part of this correction. `make mobile-design-gate` remains
BLOCKED on the existing approval, case, source and exact native artifact
requirements. No acceptance score or baseline was changed to pass the gate.
