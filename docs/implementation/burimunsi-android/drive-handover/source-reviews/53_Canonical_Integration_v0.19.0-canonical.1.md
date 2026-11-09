# BuriMunsi canonical integration — v0.19.0-canonical.1

9 November 2026 · Source implementation and local verification

## Delivery boundary

This extension is based on the complete v0.18.0 BuriMunsi source from Drive and preserves its owner-bound operation recovery. The web prototype remains v1.1.0. The separate financial-qualification v0.17.1 branch and other concurrent build, SMS or UI work are not implicitly merged. Unknown changes must remain installer conflicts.

The package contains the BuriMunsi backend/native integration overlay, tests, additive schema specification, installer, pinned inputs already supplied by v0.18.0, evidence and handoff. The complete delivery also includes the unchanged web source. It is not the entire Collect repository, an APK, a deployed service, a working provider credential broker or proof that production acceptance is complete.

## What changed

| Area | Implemented | Deliberately not manufactured |
|---|---|---|
| PIN sessions | Genuine managed-session verification, native-session linkage in the same issuance transaction, expiry capping, per-request linkage validation and native access-token provider hook | Provider identity from a PIN, a service key, an admin admission or a refreshed managed credential |
| Worker authority | Branded jobs admission, source fingerprint, explicit scoped grant, receipt/rematch lease validation and the unchanged canonical financial guard | Permission escalation, an invented actor or a permanently fresh human session |
| Member identities | Scoped, approved, effective-dated ownership evidence with ambiguity retention and complete bounded snapshots | Ownership inferred from a display name, login number, profile MoMo number or masked payer identifier |
| Payment sources | Original retained capture lineage, encrypted journal custody and adoption of exactly one accepted canonical transaction | A second parser-created transaction, payment, savings ledger or unaudited bucket fallback |
| Scheduler | Durable group lease, policy/profile rechecks, bounded queue slices, resumable durable jobs and uncertain-finalization handling | A public job endpoint, automatic cron registration, or cancellation of an in-flight financial operation |

### Session binding and native transport

`managed-request-gate.js` receives a managed access token through `X-BuriMunsi-Collect-Session`, independently of the native `Authorization` bearer and device grant. The installed entrypoint imports Collect's actual `verifyToken` and `projectSession`; it requires an existing principal link and admitted admin surface. It discards cached actor data and the admin-exchange override, checks application-work ownership around awaits, forbids concurrent sharing of the request database, and clears projected claims on exit.

`postgres-managed-sessions.js` binds a successfully verified native PIN session to the same canonical principal and managed session. Native expiry cannot exceed canonical expiry. Link insertion, token insertion and audit occur together. Revocation, expiry, wrong surface, changed principal or a different managed login rejects the old native session. Refresh retaining the same managed session ID does not invent a new linkage. Missing legacy linkage is not silently repaired.

The Kotlin `ManagedSessionTokenProvider` supplies an already-authenticated access token before network dispatch. `ManagedSessionHost` is the explicit application hook used by `BuriViewModel`. Invalid or missing tokens in that configured provider fail locally; PIN requests are not retried without managed proof. The legacy application constructor remains for existing noncanonical configurations, but the canonical server rejects requests lacking its managed-session header.

**Still required:** implement the actual application's approved login/refresh broker and `ManagedSessionHost`. This work does not issue a Supabase session from a local PIN, provision real operators, or test live provider authentication. Do not ship a permanent token, service-role key or refresh credential in an APK.

### Worker authority

`postgres-worker-authority.js` requires the existing branded `kind=jobs` application context and an explicit scoped worker grant. The grant binds owner, principal, managed session, deployment-source fingerprint, approved policy and permitted receipt/rematch work. Lease ownership is checked before and after the unchanged financial guard; policy/grant/session changes invalidate the proof. Rematch target identity remains bound to the job.

The existing posting guard still requires its canonical permission, assurance and freshness conditions. A grant alone is not a credential. If the deployment's actual authentication policy cannot provide an appropriately authorized unattended worker, automatic posting remains blocked. Resolve that institutional policy and credential lifecycle explicitly; do not weaken freshness or impersonate a human administrator to make a scheduler run.

### Identity directory and processing admission

