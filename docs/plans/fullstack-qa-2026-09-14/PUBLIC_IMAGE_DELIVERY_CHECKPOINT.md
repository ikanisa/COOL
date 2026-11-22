# Collect public image delivery checkpoint

15 September 2026 (Africa/Kigali). The full P0–P8 goal remains active.
Collect's existing public photographs now have a locally verified delivery
pipeline and browser fallbacks. Mobile performance improves in the controlled
fixture but still fails the unchanged Lighthouse budget. No deployment or
full static, native, independent or owner acceptance occurred.

## Delivery change

The six original PNG photographs remain unchanged. The new encoder creates
full-resolution WebP files with content hashes in their names. It verifies
dimensions, decoded alpha, colour-profile preservation and original hashes.
Opaque photographs use quality 92 and the transparent hero uses quality 95;
colour pixels are lossy. These are delivery encodings, with no resize, crop
or redraw. No pixel-identity or design-fidelity percentage is claimed.

| Scope | Original PNG bytes | WebP bytes | Reduction |
| --- | ---: | ---: | ---: |
| Six photographs | 11,259,743 | 1,230,960 | 89.07% |
| Five used on the home page | 9,100,683 | 1,022,200 | 88.77% |

The static builder validates the manifest before replacing output, copies
the encoded files and uses `<picture>` with the original PNG fallback.
Lazy photographs receive low fetch priority without overriding explicit
priorities. The landscape background uses `image-set` beside its original
declaration, preserving later responsive and forced-colour overrides.
Asset versions derive from the builder, delivery helper, CSS and manifest.

