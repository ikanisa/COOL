# Shared accessibility and compact layout — current rendered scope

The exact Flutter 3.44.4 artifact is retained in sibling `attempt5/artifact`; its 540 source files are retained in `attempt5/source`. Both manifests remained equal before/after compilation and copy. This attempt reuses those exact bytes and corrects the browser harness measurement of partially clipped, offscreen accessibility bounds. The original harness failure is preserved here.

120 widget tests passed: 27 focused shared header/control/state/compact tests, 27 financial recovery tests and 66 responsive/keyboard cases. Scoped fatal analyzer checked 11 items with no findings. A meaningful isolated old-source negative test fails the new 320/1x whole-word assertion while 390/1x and 320/2x pass. Its failed setup predecessors remain in the cache and do not count as product proof.

Actual Chrome 151 ran 25 route/state cases and 205 assertions at 320x568 with normal/2x text, plus the 390/1x group comparison. No runtime errors, response-body errors, hosted/provider/database calls were observed. Optional remote Roboto was blocked; Collect uses bundled Inter. Real forward/reverse Tab and Enter activated shared controls, navigation and recovery actions. Disabled controls remain inert in widget tests.

## Corrections and visual review

Shared, legal, Settings and Members task headings now have one level-1 semantic heading and an independent Back control. Sections use level 2. The duplicated Activity and recovery announcement wrappers were removed while child buttons retain independent focus/actions. Financial refresh wording does not confirm a payment, claim provider retry or hide stale/failure states.

Quick actions measure the longest word with the actual current text scaler. At 320/1x Contribute stays whole in the existing two-column wrap; 390/1x keeps four columns. At 320/2x all labels remain whole and equally sized after real scrolling brings the second row into view. Inspected those three actual screenshots, enlarged legal/recovery outcomes and keyboard focus images. Enlarged bottom navigation deliberately shows icons with full accessible names; the existing behavior is retained.

Terms and Security Back arrows and group navigation icons were already visibly painted. Earlier empty-capsule findings were mistaken; no fabricated arrow/icon fix was made. Members search hint abbreviates visually while its accessible name remains complete.

## Limits

This validates the declared local synthetic browser cohorts and widget matrix. It does not validate spoken screen-reader output, native/physical-device behavior, all product routes/states, hosted providers or complete Revolut design parity. The owner-selected Revolut native Settings comparator LIVE049 supports the shared hierarchy; no artwork was copied. L17 remains open for any required unsampled product surface/state and external native/design acceptance. Older failures and dated packets remain distinct.

The copied artifact includes the then-current root NotificationSettingsScreen. Later unrelated Admin/runtime changes do not alter the owned UI snapshot; final normal browser/native/media acceptance must bind their final source separately.
