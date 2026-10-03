# ARC-09 public advisory triage — 2026-10-01

This completed, dated pre-remediation survey found actionable dependencies in
the decoder and release toolchain. It records the exact graph queried around
21:19–21:26 UTC on October 1. Subsequent source repairs belong to their own
evidence packets; corrected versions have not been substituted into this
historical proof. A follow-up must bind the final inventory and query any new
versions or packages before final candidate advisory acceptance.

| Source dependency | Initial finding | Required reviewed remediation |
| --- | --- | --- |
| pypdf 6.7.0 | 42 distinct GHSA advisories; malformed PDF parsing, text/font handling and other APIs can consume unbounded resources. All exact queried versions are listed in the affected records. | Authenticate and pin at least 6.19.0, then exercise relevant hostile PDF mechanisms and actual decoder regressions. The earlier 6.18.1 patch alone leaves three 6.19.0 advisories open. |
| Pillow 12.0.0 | 19 distinct GHSA advisories; native memory corruption, decompression/resource exhaustion and platform-specific paths. Actual application exposure differs by operation. | Authenticate and pin at least 12.3.0 for the required Linux aarch64/Python 3.12 wheel, then exercise decode/render and resource-bound consumers. |
| Kotlin Gradle plugin 2.3.20 and local file_saver 2.1.0 | GHSA-r937-wjx7-w2jp / CVE-2026-53914: build-cache metadata deserialization. Both exact versions appear in the advisory. | Authenticate and validate stable 2.4.20 and both build consumers. Cache trust and actual native build evidence remain relevant; an empty runtime classpath query does not clear build tools. |
| rubyzip 2.4.1 | GHSA-47m2-wp7j-p9vc / CVE-2026-85396: ZIP extraction can escape to a sibling directory sharing the destination prefix. | Resolve a compatible release-tool graph with rubyzip at least 3.4.0. Official fastlane 2.240.1 requires this fixed range; existing fastlane 2.237.0 requires rubyzip below 3.0. Test the unsigned delivery consumers and frozen bundle, without manual lock substitution. |

The public Deno std 0.224.0 repository-tag query also returned
CVE-2025-55195 / GHSA-crjp-8r9q-2j9r. Its publisher describes `@std/toml`
prototype pollution in Node/browser. The retained Collect Edge import/lock
graph uses std assertion/format/internal modules, with six direct imports
confined to tests and no std TOML module. The publisher explicitly excludes
the affected mechanism on Deno. This is a conditional repository-tag hit,
not evidence of exploitable TOML code in the selected Collect module graph.

The initial maintained inventory contains 598 dependency occurrences across
13 ecosystems. Every occurrence is recorded in `query-mapping.json`;
587 map to 542 unique public exact-version queries. Eleven are explicitly
unmapped: eight Flutter SDK placeholder versions, the Flutter SDK Gradle
loader, the local Flutter CocoaPods stub, and the OCI image declaration.
Eleven initial OSV batch responses succeeded, as did all 124 distinct advisory
record fetches. There are 125 version/advisory pairs because one Kotlin record
affects two locked versions; aliases are retained, not counted as additional
vulnerabilities. Sixty-three distinct GHSA issues concern matched packages,
plus the conditional std repository record. None of these initial records is
labelled Critical by its captured database representation.

`preliminary-inventory.json` preserves the full source-hash manifest used to
derive these package queries. The completion readback observed four later
changes: `supabase/functions/_shared/roster_decoder.ts`,
`tools/roster-decoder/decoder.py`, `requirements.in` and `requirements.lock`.
The initial pypdf/Pillow findings remain pre-repair findings. This inventory
does not capture CI workflow files: ongoing CI and consumer changes cannot be
certified by this advisory packet or silently treated as the baseline tested
candidate. See `batch.json` for the dated drift/coverage boundaries and
`raw-response-manifest.json` for response-byte hash verification.

