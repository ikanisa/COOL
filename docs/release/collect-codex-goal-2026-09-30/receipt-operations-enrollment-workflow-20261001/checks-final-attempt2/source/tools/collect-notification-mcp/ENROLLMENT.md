# Receipt operations enrollment and local profile preparation

This separate CLI prepares the scoped receipt-operations identity. It does not
install/start launchd, change operating policy, widen the existing five-read MCP
profile, send SMS, or store an operator credential in the unattended profile.
The v3 owner RPCs require migration `20261001180000`; every owner call uses the
normal current, verified `info@ikanisa.com` session and backend permissions.
The CLI refuses automatic session refresh. Restore the normal operator session
through the existing login workflow if necessary; no OTP is sent by this CLI.

Run with the installed pinned Node from this directory:

```text
node --experimental-strip-types src/unattended_enroll_cli.ts <command> <options>
```

Compile `src/unattended_keychain.swift` into an explicitly selected, owner-controlled
executable in a private directory. Inspect/hash that executable and supply the
exact SHA-256. Do not replace an existing reviewed helper implicitly. Its
`self-test` reads no Keychain item and proves no physical hardware enrollment.
Evidence/journal and profile parent directories must already be owner-private
0700, with no symlink ancestors. Published JSON is canonical, exclusive 0600,
fsynced and read back. Never overwrite a profile to change identity.

Commands (all IDs are explicit lowercase UUIDs chosen for this operation):

```text
create-key --directory /private/evidence --helper /private/helper --helper-sha SHA256 --request-id UUID [--key-tag-id UUID]
read-key --helper /private/helper --helper-sha SHA256 [--key-tag-id UUID]
prepare --directory /private/evidence --helper /private/helper --helper-sha SHA256 --profile /private/profile.json --expires-at ISO-Z --workflow-id UUID --enroll-id UUID --proof-id UUID --activate-id UUID [--key-tag-id UUID]
resume --directory /private/evidence --workflow-id UUID
reconcile --directory /private/evidence --workflow-id UUID --request-id ORIGINAL_UUID --lookup-id DISTINCT_UUID
verify --profile /private/profile.json
list --limit 25 [--before-created-at ISO-Z --before-principal-id UUID]
revoke --directory /private/evidence --profile /private/profile.json --request-id UUID --reason-source stdin
lookup --directory /private/evidence --request-id ORIGINAL_OWNER_UUID --lookup-id DISTINCT_UUID
status --directory /private/evidence --request-id ORIGINAL_OWNER_UUID
```

`prepare` uses an existing selected hardware key and supplied immutable request
IDs: enroll → signed `prove_key` → activate → current identity read → profile
publication → current validation. Identity expiry must initially be 10 minutes
to 30 days away. Every owner mutation gets its own retained 90-second deadline;
the server enforces its original deadline after locks and after delegation.
The helper has separate project-bound tags; omitted `key-tag-id` preserves the
existing default. An explicit tag creates a new key and never replaces/deletes
the old one. Fingerprints must match public SPKI, server identity, local helper,
signed proof and profile; selecting another tag has no default-key fallback.

A transport failure, malformed success, lost callback or persistence failure
retains uncertainty. `resume` can progress from recorded stages but never repeats
an existing mutation. Use manual lookup with a distinct UUID. `in_progress`, an
unavailable/stale lookup, and `not_recorded` before the original deadline remain
unknown. Only a fresh absent observation after the retained v3 deadline can close
local evidence; it never authorizes replay of the original. `status` reads local
historical owner evidence without credentials or network. Retained files have no
automatic eviction or deletion.

For compromise recovery, first submit `revoke` with the original profile and a
reason through private stdin (8–500 characters; do not put it in shell arguments).
The local journal stores its digest, not free-form reason text. Revocation never
executes the signing helper and works for expired pending/active identities. If
uncertain, look up that original UUID before claiming revocation. The old profile
then fails current validation. Create a fresh explicit tag/key and prepare a new
profile with fresh enrollment/proof/activation IDs, preserving the old records
and keys. There is no automatic policy migration, enrollment, key deletion or job
restart. Actual Secure Enclave key creation and the owner-authorized hosted
enrollment/revocation/rotation drill remain physical/live acceptance work.

`PROFILE_PREPARED`/`PROFILE_VERIFIED` binds a fresh active identity, expiry, local
selected key, helper bytes and exact profile readback. It is not policy-mode,
allowlist/quota, scheduler, hosted deployment, sending or carrier acceptance.
Real backend authority is checked again for every operational request. The current
installed default MCP profile remains the exact five read tools.
