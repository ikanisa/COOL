# Current system design refresh — 6 September 2026

The obsolete form and gradient-card screenshots reported by the owner came from the gallery’s historical-run aggregation. They were still displayed after the shared runtime component had been replaced. This refresh removes those product images from the checkout and makes the current gallery reject them.

## Replacement and cleanup

All four `GroupCard` variants delegate to the shared editorial photo card. Home and Groups use that component; the contribution chooser retains its task-specific list. The old short image-strip/footer design has no remaining runtime implementation. Obsolete numbered group-card colour variants were also removed from the public website generator, whose current neutral marketing cohort is preserved. The stale Home source assertion now requires Explore Groups and the featured public route.

The gallery now uses current runtime fingerprints and image hashes, excludes historical/before-correction captures, rejects hashes in the retirement manifest, and removes unreferenced generated media. Its default input manifest points to the current route/state matrix, so a routine refresh cannot select the older gallery inputs. A changed runtime invalidates the current matrix instead of silently republishing it.

Removed **1,171 obsolete capture files (584 distinct images)** from the codebase, plus **42 obsolete golden failure composites**. Recoverable copies are outside the checkout at `/Volumes/PRO-G40/Collect-retired-design-20260906`. The retirement manifest records hashes and paths. Original Revolut comparator images, Collect runtime artwork, the required route/state cases and acceptance findings are retained. The annotated old image URLs now return 404.

## Current verification

- **750 tests passed**, after replacing the obsolete scan-action assertion. No remaining full-suite failure.
- **42 routes and 56 states in each of four layouts**: Android and iOS, dark 100% text and light 200% text. All **392 route/state checks passed**. Existing iOS creation guards are exercised rather than changed.
- **634 fresh captures** cover those route/state/scroll views and the responsive matrix. The small-phone, tablet, landscape, keyboard simulation and editorial card suite passed **91 tests**.
- **14 golden checks passed**. The two changed images (Home and contribution review) were opened and visually reviewed before copying them into the regression baselines. The original comparison tolerance was preserved.
- Source analysis and hygiene passed. The design-gate implementation passed **33 tests / 131 assertions**; gallery freshness regressions passed two tests. The static public website rebuilt successfully.
- The gallery contains **763 current mobile records**. All **969 distinct catalogue images** decoded; no retired image hash was served. The filtered browser review showed the corrected Android forms and iOS photo cards without browser warnings/errors.

These new matrix images are Flutter widget renders using Android/iOS platform layouts, not fresh native OS captures. The earlier real Android keyboard images remain bound to their original APK, with separate runtime-equivalence verification. Representative current images were visually inspected; this is not full reference-by-reference visual acceptance.

`MOBILE-DESIGN-100` remains blocked. No score, required case, acceptance annotation or production permission was removed or lowered. This work does not deploy the pending MoMo-code migration or approve a production release.

[Current gallery](http://collect.localhost:4191/) · [Verification record](current-system-refresh-verification-2026-09-06.json) · [Current gallery inputs](current-review-inputs.json) · [Retirement manifest](retired-design-assets.json)
