# Authentic app media on the Collect website

The owner requested that every app screenshot on the public website accurately represent Collect's actual UI and flows. The static website's invented phone templates and their CSS have been removed.

## Implemented media

| Website page | Current media |
| --- | --- |
| Group Savings | Native Collect group details |
| Diaspora | Native diaspora contribution entry |
| Community Groups | Native Groups, including Rwanda photo cards |
| Trust and Security, including `/security/` | Native security settings |
| Privacy and Terms | Their actual native policy screens |
| Account and Data Deletion | Native deletion entry, before submission |
| CRaaS and Credit Readiness | Rwanda finance editorial photography |
| Insurance and Protection | Rwanda shared-goals editorial photography |
| Partners, including `/partners/` | Rwanda finance editorial photography |

Eight unchanged native PNGs, including a reusable Home capture, are retained in `web/public/app-screens`. They were produced by the actual app on the isolated iOS fixture simulator. The installed app's 219 files matched the freshly built and retained bundle. Every selected original was visually inspected; the stable capture run produced identical bytes. The website labels these screens **Collect app · Example data**. The photographs are the existing generated Rwanda illustrations; they do not depict verified customers or partners.

`manifest.json` records each route, original capture, dimensions and image hash. `capture-provenance.json` retains the native run's capture inventory. The build checks app code, platform resources and declared assets, fonts and licenses; verifies original PNG hashes; and rejects missing, altered or stale app media before replacing the previous build. Checked-in provenance supports a clean checkout without requiring the local simulator bundle.

## Verification

- All 16 public routes at 320, 390, 834 and 1440 pixels: passed. The 16 share-flow checks also passed; 192 browser captures retained.
- Public website source gate: 56/56 passed.
- Existing copy outside replaced hero artwork: unchanged on all 19 generated pages. The reviewed content-baseline changes remove invented phone text and add the example-data captions; legal copy, product copy and CTAs remain unchanged.
- All 42 mobile routes and 56 material states in four platform/theme/text configurations: 392 widget checks passed. Another 81 responsive checks passed.
- Native iOS: 42 dark routes passed; 56 light, 200% text flow states passed, with 72 state/scroll captures. The installed bundles match retained builds. Text scaling and contrast are fixture overrides, not native VoiceOver acceptance.
- Native navigation: 20 checks passed. Original OS and UIKit PNG pixels contain all four icons. The earlier apparent omission was a reduced-preview artifact; the corresponding finding was a false positive.
- Gallery: 1,041 unique images decoded successfully, 128 current website records, and no unreviewed retired hashes served.

Two unbundled image-planning documents were added during testing. The complete prior runtime hashes were reproduced exactly after excluding only those newly added files. `runtime-media-fingerprint-migration-2026-09-06.json` records that proof. Local media freshness now follows bundled runtime inputs. The production `MOBILE-DESIGN-100` gate and its wider source fingerprint were not changed. The native state run retains both differing full source fingerprints and explicitly records the added README.

The old website screenshot sources (384 PNGs) were moved out of the checkout into `/Volumes/PRO-G40/Collect-retired-design-20260906`. The retirement registry was extended without overwriting prior records. Seven freshly captured native images reproduce existing screen pixels exactly; only their validated current asset paths are allowed in the gallery. An equal hash at an obsolete source path is not sufficient to reinstate it.

## Evidence and boundary

See `website-authentic-app-media-verification-2026-09-06.json`, the app-media manifest, and `current-review-inputs.json` for retained evidence paths and hashes. The failed launch and earlier source-change runs remain recorded separately.

This is a local implementation and review update. No production deployment, app distribution or financial action was performed. The disposable Collect simulator was shut down. Complete mobile design acceptance remains blocked by the exact release candidate, complete acceptance matrix, native accessibility and final visual review requirements.