The encoder is pinned to Sharp 0.35.4 and libwebp 1.6.0. A locked dependency
package, Makefile check and public CI workflow step reproduce and compare
the encoded bytes. The locked installation, actual Makefile check and
workflow syntax pass locally; hosted CI was not run. See the
[encoder](../../../scripts/assets/build_public_photography.mjs),
[builder adapter](../../../scripts/public_photography.rb) and
[packaging instructions](../../../tools/public-photography/README.md).
[Sharp's output documentation](https://sharp.pixelplumbing.com/api-output/#webp)
describes the encoding controls; its options do not establish visual acceptance.

## Browser and visual verification

The component fixture combines recorded published HTML with current CSS and
the actual production adapter. The current builder's home function was also
rendered separately. This is component evidence, not a complete current site
build: the actual build still refuses stale native app screenshots with
`App screenshots need recapturing: runtime changed`. Its preflight sentinel
survives and no media validator was bypassed. See the
[actual build attempt](../../../.cache/fullstack-qa/20260914T151002Z/public-image-delivery/full-build-attempt.json).

The first direct image-source swap passed 30 comparisons, but the first
production `<picture>` implementation failed four home-page widths. The
`source` metadata element took a flex position, leaving a gap beside the
heading. The explicit metadata hiding rule repairs that regression; the
failed captures and pre-fix source remain preserved.

The final production component passes **30 comparisons** across `/`,
`/group-savings/`, `/diaspora/`, `/craas/`, `/insurance/` and `/our-partners/`
at 320, 390, 430, 768 and 1440 px. Text, titles, element geometry and image
dimensions match the original fixture, with no overflow, internal HTTP
failure or JavaScript error. Colour-channel differences are recorded as
differences, not converted into a fidelity score.

Another **24 comparisons** pass at 390 px across the same routes with
JavaScript disabled, unsupported WebP selection, forced colours and failed
photo requests. PNG selection, preserved text/links/layout and background
overrides are checked. Unsupported-format selection is injected into the
fixture; it is not an actual legacy-browser test. Failed photos retain the
existing presentation and links, rather than proving a complete offline task.
Assistive-reader tasks and other browser engines remain unverified.

An initial forced-colour comparison captured one header colour difference
before scroll rendering settled. The first attempt to wait for frames also
stalled with JavaScript disabled; it was terminated and its owned browser
and profile removal verified. The final capture waits for frames only when
page JavaScript is enabled. Both earlier attempts remain in the evidence.

Codex visually inspected before/after pairs for the hero and landscape,
community, everyday payments, banking and shared-goals photographs, and
the repaired 320 px home page. No material difference was identified at
those reviewed sizes. Those encoded bytes match the production artifacts.
The selected Revolut marketing reference was consulted, while Collect's
photos, text and identity were preserved. This is not independent review,
owner approval, complete reference matching or native design acceptance.
See the [visual review](../../../.cache/fullstack-qa/20260914T151002Z/public-image-delivery/visual-review.json),
[final width comparisons](../../../.cache/fullstack-qa/20260914T151002Z/public-image-delivery/component-fixed-visual-comparison.json)
and [final state comparisons](../../../.cache/fullstack-qa/20260914T151002Z/public-image-delivery/component-state-comparison-final.json).

## Performance remains below the mobile budget

Six serialized Lighthouse 13.4.0 samples used Node 24.19.0 and Chrome
152.0.7977.84 with the standard simulated mobile or desktop profile.
The current component ran on local HTTP/2 with gzip. This approximates
compressed delivery, but differs from the published HTTP/3/CDN service and
does not measure real-user performance. All six commands exit 0 without a
Lighthouse runtime error. Each required category must still score at least 90.

| Profile / sample | Performance | LCP |
| --- | ---: | ---: |
| Mobile 1 | 83 | 4.651 s |
| Mobile 2 | 84 | 4.458 s |
| Mobile 3 | 84 | 4.454 s |
| Desktop 1 | 99 | 0.840 s |
| Desktop 2 | 99 | 0.847 s |
| Desktop 3 | 99 | 0.847 s |

Automated accessibility, best-practices and SEO scores are 100 in these
samples. This does not establish full accessibility or functional coverage.
Mobile median performance is 84 and LCP is 4.458 s; desktop is 99 and 0.847 s.
**FQA-042 remains open.** Source size reduction and desktop success do not
close the mobile budget or field-performance requirement. The retained
published baseline remains mobile 78/77/70 and desktop 97/98/97; different
targets and transports prevent treating the comparison as a published gain.
See the [current component samples](../../../.cache/fullstack-qa/20260914T151002Z/public-image-delivery/component-benchmark.json).

All earlier lossless, photographic and balanced experiments are retained.
Uncompressed HTTP/1.0 previews distorted font delivery and are labelled
diagnostic only. A controlled HTTP/2 original sample scored 69 with LCP
15.336 s, while a balanced source-swap sample scored 83 with LCP 4.679 s.
These single samples support further investigation, not production acceptance.
The published `/c/` capture initially failed an all-200 assumption; a separate
readback verifies its declared 302 redirect to `/group-link/?slug=`.

## Regression, continuity and remaining work

Final local tooling passes **168 Ruby tests with 768 assertions across 13
files, plus nine Python tests**, with zero failures/errors/skips. All **552
recorded inputs** remained unchanged during the final checks. Twelve photo
pipeline tests contribute 57 assertions. The locked encoding check, syntax
checks and `git diff --check` pass.

The earlier full Flutter result remains 867 passes and 74.65% measured line
coverage, with 610/615 inputs unchanged: two CI files, Makefile and two expanded
test files differ. Of the earlier focused framework inputs, 521/527 match;
the static builder is one additional change. Of the preceding tooling run,
527/529 inputs match, with Makefile and the builder changed. No Flutter or
coverage rerun is claimed for this public pipeline change. All 413 synthetic
Admin application inputs and 154 artifacts still match. Original assets,
product Dart and platform source did not change in this continuation.

The user's settings and zero-case native acceptance file are preserved.
Both native gates remain blocked with 966 required cases per platform.
Free capacity was about 2.24 GiB at the source checkpoint and remains unstable.
The database fixture remains stopped with its volume retained. Scope discovery
still has 338 entries; discovery is not completed route/state acceptance.

All four owned HTTP/2 server processes and nine listener ports were verified
absent after shutdown. The temporary localhost certificate/key directory was
removed without modifying a trust store. Browser capture reports record
closure; independent Lighthouse profile deletion is not claimed. The first
cleanup path comparison stopped before deletion because `/var` resolves via
`/private/var`; corrected canonical-path verification and final cleanup pass.

The next work includes the remaining mobile critical path, legitimate native
media recapture and full static build, other routes and field measurements,
native/member/Admin/database workloads, recovery and provider/device evidence.
FQA-030 broken public links, FQA-011 native media freshness, FQA-040 PWA online
indicator and all other open findings remain active. No release gate or
required case was lowered, deleted or accepted by inference.

The [source checkpoint](../../../.cache/fullstack-qa/20260914T151002Z/public-image-delivery/source-checkpoint.json),
[evidence manifest](../../../.cache/fullstack-qa/20260914T151002Z/public-image-delivery/evidence-manifest.json)
and [verification](../../../.cache/fullstack-qa/20260914T151002Z/public-image-delivery/checkpoint-verification.json)
bind current sources, failed attempts, final results and this report.
