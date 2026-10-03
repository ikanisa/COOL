# Ruby delivery dependency repair

Fastlane is pinned to 2.240.1 and rubyzip to 3.4.0. Bundler 2.7.2 resolved the real dependency graph under Ruby 3.3.12; all 102 exact downloaded gem archives match the emitted checksum section of the new lock. The source pair is published in the checkout. Public HTTPS metadata and byte digests establish this registry comparison, without an independent publisher signature or license authorization.

The third Linux ARM64 attempt completed eight current runtime checks: frozen bundle admission, real Fastlane version/lane parsing and delivery action configuration loading, three actual ZIP extraction cases, and 25 offline iOS delivery contracts. Its network was disabled and the source fixture omitted private credentials. The prior rubyzip 2.4.1 V3 compatibility extraction API allows both hostile sibling-directory writes; the current API blocks them and admits the benign file. The separate legacy default API was not demonstrated vulnerable.

The two failed attempts are preserved. The first lacked Node for the fixture validator. The second sent the current API signature to the old legacy API and raised TypeError before any prior vulnerability reproduction. The third used the real old V3 compatibility API and returned the expected failed security comparison. The parent receipt was completed after correcting a case-sensitive cleanup-output assertion; the passed checks were not repeated.

The separate credential-free CI job now admits the frozen bundle, actual ZIP cases and Fastlane lane parse. This packet proves local source and dependency mechanics. Hosted CI, macOS signing/store delivery, new transitive advisory triage and final packaged dependency reconciliation remain unverified. ARC09 stays open.

Machine results, current source bindings, public metadata and every recorded attempt are in batch.json. No provider or signing action occurred.
