# ARC-06 iOS delivery implementation

The local delivery gap is corrected. ARC-06 remains open: no real signed IPA,
Apple/device/privacy acceptance or enforced hosted delivery run was produced.
GitHub's live read-only environment listing returned `total_count: 0` on
2026-10-01. No environments or reviewer policies were created or changed.

## Result

The workflow accepts exactly one operation: credential-free unsigned compilation,
signed candidate creation, internal TestFlight, metadata, screenshots or public
privacy answers. Signing and distribution require different dispatches. Public
binary submission is unavailable through these lanes. Metadata lanes neither
submit for review nor enable automatic public release. Privacy publication is
explicitly named because it changes public answers.

Every effect requires the reviewed main dispatch SHA, the canonical source-file
manifest SHA-256 and a separate, scoped approval record. The record is supplied
as exact UTF-8 workflow input outside the source checkout. Committing a new IPA
approval therefore does not change the approved source commit. The record hash
must match those exact bytes; whitespace is significant.

The workflow exports source to a private pristine candidate and runs from a
separate working copy. It rejects non-atomic checkpoints, changed/missing/unlisted
candidate files, changed/additional working source, wrong targets, stale records,
wrong scope and incomplete artifact binding. Rechecks after resolution preserve
lock enforcement. Known generated/cache/private paths remain excluded according
to the canonical export policy; those exclusions do not certify provider inputs
or package-cache integrity. Signing binds the public Supabase anon key hash and
fixed Supabase/public URL target separately.

Before scheduling the effect job and before Apple secrets, the guard reads back
GitHub environment and branch policy. Each relevant environment must have a
required reviewer, prevent self-review, explicitly disable admin bypass, and have
exactly the `main` branch policy. Missing/inaccessible/unsupported policy fields
fail closed. Direct iOS Fastlane lanes and signing import repeat the same checks.
GitHub API readback proves configuration at that instant; approval JSON does not
cryptographically prove a human identity or that an off-platform review occurred.

Signing imports only after source/configuration checks, validates distribution
profile target/expiry, uses a private keychain and restores its previous list.
Failure cleanup and the workflow's always-run cleanup remove owned certificate,
profile and keychain material. A partial cleanup failure is reported and retains
nonsecret reconciliation state rather than claiming successful cleanup.

The signed-candidate lane inspects the single IPA before saving it. Inspection
binds its SHA-256, bundle/version/build identity, Apple-anchored signing team and
distribution signer, production push/link entitlements, distribution-profile
identity/expiry and every embedded app/SDK privacy manifest. The Apple code
requirement syntax was compiled locally with `csreq`; Apple commands and
signatures in contract tests use synthetic transports. No actual IPA was signed.

A later internal TestFlight approval must name the exact IPA and inspection file
hashes. The workflow checks the originating successful main workflow run, then
repeats signature/identity/privacy inspection before upload. Fastlane checks the
IPA again immediately before and after upload. Hash change or uncertain Apple
failure requires reconciliation before another attempt; no retry is automated.

## Approval record interface

An externally reviewed record has `schema_version: 1`,
`kind: collect_ios_delivery_approval`, `decision: approved`, one exact `operation`,
the matching `environment`, a nonempty `reviewer` and `review_record`, UTC
`approved_at_utc` and `expires_at_utc` (current and at most seven days apart),
`source_commit`, `source_manifest_sha256`, `version`, `build_number`, and this
exact target object:

```json
{"bundle_id":"app.cool.mobile","apple_id":"6783960331","team_id":"63STJ5N27W","supabase_url":"https://lhbowpbcpwoiparwnwgt.supabase.co","public_url":"https://collect.ikanisa.com"}
```

For `signed_candidate`, `artifact` is null and `public_anon_key_sha256` names the
actual public build configuration. For `testflight_internal`, `artifact` holds
`ipa_sha256` and `inspection_sha256`. Metadata/screenshots and `privacy_public`
require their own operation/environment; another scope never substitutes for it.
No helper generates a human approval. Reviewers must use the actual reviewed
source and artifact; this interface description is not an approval record.

## Verification and remaining acceptance

The receipt binds the exact changed sources, canonical verifier dependency and
local tool versions. Offline tests cover denial before keychain/API/upload effects,
accepted synthetic source/signing/metadata/internal paths, profile/entitlement and
signer failures, cleanup on a partial import failure, source drift, manifest
completeness, stale/wrong scope/target, IPA/inspection drift and environment policy.
Five workflow caller tests check the source/credential/job/scope integration.
Ruby syntax, Python compilation and diff checks pass. Actual Fastlane lane
fixtures execute the real Python guards and synthetic GitHub transport; readiness,
Keychain, codesign and Apple upload actions are deliberately mocked.

Current committed screenshots contain only two PNGs, while the retained readiness
contract requires five of each device cohort. This is an observed local blocker;
no replacement artwork or design authority was introduced. The full readiness
gate, real unsigned/signed builds, physical device/APNs/link lifecycle, merged
privacy API-usage review, font/media rights, actual Apple processing/readback,
protected environments and artifact-bound human distribution decision remain
unverified or incomplete. The parent owns final candidate integration and the
existing affected Dart security-hygiene consumer.

## Primary technical references

GitHub documents environment reviewer/branch/bypass controls and delayed secret
access; the runtime guard additionally checks the current API response.
[GitHub environments](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments),
[environment REST API](https://docs.github.com/en/rest/deployments/environments),
[branch-policy REST API](https://docs.github.com/en/rest/deployments/branch-policies).
The guard refuses an absent `can_admins_bypass` field rather than treating it as
false; GitHub's integration provider reads that returned field in its environment
implementation.
[GitHub integration provider](https://github.com/integrations/terraform-provider-github/blob/main/github/resource_github_repository_environment.go).

Workflow expressions use contexts only where supported. Artifact retrieval uses
the documented GitHub CLI interface.
[GitHub contexts](https://docs.github.com/en/actions/reference/workflows-and-actions/contexts),
[artifact download](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/download-workflow-artifacts?tool=webui).

Fastlane documents internal/external TestFlight controls and the separate public
release behavior of Deliver. Apple's technical note explains why a signature
verification needs an explicit signer requirement. These sources support the
local command/control design, not actual Apple release acceptance.
[Fastlane Pilot](https://docs.fastlane.tools/actions/pilot/),
[Fastlane Deliver](https://docs.fastlane.tools/actions/deliver/),
[Apple code requirements](https://developer.apple.com/library/archive/technotes/tn2206/_index.html).