`postgres-identity-directory.js` reads canonical membership plus owner-approved evidence in `private.burimunsi_identity_proofs`. Evidence records the member, normalized full phone, purpose, validity interval, approval, source reference and evidence digest. Policy is versioned, effective and revocable. Missing/disabled policy returns no verified identities. Row limits fail rather than silently dropping a competing owner. An inactive competing owner remains in historical evidence so ambiguous receipts cannot become false matches.

`postgres-processing-admission.js` requires the canonical environment pause to be explicitly false and the scoped policy to allow work. It validates the current receiving-account profile through Collect's real validator and compares both version and exact profile-byte digest. Sender/timezone are derived from that approved profile, never from client or scheduler JSON. This adapter only admits the native parser's supported MTN/YMD grammar; it does not add Airtel or new message formats.

Identity and worker approval tables are empty and disabled by default. The runtime cannot approve identities, change policy fields or mint worker grants. PostgreSQL row-locking reads need an UPDATE privilege on at least one column; the new schema grants it only on `lock_anchor`, a NOT NULL value constrained permanently to zero. This permits locking without granting authorization-field edits. Real runtime-role/RLS qualification remains mandatory.

### Retained sources and canonical adoption

`postgres-retained-sources.js` verifies the original SMS receipt, gateway capture, active credential/binding, receiving account, current scope/binding version, subscription and completed canonical-processing job. It uses the existing encrypted local journal and original AAD. It rejects deletion intents, retention barriers, missing/scrubbed payloads, changed namespace, ciphertext metadata, source hashes or subscription evidence. It rechecks lineage and custody after decryption. It never substitutes the newest source or trusts raw SMS supplied to a queue call.

`postgres-canonical-adoption.js` reparses that original source under the approved exact profile and requires exactly one accepted canonical source relation/parse attempt. Amount, currency, provider reference, timestamp, payer identity, body hash and profile must agree. Only a scoped routing row is inserted; no second canonical transaction, payment or ledger is created. Conflict, compensation, reversed status and inconsistent payment/ledger amounts cannot be reported as a healthy posted result.

`composePostgresNativeWorkers(...).enqueueRetainedSource(sourceId)` generates the descriptor from canonical SQL and enqueues it transactionally. Its input is an original source ID, not a body, group, digest, parsed receipt or ledger entry. **The deployment must connect a trusted canonical-completion hook or bounded discovery/recovery process to this method.** The scheduler does not discover all historical sources by itself. Pending/unaccepted/conflicting canonical sources remain unavailable rather than being independently credited.

### Scheduler behavior

`postgres-scheduler.js` stores a durable per-group scheduler lease with run ID, owner, lease version, SQL-clock expiry, admission fingerprint, profile and policy. Concurrent valid ownership returns `busy`; expired takeover increments the version and invalidates the previous owner. Policy/profile changes prevent new work. Each invocation runs bounded one-job slices from existing receipt/rematch queues and renews its scheduler lease before each slice.

The time budget stops NEW starts; it does not race, detach or cancel an already-running financial operation. Completion records bounded operational counters, not raw financial payloads. Counters are observations and are not proof of newly credited funds. A lost finalization acknowledgement returns `scheduler_outcome_unknown`; it does not blindly finalize twice or replay the financial work. Durable job/ledger idempotency remains the recovery mechanism.

`runCanonicalScheduledCycle` is a server-only installed entrypoint. It requires a real jobs context and approved managed credential. It is not an unauthenticated HTTP endpoint and does not install a cron schedule.

## Installed integration sequence

