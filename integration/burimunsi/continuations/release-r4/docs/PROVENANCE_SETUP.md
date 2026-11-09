# Producer provenance: protected integration guide

## Trust boundary

r4 verifies Ed25519 signatures made by keys explicitly allowed in a separately pinned trust policy. It does not independently identify the people controlling those keys, prove that tests truly ran, issue independent security certification, or authorize production. Identity onboarding, truthful qualification producers, protected CI code/environments, key custody, clock integrity, immutable evidence storage and real owner decisions are external responsibilities.

Run a separately protected, reviewed validator. An attacker who can replace the executing validator, environment pin or trust policy can replace the policy itself. A policy stored outside the source tree is not protected solely by its location. Do not let pull requests or candidate scripts set `RELEASE_TRUST_POLICY`, `RELEASE_TRUST_SHA256`, modify the clock, replace OpenSSL or write the trusted workspace.

## Policy structure

Supply a UTF-8 JSON file with exactly these top-level fields:

`schema_version` (integer 1), `kind` (`release-trust-policy`), `product`, `phase`, `issued_at`, `expires_at`, `keys`, `roles`.

The policy is scoped to exactly one product and phase. Its issue/expiry timestamps must bracket the validation time, with a maximum 30-day validity period. Publish its exact-byte SHA-256 through your protected configuration. Formatting changes alter the pin and require renewed statements.

Each key has exactly: `id`, `producer_id`, `public_key_hex`, `status`, `not_before`, `not_after`. `public_key_hex` is a 32-byte Ed25519 public key in lowercase hex; `id` is SHA-256 of those 32 raw bytes. No private keys are accepted or required by this tool. `status` is `active` or `revoked`; a revoked key cannot contribute even if its signature predates revocation. Keys must be valid at both statement time and validation time. The sample policy under `examples/` is intentionally empty/expired and cannot pass.

`roles` has exactly `manifest` plus `qualification:<id>` for every qualification required by the immutable product/phase policy in `docs/required-policies.json`. Every role contains `key_ids` (nonempty unique configured IDs) and `threshold` (positive integer). A threshold counts distinct `producer_id` identities, not multiple keys held by one producer. Duplicate public keys or IDs are rejected. Rotation is supported by overlapping valid keys, subject to distinct-producer counting and a fresh pinned policy.

Security acceptance/dependencies and operations authorization require producer identities that are not reused for any other role. This prevents a builder key or another key assigned to the same configured producer identity from satisfying those independent roles. Trust-policy maintainers remain responsible for mapping those IDs to genuinely separate accountable identities. No auto-enrollment or trust-on-first-use occurs.

## Produce and review real evidence first

Freeze the consolidated candidate and protected verifier version. Execute actual required qualifications and dependency resolution; record exact source, artifact and log hashes. Build the schema-1 manifest with current 4.0.0 policy digest. r2/r3 evidence does not satisfy r4 merely by having its dates changed. The `validate_consistency` diagnostic can reject malformed evidence but cannot approve release.

The manifest must already include every required qualification. Every signer's statement binds the full canonical manifest digest, its own qualification-result digest (or the manifest for the manifest role), product, exact version, phase, run ID, immutable policy digest, external trust pin, key ID, role and signed timestamp. The signature therefore cannot be moved to a different role, candidate, run or pinned policy.

## Export unsigned requests

From the toolkit source directory, define real paths in a protected operator environment:

```sh
SOURCE=/work/reviewed-candidate
EVIDENCE=/work/qualification-run
TRUST=/protected/release-policy.json
TRUST_HASH=INDEPENDENTLY_APPROVED_POLICY_SHA256
ROLE=manifest
KEY_ID=APPROVED_PUBLIC_KEY_FINGERPRINT
REQUEST=/work/new-manifest-request
python3 -B src/provenance_exchange.py prepare \
  --source "$SOURCE" --evidence-root "$EVIDENCE" \
  --manifest "$EVIDENCE/release-manifest.json" \
  --trust-policy "$TRUST" --trust-sha256 "$TRUST_HASH" \
  --role "$ROLE" --key-id "$KEY_ID" --output "$REQUEST"
```

Repeat for each required role and each distinct producer needed by its threshold. Outputs contain `statement.bin` and `request.json`. This command is **unsigned preparation**, not acceptance. Output directories must be new and outside the candidate, evidence and trust inputs. The timestamp is the statement preparation time and is signed as part of the payload; it is not a trusted timestamp-authority record.

