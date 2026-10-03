# Hosted upgrade prerequisites

This is a planning inventory, not an executed hosted upgrade. The retained
read-only hosted registry has **124 migrations**, ending `20260906160000`.
Retained snapshot02 contains **157 migrations**, ending `20260930230300`.
`hosted-upgrade-inventory.json` lists all **33** pending SQL files, their exact
snapshot hashes and whether each belongs to the three-file subset rehearsal.
Later workspace files are recorded separately and have not silently become
part of snapshot02. Registry presence does not attest installed function bytes.

The combined rehearsal uses the retained **schema153** catalog capture plus
receipt backlog230100, Overview230200 and lifecycle230300. Group-share230000
is deliberately omitted from this subset; the full157 upgrade must include it
in version order. This is neither a clean installation nor a124-to157 upgrade.

| Pending source ordinals | Work to rehearse before hosted activation |
| --- | --- |
| 125–128 | Membership/roster boundary, atomic OTP quota, Rwanda-only configuration and relational history. Test old foreign/bank/profile rows and the new `NOT VALID` constraints without destroying retained evidence. |
| 129–133 | Replace SMS-as-finality with observation-only ingestion, bind a genuine provider confirmation before posting, exact intent matching and attested v2 ingestion. Test old raw/parsed/payment rows, duplicate references, unallocated/late allocation, already-posted/reversed records and old Android builds. No synthetic confirmation is provider-authenticity evidence. |
| 134–139 | Notification paging, payment lock ordering/content binding, fencing, eligibility and bounded retry schedule. Rehearse old open/expired claims, failed and uncertain attempts, lost acknowledgements, registrations and retry caps; never convert an unknown carrier handoff into a safe retry merely because a lease expired. |
| 140–146 | Governed reconciliation, Auth-bound device registration, roster provenance/reload/resource integrity and signed OTP recovery. Test stale grants, missing identities, invalid provenance and all old sessions. Legacy bank scheduler 143 must be retired through its actual governed procedure and read back; installing its functions alone does not prove retirement. |
| 147–150 | Governed runtime controls, redacted health and current authority. Rehearse lock order, permission/approval/session revocation, missing runtime configuration, safe aggregate output and denied API/private-table access. Match installed function bodies, RLS, grants and configuration after deployment. |
| 151–153 | Navigation preserving existing disabled rows, manual shadow lease/fencing, and runtime authority. A completed shadow record is sampled monitoring telemetry, not attested Codex execution or delivery. No unattended scheduling or principal is created. |
| 154 | Group-share rotation request receipts and current actor authority. Test legacy clients, request replay/collision, revoked membership/platform authority, concurrency and lock ordering against roster changes. This file is outside the combined subset. |
| 155–157 | Durable paused receipt capture/per-event human observations, Overview aggregates and transaction lifecycle. Preserve immutable primary receipt bytes, balances and journals; verify deliberate eligibility suppression and pending-policy historical catch-up refusal. Test independent permissions, mixed timestamps, malformed reads, retained historical rail/currency data and exact current source against the deployed version. |

The full rehearsal requires an independently captured or reconstructed,
authorized **schema124** baseline, a clean157 installation, and a nonempty
124-to157 upgrade in isolated PostgreSQL. Include historical members, retained
foreign/bank records, raw/parsed SMS, provider evidence, canonical journals,
balances, receipts/attempts/confirmations, roster imports, device tokens,
registration sessions, role/approval records and cron catalogs. Use synthetic
or expressly authorized redacted data; do not copy credentials, OTPs or
destination/body data from the shared or hosted service.

Freeze all migration, Edge, Android, Admin and MCP bytes together. Verify their
versioned contracts and actual migration order; exercise real GoTrue/PostgREST
and signed approved operator sessions separately. The present subset uses
synthetic claim settings and catalog ACLs in an isolated database. Its empty
cron catalog and excluded network/GraphQL/statistics extensions are not an
extension/Vault/cron integration test.

The hosted readback still reports five active cron jobs, including the legacy
daily bank-reconciliation job, and `hybrid_sms_notifications=false`. None is
proof of the requested unattended receipt runner. Keep dispatch paused through
restore rehearsal, historical policy review, deployment/body/ACL readback and
the approved live positive/negative operator checks. The durable event ACKs
currently record human `observed` progress; `deferred` remains pending and
neither constitutes durable unattended business handling.

Full activation also needs a provisioned least-privilege unattended principal,
credential/session lifecycle, gateway or approved provider decision, run-bound
authority/leases, event handling/deduplication, scheduler ownership, bounded
rate/budget/maintenance controls, physical gateway/device and live provider
evidence, kill-switch rehearsal, recovery/SLO/load tests, and approved rollout
and rollback. Those capabilities are not supplied by this read-only subset.

Source conflicts to keep visible: the initial230000 timestamp collision was
resolved by renaming only the backlog/Overview/lifecycle files to230100,
230200 and230300. The original group-share230000 remains. New investigation
and sensitive-authority migrations appeared after snapshot02 and require their
own source capture, compatibility review and rehearsal. Earlier authority
files can be concurrently edited; the recorded prerequisite parity is narrowly
scoped rather than a claim that every source file matches every installed body.