1. **Verify the source and exact upstream.** Run the source-integrity verifier. Use an exclusively controlled Collect checkout corresponding to the recorded repository reference, then run `scripts/verify_canonical_inputs.py --collect-root /path/to/COOL`. That checker verifies direct upstream module bytes against Git; it is not a runtime import or deployment test. The old `.js`/receiver scanner alone does not cover the installed `.mjs` entrypoint.
2. **Reconcile and apply a normal migration on disposable/staging PostgreSQL.** `native/burimunsi/integration/canonical-integration-proposal.sql` is an additive specification, not an applied migration. Reconcile existing proposal order, key types, actual runtime grants and schema state. Do not run it blindly on a live database.
3. **Supply genuine authentication and remaining server bridges.** Mount the native managed-session provider, route admitted requests to `handleCanonicalNativeRequest`, and keep native/managed bearers distinct through the authenticated gateway. The existing trusted principal provisioning, direct-member/membership commands, source reader, gateway adapter and posting-preparation media/encryption inputs are still deployment dependencies. They must not be supplied by request JSON.
4. **Approve actual scope and evidence.** Populate owner-reviewed identity evidence and processing policy with exact provider-profile digest/version. Provision a real authorized worker session and its scoped, expiring grant. Reconcile the actual canonical financial permission/assurance/freshness policy before choosing unattended operation. No sample fixture is approval evidence.
5. **Wire canonical completion and scheduling.** In a genuine admitted context, enqueue retained original source IDs after canonical acceptance. Connect the existing authenticated scheduler to `runCanonicalScheduledCycle`, with bounded limits and proper pause behavior. Confirm completion-hook recovery and backlog discovery explicitly.
6. **Qualify before enabling.** Keep `canonicalIntegrationEnabled` off until staging acceptance passes. Enabling it also requires the existing shared-posting, custody, journal-allocation, posting-preparation and native-posting-authority flags; conflicting injected adapters are rejected. Existing global/local processing holds remain authoritative. Enable only the approved scope after acceptance, not every scope by default.

Installer dry run:

```sh
python3 scripts/verify_candidate.py
python3 scripts/verify_canonical_inputs.py --collect-root /path/to/COOL
python3 scripts/apply_to_collect.py --collect-root /path/to/COOL
```

The installer now recognizes exact delivered v0.18.0 bytes in addition to earlier baselines. Unknown local edits and parallel branch changes remain conflicts. `--apply` copies the approved overlay only; it does not commit, migrate, deploy, move money or enable features. Perform the full runtime import and route integration inside the installed Collect project after the dry-run diff is reconciled.

## Required real-system acceptance

| Priority | Remaining work | Required evidence |
|---|---|---|
| P0 | Managed session broker and native host | Actual login, refresh, revocation, expiry, re-login, same-person binding and wrong-person rejection with real provider sessions; no token/PIN logging |
| P0 | Database migration and privilege model | Real PostgreSQL under `collect_runtime`, FORCE RLS, scoped reads, lock-only column privilege, denied identity/policy/grant edits, native-link atomic rollback and key compatibility |
| P0 | Concurrency and command recovery | Competing scheduler/job leases, grant/policy rotation, overlapping identities inserted/revoked during work, binding replacement, pause mid-run, deadlocks/retries and dropped commit acknowledgements |
| P0 | Canonical payment reconciliation | Real original retained sources, accepted/duplicate/conflicting events, reversals/compensation, existing payment/ledger parity and proof that replay never creates duplicate credit |
| P0 | Authenticated runtime wiring | Real route admission, remaining trusted bridges, original-source completion/recovery hooks, scheduler registration, environment/source fingerprint and worker credential lifecycle |
| P1 | Native and operational acceptance | Pinned-toolchain APK builds, device/Android lifecycle, SIM/reboot/replacement/carrier tests, actual token-provider storage, monitoring and rollback exercise |

Owner edits must use the same canonical mutation serialization discipline as the rest of Collect. Existing-row locks do not by themselves qualify concurrent insertion of a new overlapping identity. Test those races explicitly on PostgreSQL; never turn a local fixture pass into a production isolation claim.

Stopping processing is the rollback action: disable the approved policy/scheduler and revert the installed route/feature flag under the existing change process. Preserve command journals, canonical payments, ledgers and source evidence. Do not erase history or resend unresolved operations as a rollback shortcut.

## Evidence and execution limits

`VERIFICATION.md` and `evidence/canonical-integration/` contain the executed local results. No live database, carrier, provider, APK, Cloudflare deployment, GitHub commit or production operation was performed. The requested macOS efficient-codex skill path was not mounted in this execution environment; its contents were not available.

Reference behavior was inspected in the user's `ikanisa/COOL` source at the recorded reference. PostgreSQL's row-lock privilege requirement is documented at https://www.postgresql.org/docs/current/sql-select.html. Source integrity, source compatibility and production acceptance are separate claims throughout this handoff.
