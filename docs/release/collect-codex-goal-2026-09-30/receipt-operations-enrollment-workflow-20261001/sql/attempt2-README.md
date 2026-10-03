# Isolated v3 enrollment workflow evidence

The additive migration and stdlib harness passed 60 local assertions on PostgreSQL 17.6. The fresh owned container required all 177 captured source08 prerequisite migrations, followed by captured 111000 and 180000 migrations. Existing nonempty financial and primary receipt fingerprints were preserved. Network mode was none, no ports were published, cron was off, and the owned container was removed.

Executed command:

```sh
python3 scripts/qa/receipt_operations_enrollment_workflow_uat.py --report-dir docs/release/collect-codex-goal-2026-09-30/receipt-operations-enrollment-workflow-20261001/sql/attempt2
```

Exit status: 0. `attempt2/result.json` records all checks, exact source hashes, the target guard and cleanup. Captured SQL inputs and installer/runner bytes are retained under `attempt2/inputs`. Actual output fixtures use the `observed-` prefix. The query log and synthetic seed are retained in `attempt2/enrollment`.

The five authenticated owner RPCs are `admin_enroll_receipt_operations_identity_v3`, `admin_activate_receipt_operations_identity_v3`, `admin_get_receipt_operations_enrollment_request_v3`, `admin_get_receipt_operations_identity_v3` and `admin_list_receipt_operations_identities_v3`. Mutation deadlines must be in the next 120 seconds and are rechecked after the original UUID advisory lock and after delegated v2 operations. Workflow persistence and underlying identity mutation commit atomically. Recovery reads the original UUID, returns immutable actor-bound receipts, permits the same actor with a fresh authorized session, and uses a nonblocking lock to distinguish an in-progress request. A legacy v2 recorded UUID without v3 evidence is refused rather than labeled absent. Lookup absence contains no invented deadline; the client must retain its original deadline and only close absence using a fresh server check beyond that deadline. Timestamp output uses six fractional digits from the existing UTC formatter.

Identity directory output is restricted to the current actor and receipt operations scope, redacts source SPKI, and uses paired tuple pagination with at most 25 rows. Revocation retains historical receipts and immutable identity key/expiry. An expired active source identity remains active in directory output; expiry separately prevents use.

These results cover local SQL mechanics with synthetic public curve points and injected SQL role claims. They do not attest Auth provider behavior, signed JWT validation, signature verification, hosted installer privileges, hosting, Keychain/device use, SMS sending, or production enrollment. No credentials, hosted calls or signing material were used.

`evidence-seal.json` binds every evidence file other than the seal and its readback. `seal-readback.json` records a separate hash readback and current source binding.

Attempt1 remains predecessor evidence for the original 56-case implementation. Attempt2 adds current-actor activation ownership and final identity-expiry gates, with four new regression assertions. The predecessor seal/readback are retained separately. Final mutation receipts require the identity to remain live at recorded_at.
