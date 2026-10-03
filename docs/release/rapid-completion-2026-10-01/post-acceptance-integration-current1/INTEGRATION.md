# Collect integrated local acceptance

**Status: complete for this integration pass. Production release: NO-GO.**

The current captured source has 2,175 selected files and 187 migrations. The earlier immutable 24-item local acceptance remains intact. This packet adds matching-source evidence for the subsequent Admin/MCP/SQL changes; independent work in other chats remains governed by its own register.

## Corrections integrated

| Correction | Why it was required | Result |
| --- | --- | --- |
| Scheduler admission after awaited setup | A tick admitted earlier could resume after durable disable or identity expiry and still invoke the runner. | Permission and identity are rechecked immediately before invocation; non-invoked outcomes are recorded. Current 66 scheduler cases plus 347 unchanged cases compose 413 MCP cases; type checking and 12 Python preparation cases pass. |
| Recovery input bounds before encoding and parsing | An oversized sessionStorage value could allocate UTF8 and decode JSON before resource limits rejected it. | Code-unit admission precedes encoding, byte admission precedes JSON decoding, and bounded quarantine survives reload. Both ASCII and multibyte regression cases pass within the 657-case combined run. |
| Current joined audit reader | The earlier UNION plan read excessive equal-time records before applying its outer limit. | Each source arm now applies its authorization-compatible bounds, paired cursor and limit before UNION. The 37 query-plan checks and 21 ordinary-owner new/retained-body checks pass. |

The other chat's route-origin and opening-generation guards were preserved. Exact acknowledgements, session changes and authority refusal remain covered by the actual 19-suite, 657-case run. Strict analysis and sole-design-authority hygiene pass. Hygiene does not certify visual fidelity.

## Verified scope

- Admin: 657 actual VM cases across 19 suites, with 135 new history/inbox cases. One production Admin build and 89 actual browser/PWA checks passed.
- Browser fixtures are synthetic loopback data. The actual SQL decoder/SDK and widget proofs establish the new positive v2 contracts; no claim is made that every positive v2 state was exercised in the browser.
- SQL: the preceding 187 clean plus 187 populated ordinary-installer applications and 36 checks retain their earlier a835 reader-body provenance. The 186 migration files are unchanged. The changed 7f6aea reader is separately covered by 37 plan checks and 21 ordinary-owner checks. Overlapping database cases are not summed as unique coverage.
- MCP: 413 unique composed cases, including 66 corrected scheduler cases and 347 unchanged cases, plus 12 preparation cases. Real launchd, Keychain and provider operations were not invoked.
- Unsigned Android/Gateway/iOS and Edge results are reused only where exact consumer, dependency/toolchain and artifact readback maps match. Broad native, Edge and full Flutter reruns were avoided.
- Current source readback, locks, input maps, terminal logs and artifact maps are bound by [integration-acceptance.json](integration-acceptance.json). Rejected/stalled runs and their causal fixture corrections remain preserved.

The first final browser-build attempt stopped at a pinned Flutter/font-subset pipe deadlock before browser launch. The corrected command uses a private output-draining wrapper around the identical engine binary, with original arguments, standard input, font outputs and exit status preserved. Its bounded log and complete output digest, failed attempt and actual final artifact are recorded separately. Application source and the shared SDK were unchanged; one successful final build is claimed.

The corrected Admin and Public builds passed. Its browser driver then timed out while typing after a repeated sign-in: DOM focus preceded the Flutter editor's input readiness. The private continuation brings the page forward, clicks the current named field and waits two frames while retaining the exact native-editor value assertion. Both accepted bundles are reused under hash guards; no third Admin or Public build is performed. This harness correction and the failed captures are preserved separately from application source.

## Source delivery

Use the earlier [accepted source archive](../final-candidate-current1/collect-accepted-local-source.tar.gz) together with [the integrated source overlay](collect-integrated-source-overlay.tar.gz). Their SHA256 values and every overlay member are verified in [source-overlay-readback.json](source-overlay-readback.json). The overlay carries 58 added and 16 changed selected-source files; no selected-source deletion occurred. The declared source and reproduction-only files are distinguishable in [source-overlay-manifest.json](source-overlay-manifest.json). SDKs, caches, secrets and signing material are excluded.

The portable build/evidence delivery is recorded in [delivery-readback.json](delivery-readback.json). Prior archives remain intact. Original 24 local criteria and 102 production criteria are preserved in [register-integrity.json](register-integrity.json); 101 production checks remain open.

## Remaining release acceptance

The owner of **Connect Collect to Codex MCP** reported six additional local requirements against 11 source files that match this capture. Three owners are preparing the corrections privately. These findings were not independently reproduced by this chat; their guarantees are excluded from reused native/MCP/SQL tests and this frozen integration pass. They remain open in that chat's register. The [read-only findings receipt](known-open-parallel-review/findings.json) is preserved here.

| Open local requirement | Why it remains necessary |
| --- | --- |
| Continuous heartbeat ACK retention | Legacy 256-request/512KiB archives bound lifetime sender availability. |
| Permanent global native request-ID reservation | A compacted request's identity must remain reserved across a changed action or attempt. |
| Expandable native indexes and complete recovery | Finite per-prefix and late-observation caps need bounded expansion and a complete recovery closure. |
| Scheduler hot/cold maintenance and inactive restore | Existing admission limits fail closed; continuous operation also needs lossless maintenance and read-through. |
| Indexed worker source sweep | Limiting output after lifetime duplicate/deferral aggregation does not bound the underlying scan. |
| Worker cold-history preservation and restore | Maintenance must retain original IDs, acknowledgements and foreign-key provenance. |

Hosted/Auth/provider behavior, physical devices, signing/store release, trusted-source governance, visual comparators and owner release acceptance retain their existing gates. No deployment or production approval is inferred from this local packet.
