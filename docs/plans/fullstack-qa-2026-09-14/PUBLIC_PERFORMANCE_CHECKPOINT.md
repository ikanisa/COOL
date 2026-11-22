# Collect public performance and evidence checkpoint

15 September 2026 (Africa/Kigali). The full P0–P8 execution goal remains active.
The published home page fails the existing mobile Lighthouse budget. Two QA
evidence/reporting defects are repaired locally. No deployment, image edit,
native release or all-surface acceptance occurred.

## Measured public home page

Target: [Collect](https://collect.ikanisa.com/). Lighthouse 13.4.0 ran through
Node 24.19.0 and Chrome 152.0.7977.84 on macOS 26.6.2. Three mobile and three
desktop samples ran sequentially using Lighthouse's simulated profile
throttling. All six commands completed with no Lighthouse runtime error.
Each of the four required categories must remain at least 90; no budget was
lowered. These are home-page lab measurements, not a full-site or field result.

| Profile / sample | Performance | FCP | LCP | TBT | CLS |
| --- | ---: | ---: | ---: | ---: | ---: |
| Mobile 1 | 78 | 1.25 s | 6.18 s | 0 ms | 0.000118 |
| Mobile 2 | 77 | 1.28 s | 6.35 s | 0 ms | 0.000118 |
| Mobile 3 | 70 | 2.54 s | 31.39 s | 0 ms | 0 |
| Desktop 1 | 97 | 0.40 s | 1.24 s | 0 ms | 0.000274 |
| Desktop 2 | 98 | 0.35 s | 1.16 s | 0 ms | 0.000274 |
| Desktop 3 | 97 | 0.45 s | 1.27 s | 0 ms | 0.000274 |

The mobile median is 77 with LCP 6.35 s; desktop is 97 with LCP 1.24 s. The
31.39 s mobile outlier is retained. Automated accessibility, best-practices and
SEO scores are 100 in all six samples. An automated accessibility score is
not reader-task or full conformance evidence. Raw reports, exact commands,
profile configuration and the first mobile/desktop trace assets are retained
in the [baseline evidence](../../../.cache/fullstack-qa/20260914T151002Z/public-performance/lighthouse-baseline.json).

A separate DevTools desktop reload diagnostic observed LCP 251 ms and CLS 0
at 1440×1000 with no throttling. It used a warmed browser cache and must not
replace the mobile or cold-navigation measurements. The tool's raw-trace
path write was rejected; its returned summary and insights were saved after
a retry without an output path. No raw DevTools trace export is claimed.
The Lighthouse CLI trace assets are separate evidence.

DevTools reported no CrUX field data for this page. Field performance remains
unverified; lab TBT does not establish field INP, and these sample medians do
not establish real-user percentiles. [Core Web Vitals guidance](https://web.dev/articles/vitals)
and [Lighthouse scoring guidance](https://developer.chrome.com/docs/lighthouse/performance/performance-scoring)
support keeping those results separate.

## FQA-042: mobile image delivery remains open

The LCP element is Collect's `img.hero-editorial`, using
`kigali-woman-hero.png`. It is already eager, discoverable and high priority.
Three adjacent story images already use lazy loading; proximity to the
viewport still makes them download. The evidence does not support fixing
this by simply adding priority or lazy-loading attributes.

| Published original | Bytes |
| --- | ---: |
| community-savings.png | 2,426,242 |
| everyday-payments.png | 1,941,761 |
| banking-together.png | 2,166,126 |
| kigali-hills.png | 1,897,870 |
| kigali-woman-hero.png | 668,684 |
| **Total** | **9,100,683** |

A later normal browser read returned HTTP 200 and verified that all five
published hashes match their local originals. The first mobile report's
image-delivery insight estimates approximately 8,356 KiB of potential savings
and 2,600 ms LCP savings; those estimates are not a measured optimization.
Preserve the photos, crop, identity and selected visual treatment when
preparing a candidate, then compare its visuals and repeated performance.
No image or visible product surface changed in this continuation.

The existing `critical_first_party_bytes` check measures only root HTML,
base CSS and site JS: the current audit records 33,663 bytes. It excludes
other stylesheets, fonts and images and is not the total page payload.
The report now says so explicitly.

Fifteen recorded source/media inputs stayed unchanged during the baseline.
Two QA scripts changed afterward; the other thirteen still match. Python
HTTP snapshots before/after the samples returned 403 and are retained.
The later browser hashes bind ten resources but do not prove byte stability
throughout all six baseline measurements.

## FQA-041 and FQA-043: evidence and reporting repaired locally

The old Lighthouse gate accepted an arbitrary PDF over 100 bytes and a
high-scoring JSON report for another host, device profile and year. Twelve
of eighteen focused tests failed before the shared validator was added.
The gate now requires structured JSON with matching requested/final URLs,
device profile, browser/version/time metadata, a successful HTTP audit, no
runtime error and four scores in the unchanged 0.9–1 range. HTML/PDF may
supplement the report. The seven-day freshness window and five-minute future
tolerance are explicit local QA policies, not external standards.

The runner pins Lighthouse 13.4.0, retains command failures and both profile
reports, rejects output reuse and binds its source inputs. Its actual current
run exits 1: mobile 78 fails and desktop 97 passes. Both underlying Lighthouse
commands exit 0; the measured score causes the QA failure.

The completion report previously called code work green after failed checks,
inferred publication state and conflated Lighthouse with field Core Web
Vitals. Regression tests reproduced those errors and the missing-result
case. The report now uses actual required results, reports absent checks as
unverified, separates lab and field evidence, and preserves NO-GO. It does not
infer indexing, partnerships, store publication or deployment from a gate
failure or an accepted evidence/deferral artifact.

The actual completion gate exits 1. It accepts desktop Lighthouse evidence
and rejects mobile specifically for performance below 0.9. Static checks
pass 11/56 without a current accepted full static build; those 45 failed
checks are not asserted to be 45 distinct product defects. Live checks pass
35/36, retaining four broken links to three privacy/terms destinations. The
HTTP audit passes. Other external artifacts remain missing or invalid.
The actual report generator was then run against that saved gate JSON and
preserved NO-GO without repeating network requests. See the
[generated report](../../../.cache/fullstack-qa/20260914T151002Z/public-performance/completion-current/REPORT.md).

## Final regression and continuity

The final tooling target passes **156 Ruby tests with 711 assertions across
12 files, plus nine Python tests**, with zero failures/errors/skips. This
includes 24 Lighthouse/report regressions with 48 assertions. All 529
recorded inputs stayed unchanged during the final checks. Bash/Ruby syntax
and `git diff --check` pass. Six changed/new tooling files have immutable
snapshots. The final completion-gate wiring was exercised by the real gate.

Earlier framework evidence remains 87 focused Flutter passes. Five of its
527 source inputs now differ: Makefile, the three public QA scripts and the
previously exercised PWA lifecycle probe. Two new QA files are additional
inputs. The full Flutter result remains 867 passes and 74.65% measured line
coverage, with 611/615 inputs unchanged. CI, Makefile and two expanded test
files differ. Product Dart, original assets and platform inputs remain
unchanged; no new full Flutter or coverage run is claimed.

The existing synthetic Admin build still has 413 matching application inputs
and 154 matching artifacts. The prior installed PWA result remains 22 checks,
21 passes and one retained Chromium online-state failure; its actual network
blocking probes pass. The owned DevTools pages were closed, leaving the
pre-existing blank page. No independent CLI profile-removal claim is made.

The user's settings hash and the zero-case mobile acceptance file are
preserved. Both native gates remain blocked with 966 required cases per
platform. Native capacity remains unstable. Other public routes, image
optimization, field performance, native/member/Admin/database workloads,
complete recovery, provider/device evidence and independent/owner acceptance
remain part of the full active goal.

The [source checkpoint](../../../.cache/fullstack-qa/20260914T151002Z/public-performance/source-checkpoint.json),
[evidence manifest](../../../.cache/fullstack-qa/20260914T151002Z/public-performance/evidence-manifest.json)
and [verification](../../../.cache/fullstack-qa/20260914T151002Z/public-performance/checkpoint-verification.json)
bind the measurements, retained failures, current sources and this checkpoint.