## Sign outside this package

The responsible producer independently verifies its evidence and the requested scope, using a trusted copy of the statement encoder to reconstruct and compare the exact bytes. It then signs `statement.bin` with its protected Ed25519 signing service. The output must be the raw 64-byte Ed25519 signature, not an ASCII/base64 wrapper. The production tools in this package neither generate private keys nor sign data.

The message starts with the binary domain separator `BuriMunsi-release-provenance-v1` followed by a null byte and the exact `release_guard.canonical` JSON representation. Use the generated binary bytes rather than recreating canonicalization in another language without conformance testing. Hashing the payload before ordinary Ed25519 signing would be a different protocol and is rejected. OpenSSL verification uses `pkeyutl -verify -rawin -pubin -keyform DER`; the official OpenSSL 3.0 reference documents the Ed25519 raw-input requirement: https://docs.openssl.org/3.0/man1/openssl-pkeyutl/ .

Tests generate ephemeral keys solely in temporary directories, sign synthetic fixtures and remove those directories. Those test identities/signatures are never production trust roots or a real independent acceptance result.

## Assemble returned signatures

Supply one repeated `--signed` pair per request directory and returned raw signature file:

```sh
python3 -B src/provenance_exchange.py assemble \
  --source "$SOURCE" --evidence-root "$EVIDENCE" \
  --manifest "$EVIDENCE/release-manifest.json" \
  --trust-policy "$TRUST" --trust-sha256 "$TRUST_HASH" \
  --signed /work/request-manifest /work/returned-manifest-signature.bin \
  --signed /work/request-local-regression /work/returned-local-signature.bin \
  --output "$EVIDENCE/provenance.json"
```

This two-pair illustration is deliberately incomplete for real application phases: supply all policy-required roles/thresholds. Missing signatures cause rejection and no output. Assembly verifies the exact requests, payloads, real signatures, validity and thresholds and rechecks evidence consistency before exclusive publication. Existing outputs cannot be overwritten. Assembly still returns `gate_open=false`; run the actual gate afterward. Do not reuse the output of a failed or interrupted exchange.

## Run protected application gates

For a diagnostic call to the public validator:

```sh
python3 -B src/release_guard.py validate \
  --source "$SOURCE" --evidence-root "$EVIDENCE" \
  --manifest "$EVIDENCE/release-manifest.json" \
  --product M-Money --version 0.2.10 --phase build \
  --trust-policy "$TRUST" --trust-sha256 "$TRUST_HASH" \
  --attestations "$EVIDENCE/provenance.json"
```

Use the exact expected product/version/phase from protected release configuration, not values suggested by untrusted evidence. For the integrated product entrypoints set `RELEASE_TRUST_POLICY` and `RELEASE_TRUST_SHA256` in protected CI configuration; the adapter reads `provenance.json` beside that phase's manifest. Run the combined product CLI to preserve its legacy acceptance and exact-artifact checks, not merely the shared gate. See `INTEGRATION.md`.

A successful result means the checked snapshot and configured producer signatures satisfied this policy at that validation time. It is not a deployment token. Keep the candidate/evidence immutable, rerun gates immediately before use and retain logs. There is no atomic transaction with an external deployment service. All responses retain `production_authorized=false`.

## Rejection, revocation and operational limits

Missing or wrong pins, in-tree/symlink policies, expired/revoked keys, stale/future/pre-subject signatures, duplicate/unknown roles, unauthorized key-role pairs, incomplete thresholds, altered evidence, unsupported crypto, missing OpenSSL, timeout/crash and detected concurrent changes all close the gate. Verification uses fixed executable search directories and a reduced subprocess environment, per-process timeout and overall crypto time budget. These assume the OS and installed executable are trusted.

Policy and signature files are reread after verification; source/evidence are checked again. These checks detect the covered mutations but do not replace immutable storage or eliminate all filesystem races. The library `now` parameter exists for deterministic tests; production CLIs expose no freshness override. Signer time is asserted by the producer, not independently timestamped.

Revocation is checked against the supplied pinned policy, **not an online service**. Updating revocation or rotation requires a new protected pin and new statements. A compromised signing service, dishonest authorized producer, fabricated external result, stolen key or compromised trust administrator remains outside the guarantee. No private key custody, real protected policy, trust distribution, online revocation, transparency log or hosted CI integration was deployed by this workstream.
