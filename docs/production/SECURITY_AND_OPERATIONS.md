# Security and operational control notes

## Trust boundaries

Member-authenticated traffic, native receipt storage, device attestation, parsed SMS, independent provider evidence, privileged database transitions, and human approval are distinct boundaries. Display labels are not identity. Device attestation is not settlement proof. Unknown queue totals are not zero. A successful provider HTTP call is not proof of a journal posting.

The new receipt-v2 contract fails closed on missing security versions. Persisted receipt identity is verified before a storage ACK. A stale owner cannot acknowledge another owner's native envelope. OTP verification binds signature, exact body, webhook ID and bounded timestamp; persistent reservations prevent automatic replay sends. Public errors use fixed codes. Provider HTTP calls have timeouts, response-size limits where integrated, and do not follow credential-bearing redirects.

## Operating signals to establish and test

Receipt oldest-age, local queue unavailable/overflow, durable-ACK failure, contract-version rejection, attestation rejection by non-sensitive category, unresolved OTP reservations and quota usage, unmatched receipt age, independent-review age, duplicate reference/reversal counts, notification retries/dead letters, database latency and restore drill success. Do not log body text, OTPs, phone numbers, signing keys or provider credential payloads. Current source does not constitute a provisioned telemetry backend or an on-call service.

Define alert thresholds and escalation ownership from observed pilot throughput. The receipt queue's current capacity is not an SLA. Test key-lock recovery without clearing ciphertext; require explicit evidence before destroying irrecoverable data. Establish documented support paths for devices offline beyond intent expiry and receipts rejected by a narrower sender filter.

## Independent evidence and privacy

Reconciliation source references must identify actual independently obtained records. Two distinct authenticated approvals improve separation of duties, but do not certify a forged statement. The protected service finalizer must not be offered as an unrestricted client action. Test current role removal, session expiry, stale approval and duplicated requests on the full backend.

The new tables store digests and identifiers, not OTP bodies. Define lawful retention and controlled maintenance for reservation/review/audit tables before launch. A digest of a phone number remains potentially linkable personal data; it is not guaranteed anonymity. The existing Flutter snapshot cache still needs a platform-appropriate encrypted/minimized implementation. Do not describe `store:false` in AI requests as a blanket zero-retention guarantee.

## Tracked source and release evidence

Run `python3 scripts/hardening/source_inventory.py --output /tmp/collect-source.json` to list tracked working-copy files outside `docs/release/`. Use `--scope release-evidence` for the files under that directory, including receipts used by current checks. Use `--scope checkout` for the full tracked inventory. Each report identifies the selected scope and the checkout's HEAD. The digests reflect the bytes present on disk, including local edits. Files named `.env*` or ending in `.jks`, `.keystore`, `.p12` or `.p8` receive a size and a private-review classification.

Dependency reachability, license review and secret scanning have dedicated checks. Preserve lockfiles and keep font files and credentials out of collaboration archives. [Release evidence and custody](../release-evidence.md)

## Cutover source identity

Run the v3 source inventory from the current repository after moving a
checkout to verify the managed archive operator's original inputs.

```sh
python3 scripts/qa/managed_archive_source_inputs.py "$original_git_store" \
  --node-modules "$original_dependencies" --show-inputs
```

The command reads the pinned Git revision and verifies the exact dependency and
runtime bytes. If a separately stored input has moved, pass
`--external-input ORIGINAL RECOVERED` with its original manifest path and its
physical recovered path. A missing or changed input returns an incomplete
result. Keep the manifest at its original digest and use the report to locate
the remaining inputs. [Source checker](../../scripts/qa/managed_archive_source_inputs.py)

Run `python3 scripts/supabase/cutover_gate.py source-identity` from the selected
checkout to capture the source digest used by the cutover evidence gate. It
binds React Admin source and package locks, shared contracts, the pinned
BuriMunsi receiver inputs, and the Edge and Supabase CLI version pins. A change
to those inputs requires matching cutover evidence and owner approval for the
new digest. [Cutover source gate](../../scripts/supabase/cutover_gate.py)
