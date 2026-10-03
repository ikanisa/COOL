# Controlled rollout of the reconciled hardening candidate

This is candidate code, not a production release or an assertion that the 100 audit tasks are closed. The source is a cumulative partial overlay for an authorized full checkout. Existing application files outside its manifest are preserved. `revolut-design` remains the sole design authority.

## Source and exposure boundary

The recorded Drive folder has an anyone-with-link writer grant. No permission was changed in this delivery. Do not put credentials, customer SMS, review-access passwords, signing material, or live operational exports in that folder. The owner-operated `scripts/hardening/restrict_drive_sharing.py` defaults to a read-only plan, requires a separately obtained OAuth access token and explicit folder confirmation for a change, and only removes root public-link grants. Child-specific grants still need inspection. It was not executed against Google in this delivery.

The GitHub origin `ikanisa/COOL` was discovered and its main commit was inspected. That is not proof that its September source and later Drive working files are equal. No main-branch update or production deployment was performed. A source-capture Git tree object was prepared but was not committed to or activated on a branch.

The Payment Decoding branch supplies the broader payment/contribution decoder. The Intent Decoding public behavioral suites are retained. Its private-helper source checks were updated to check the retained helper names and unchanged validation obligations. Shared source is not blindly overwritten by the other branch. Full Dart execution remains required.

## Deployment order — do not deploy individual files independently

1. Restrict source/evidence access, preserve revisions and independently verify the source/archive checksums. Obtain the authorized full checkout, resolve all installer conflicts without forcing, and review the merged diff.
2. Prepare a quiescent, isolated staging environment with synthetic accounts and a restorable database. Take and verify an authorized backup. Real customer financial actions must not be used as test fixtures.
3. Rehearse the additive `20260928160000_sms_observation_never_settles.sql` migration in the complete chain, including its corrected SMS-boundary UAT and deployed-function/grant readback. It is local source and has only passed a minimal PostgreSQL scratch test. Then register the three staged SQL files through the installed pinned Supabase CLI using `scripts/hardening/register_staged_sql.py --register`. This creates CLI-generated migration names; it never applies SQL. Rehearse the full staged chain and test the real functions, grants, roles, enum types, row locks and journal invariants. The staged SQL was not applied in this delivery.
4. Rehearse the receipt-v2 SQL, Edge handlers and new native/mobile acknowledgement contract together. Unknown contract versions fail closed. The current parser returns an SMS-observed state; the historical database finalizer can still self-confirm if the new containment migration is not installed. Do not resume production posting merely because a receipt was stored or parsed.
5. Set an explicitly approved licensed build minimum and signing-certificate allowlist. The fixture version in tests is not the approved production build. Validate Google Play installations and actual MTN/Airtel sender samples before enforcement. The narrower native sender check must not silently lose supported real operator formats.
6. Configure OTP template/version/language/button policy and the private global quota row with approved budgets. No default quota is silently enabled. The new hook requires signed Standard Webhooks input. An uncertain provider send leaves the hook reservation unresolved rather than automatically sending twice; a new user-requested hook or operator reconciliation is needed. Establish monitoring, expiry/retention and a support procedure for unresolved reservations.
7. The staged reconciliation path separates proposal and approval using distinct authenticated AAL2 users with the existing `payments.allocate` permission. Only an approved review can reach the service-only finalizer. This is not a provider API integration, and source evidence must be independently obtained and verified. The operational UI, reviewer-role revocation races, approved-record expiry, full financial-engine permissions and actual settlement/reversal tests remain release gates. No reconciliation was performed here.
8. Run the pinned formatter, full Flutter analysis, every original and added Dart test, Deno checks, native builds, signed release artifacts and web builds. The delivered boundary tests are not substitutes. Then execute real-device account-switch, process-death, boot, key-lock, permission-revocation, overflow, dual-SIM and slow-network journeys.
9. Verify read-only production readiness with a named protected environment and a truly read-only database credential. Missing evidence is a failure, not a successful skip. The manifest validator checks consistency; a file checksum is not an independent signature or an approval.
10. Require all G0–G5 gates before an unrestricted launch. Use a monitored constrained pilot only after separately approved risks and rollback criteria. Neither a package upload nor a test count authorizes a release.

## Receipt lifecycle

`queued locally → durable server storage → parsing/matching → independent reconciliation → posted journal`.

The storage ACK binds owner, envelope, exact body digest and raw record ID. Client checks happen after awaited operations and immediately before native deletion. Native code independently checks current owner and stored-body hashes inside its queue lock. A processing failure yields a retry response; the client retains the local receipt. An exact committed replay can receive the same durable acknowledgement even after the client obtains a fresh short-lived capability. This requires real database integration testing before rollout.

A decryption failure preserves ciphertext and reports queue unavailability. Retrying a read may recover from a transient key lock. Explicit user consent revocation and account-switch clearing retain their existing deletion semantics; this delivery does not claim a redesigned retention policy. The existing queue is still process-assisted and bounded: OS-persistent headless processing and overflow recovery remain open.

## Safe rollback

Pause financial finalization first. Preserve raw SMS, queue ciphertext, journal entries and reconciliation records. Never fix an outage by restoring the former SMS-to-settlement shortcut or by accepting an unknown contract version. Application source backups from the installer permit file restoration but are not database backups. Financial corrections must remain compensating entries, not destructive record edits. Verify rollback on isolated data before approving the production sequence.

## Important unfinished work

Full-checkout compilation; live migration and RLS tests; independently verified provider/reconciliation integration; review UI and operational reviewer lifecycle; persistent background capture; full application validation of the protected financial cache; scalable relational history queries; valid late-receipt semantics; dynamic data cleanup; current CAPTCHA/PITR/restore evidence; app-store and physical-device acceptance; incident and privacy/legal approvals. See the 100-task status register for individual evidence requirements. The task register does not mark these items complete because helper tests passed.

## Verified Integration v2

Read `PROTECTED_CACHE_AND_VIEW_INTEGRATION.md` for the implemented native protected cache, authoritative Home display, review fingerprint and Admin build headers. These extend the candidate without closing the listed production gates.
