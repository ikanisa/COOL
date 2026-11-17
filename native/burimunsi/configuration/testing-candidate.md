# Testing-candidate compilation

This explicit phase serves the owner's current six-task MVP. It permits compiling
configured Release APKs before signing and the physical-phone pilot that consume
those APKs. It grants no signing, distribution, financial-operation or production
promotion authority. Legacy `build` and `promotion` checks are unchanged.

Create a physical evidence bundle outside `native/burimunsi` and
`upstream/collect`, on the build-evidence volume. It may contain retained copies,
or sit at a common parent of existing build/device directories. References are
relative to the candidate manifest, cannot traverse parents or symlinks, and bind
each file's SHA-256. Do not put credentials or evidence inside the source tree.

The exact manifest keys are:

```json
{
  "format": "collect.burimunsi.testing-candidate.v1",
  "purpose": "testing-candidate-build",
  "created_at": "<current UTC timestamp>",
  "source_sha256": "<current native_pipeline source fingerprint>",
  "profile_sha256": "<SHA256 of canonical public deployment profile>",
  "properties": {},
  "qualification": {
    "build_result": {"path": "build/build-result.json", "sha256": "<digest>"},
    "source_fingerprint": {"path": "build/source-fingerprint.json", "sha256": "<digest>"},
    "artifacts": {"path": "build/artifacts.json", "sha256": "<digest>"},
    "instrumentation_result": {"path": "device/instrumentation-result.json", "sha256": "<digest>"},
    "device_inspections": [],
    "instrumentation_logs": {
      "staff": {"path": "device/staff-instrumentation.txt", "sha256": "<digest>"},
      "internal_receiver": {"path": "device/internal_receiver-instrumentation.txt", "sha256": "<digest>"}
    }
  }
}
```

Fill `properties` with exactly `collectSupabaseOrigin`, `collectAdminOrigin`,
`burimunsiApiOrigin`, `burimunsiApiPathPrefix`, `collectGatewayOrigin`,
`collectPublishableKey`.
Values are strings and must equal the actual Gradle-selected values. Only a
bounded `sb_publishable_` opaque public key is accepted; secret keys, JWTs and JWKs
are refused. Never insert group/account/phone/SIM/custodian identifiers.

The separate profile file is the canonical `collect.deployment.v1`
managed-cloud public profile: format, id, mode, environment, supabase_origin,
member_api_origin, admin_origin, public_origin, google_callback_origin. Native
API and receiver must use that Supabase origin; Admin must use its Admin origin.
The receipt profile must be an approved nonblank identity and offset, not an
invented carrier acceptance claim.

`device_inspections` holds four hashed references to the actual `inspection.json`
files for both nativeTest apps and both test APKs. The gate checks all eight build
APK hashes, source fingerprint, exact current test inventory, four corresponding
device inspections, cleanup, and reparses the two raw instrumentation streams.
Manifest, build and device timestamps must be UTC and no older than 24 hours.
These checks bind local bytes; they do not authenticate human attestations or
claim live GoTrue, TLS, SMS, carrier, financial, signing or store acceptance.

After fresh qualification of the current source, select the phase explicitly:

```text
-PburimunsiReleasePhase=testing-candidate
-PburimunsiReleaseEvidence=/physical/evidence/candidate.json
-PburimunsiReleaseProfile=/physical/evidence/deployment-profile.json
-PnativeReleaseQualified=true
```

Keep the public installation properties from `installation.example.properties`.
Gradle supplies its actual selected fields to the check through
`BURI_BUILD_PUBLIC_PROPERTIES`; do not construct that environment value to mask
different compiler properties. The gate's successful output always has
`production_authorized`, `signing_authorized` and `distribution_authorized` false.
`verifyProductionPromotion` continues to call the unchanged promotion phase.