`version-findings.json` retains exact affected identities, version-list
membership, fixed ranges, severity vectors, publication/modification fields,
references and source-occurrence indices. Every initial match also lists the
exact queried version. This corroborates OSV's response despite its documented
fuzzy-version lookup behavior. Local Dart forks use their recorded public
upstream version as a proxy; their reviewed deltas require separate evidence.
The esm.sh mappings identify the encoded npm package/version and do not
independently authenticate transformed CDN modules.

GitHub's reviewed `affects=package@version` API corroborates the actionable
records. Case handling matters: `Pillow@12.0.0` returned five records and
`pillow@12.0.0` returned fourteen disjoint records, whose union matches OSV's
nineteen. Both spellings were queried for the fixed target. Exact pypdf
6.19.0, Pillow/pillow 12.3.0, rubyzip 3.4.0, fastlane 2.240.1 and Kotlin
2.4.20 currently have no returned OSV records; targeted GitHub checks for the
two decoder fixes likewise returned none. These are dated database results,
not a guarantee against unknown defects or a final candidate acceptance.

One captured representation disagrees with the publisher UI. For
GHSA-fp3h-c4fm-7vvf, OSV records HIGH, publication 2026-10-01 and a CVSS v4
vector; the publisher page displays Moderate and publication September 11.
The three pypdf 6.19.0 publisher pages similarly display Moderate and
September 16 while their OSV records show HIGH and October 1. Both sources
agree on affected/fixed versions. Preserve both dated representations rather
than treating ingestion timestamps or database severity as the publisher's
own date/rating. Raw primary publisher HTML and API bytes are retained.

All network requests used public package identities/versions or public
advisory/release IDs over certificate-verified HTTPS without credentials.
No repository contents, private data, tokens or source hashes were sent.
`*.metadata.json` binds each exact request URL, retrieval time, status,
public response bytes and SHA-256. Public PyPI metadata for the six decoder
dependencies and exact fix candidates, RubyGems metadata and Kotlin release
metadata provide registry-origin evidence. A TLS origin plus registry digest
is distinct from independently verified publisher attestation.

An empty result cannot establish complete vulnerability coverage. The selected
source inventory does not describe the shipped AAB/IPA/web bundle, full native
build-plugin graph, installed decoder base-image OS packages or native
libraries bundled inside wheels/binary Swift packages. Actual Flutter/Dart,
JDK, Gradle distributions, Ruby, Python, Deno, Supabase CLI and GitHub Actions
toolchain advisories also need their separately bound versions. Container
platform/SBOM inspection, native binary composition, current full graph
license/provenance review, exploitability/mitigation validation and authentic
release approval remain separate requirements. No packages were changed by
this report, and it grants no production or release clearance.

Primary references:

- [OSV exact-package API and version rules](https://google.github.io/osv.dev/post-v1-query/)
- [OSV batching and per-query pagination](https://google.github.io/osv.dev/post-v1-querybatch/)
- [OSV ecosystem/affected-version schema](https://ossf.github.io/osv-schema/)
- [GitHub reviewed public advisory API](https://docs.github.com/en/rest/security-advisories/global-advisories?apiVersion=2022-11-28)
- [pypdf 6.19.0 appearance-stream advisory](https://github.com/py-pdf/pypdf/security/advisories/GHSA-php9-fj8v-98fj)
- [pypdf 6.19.0 embedded-file advisory](https://github.com/py-pdf/pypdf/security/advisories/GHSA-v247-6f48-mgcj)
- [pypdf 6.19.0 page-label advisory](https://github.com/py-pdf/pypdf/security/advisories/GHSA-w23x-9jrw-r45c)
- [Pillow coordinate overflow advisory](https://github.com/python-pillow/Pillow/security/advisories/GHSA-6r8x-57c9-28j4)
- [Kotlin cache advisory](https://github.com/advisories/GHSA-r937-wjx7-w2jp)
- [rubyzip extraction advisory](https://github.com/advisories/GHSA-47m2-wp7j-p9vc)
- [Conditional std TOML advisory](https://github.com/denoland/std/security/advisories/GHSA-crjp-8r9q-2j9r)
