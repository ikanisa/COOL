# Public website QA checkpoint

14 September 2026. Full-system execution remains active. This checkpoint
records source discovery, read-only published-site checks and a local CSS
repair. It does not establish release or former mobile visual acceptance rule acceptance.

## Scope correction — FQA-028

The full-stack scope exporter incorrectly reused the nine Flutter public
routes for the independent static website. Its actual source is
`scripts/public_static_site_build.rb`: 12 primary pages, four aliases, three
share/app landing paths and two redirect patterns, for **21 entries**.

The new Ruby syntax reader extracts that declaration without requiring or
executing the builder. It rejects dynamic/ambiguous routes and duplicates,
includes source lines and preserves page-family/redirect details. Seven
regressions pass, including the real 16-route content baseline, independent
share/redirect paths, unrelated dynamic asset writes and non-execution of
source. The initial test used the wrong baseline JSON key; that failure is
retained with its passing correction.

The scope export now contains **337 platform/entrypoint rows**. Static paths
and the nine Flutter public paths remain separate. This still is discovery,
not complete role/state/dependency or acceptance coverage.

## Published inspection and local repair — FQA-029

All 21 source-derived entry cases returned HTTP 200 after redirects, using
synthetic values for the two wildcard patterns. The served version metadata
reported `250ebf9c9575fe407be3c4108669059cb40f3401`, generated on
7 September 2026, with a clean source tree at build time. The served
`revolut.css` exactly matched the local pre-edit stylesheet. This does not
prove that every deployed artifact matches the current application source.

The original live gate passed **35/35** checks, including the 16 governed
visible-content hashes. Browser inspection then measured all 19 concrete
requested paths at 320, 390, 834 and 1440 px: **76 observations**. Some entry
paths redirect to the same rendered page; these are not 76 distinct pages.

At 320 px, the Home heading extended to x=308.44 while the document's usable
width was 305 px and the heading box ended at 285 px. The Community Groups
heading also exceeded its content box. Ancestor clipping kept document
scroll width unchanged, so the old overflow assertion missed both cases.

The selected public Revolut UK homepage was inspected at 320 px. It uses
48 px Aeonik Pro for its shorter heading. Collect retains its own longer
copy. Its shared hero token now scales from 44 to 48 px only below 360 px;
this is an explicit adaptation to fit that copy, not a claim that Revolut's
measured token is 44 px. The existing rendered route runner now checks actual
heading text bounds as well as document width.

A loopback preview used published HTML with only the reviewed local
stylesheet substituted. It reproduced both failures with the pre-edit CSS
across 19 requested paths. After the repair, **95 geometry cases pass**:
19 requested paths at 320, 360, 390, 834 and 1440 px. The implementing agent
visually inspected the original clipped heading, source reference and repaired
heading. No production CSS was changed.

The full static build remains blocked by stale native app screenshot
provenance. This isolated CSS preview neither invokes nor bypasses that build
gate, and does not establish current app-media fidelity or full build acceptance.

## Broken privacy destinations — FQA-030 remains open

The Privacy page links to `/subprocessors/`, `/privacy-request/` and
`/cookies/`; Terms also links to `/cookies/`. These **four links point to
three HTTP 404 destinations**. The existing gate checked their markup and
expected the removed pages to be absent, but did not check usable navigation.

A new internal-link check now resolves same-origin targets and HTML fragments,
reuses fetched responses and avoids external action links. Seven regressions
pass, covering missing pages/fragments, URL/entity handling, caching and inert
markup. The revised live gate reports **35/36 checks passing** and fails the
new check: **217 source/link pairs, 19 distinct destinations, four failures**.
The earlier passing result is retained as evidence of the former coverage gap.

No replacement legal notice, subprocessor list or request-handling workflow
has been invented. The currently published policy and the earlier removal of
the extra pages need a coherent product/content resolution. An attempted
privacy-request browser click retained the policy page in this browser; the
saved screenshot is click-state evidence, not a rendered 404 page. The HTTP
404 observations are independently recorded.

## Interaction evidence and limits

Menu opening, focus containment, forward/backward wrap, Escape dismissal and
focus restoration pass **48 cases** across the 16 primary/alias routes at
320, 390 and 834 px. These are browser keyboard checks, not screen-reader
task completion or installed PWA/device evidence.

The initial menu measurement used an unexposed DOM property and applied
viewport overrides to another tab. It is retained as invalid measurement
evidence. The rerun uses reflected attributes, one active tab and actual
viewport readback. All recorded viewport counts were separately verified.

The final combined tooling run passes **51 QA-tooling tests/232 assertions**,
**49 mobile-gate tests/265 assertions** and **three catalog-generator tests**.
JavaScript and shell syntax checks pass. The prior 769-test Flutter checkpoint
remains separately bound to its recorded source; this website work changes
CSS and QA tooling, not Flutter application behavior.

Raw evidence is under `.cache/fullstack-qa/20260914T151002Z/` in
`public-static-scope/`, `public-live-discovery/` and `public-browser/`.
The browser manifest binds source and artifact hashes. The preview server was
stopped and the viewport reset. An unmarked temporary error tab could not be
accessed under the browser's data-URL policy and was left for automatic cleanup.

Disk space again reached ENOSPC while saving metadata. Only Git-ignored,
inactive Flutter test asset copies and compiled test caches were removed,
freeing approximately 101 MiB. Source, goldens, coverage and raw QA evidence
were preserved. Available space remained approximately 216 MiB after that
cleanup, far below native build capacity. Docker inspection and task-container
cleanup remain separately recorded and unconfirmed.

Next: resolve the three missing privacy destinations, finish remaining public
interaction/accessibility cases, obtain current native app captures and rerun
the complete static/rendered gates on a build bound to current source. No
deployment, external message, provider action or approval occurred.
