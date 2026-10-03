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

## Full-checkout source inventory

`scripts/hardening/source_inventory.py` inventories tracked paths and approved file hashes without deleting anything. It does not prove asset non-use, dependency reachability, absence of private keys, or software supply-chain safety. Preserve lockfiles, verify licenses independently, and perform secret scanning with the existing release scanner plus a trusted independent scan. Do not bundle font files or credentials into collaboration archives.
