# Isolated v3 identity workflow evidence

Final attempt3 passed 92 local assertions on PostgreSQL 17.6. The fresh owned container required all 177 captured source08 prerequisite migrations, followed by captured 111000 and final 180000 migrations. Existing nonempty financial and primary receipt fingerprints were preserved. Network mode was none, no ports were published, cron was off, and the owned container was removed.

Executed command:

```sh
python3 scripts/qa/receipt_operations_enrollment_workflow_uat.py --report-dir docs/release/collect-codex-goal-2026-09-30/receipt-operations-enrollment-workflow-20261001/sql/attempt3
```

Exit status: 0. `attempt3/result.json` records all checks, exact source hashes, the target guard and cleanup. Captured SQL inputs and installer/runner bytes are retained under `attempt3/inputs`. Actual output fixtures use the `observed-` prefix. The literal exercised query log and synthetic seed are retained in `attempt3/enrollment`.

The six authenticated owner RPCs are `admin_enroll_receipt_operations_identity_v3`, `admin_activate_receipt_operations_identity_v3`, `admin_revoke_receipt_operations_identity_v3`, `admin_get_receipt_operations_enrollment_request_v3`, `admin_get_receipt_operations_identity_v3` and `admin_list_receipt_operations_identities_v3`. Mutation deadlines must be in the next 120 seconds and are rechecked with current authority after each original UUID advisory lock, identity row lock and delegated operation. All mutations acquire both existing operations and supervisor owner UUID namespaces and refuse either preexisting legacy request namespace. Workflow persistence and underlying identity mutation commit atomically. Enrollment/activation require the identity to remain live at the receipt timestamp; activation also enforces creator ownership. Revocation requires current actor ownership, operations scope and exact key binding, and permits expired pending or active credentials. A fresh UUID cannot mutate an already revoked identity.

All receipts have the ten common v3 fields. Only a revoke receipt adds `reason_sha256`, binding SHA256 of the exact trimmed reason encoded as UTF8. The new retained revoke input stores this hash and immutable source expiry, with no raw reason in the wrapper evidence or API output. Synthetic public input fixtures retain the canonical trimmed reason; the literal concurrent SQL calls deliberately supplied surrounding ASCIIspaces to verify digest normalization. The literal arguments remain in the captured SQL query log.

Recovery reads the original UUID and returns immutable actor-bound receipts. The same actor may use a fresh authorized session. Lookup nonblocking trylocks both namespaces and reports in-progress contention. A legacy v1/v2 recorded UUID without v3 evidence is refused instead of labeled absent. Lookup absence contains no invented deadline; the client must retain the original deadline and only close absence using a fresh server check beyond that deadline. UTC output uses six fractional digits.

Identity directory output is restricted to the current actor and receipt operations scope, redacts source SPKI, and uses paired tuple pagination with at most 25 rows. Revocation retains historical receipts and immutable identity key/expiry. An expired active source identity remains active in directory output until explicitly revoked; expiry separately prevents use.

These results cover local SQL mechanics with synthetic public curve points and injected SQL role claims. The actual operations SQL boundary refused a revoked key. Auth provider behavior, signed JWT validation, cryptographic signature verification, hosted installer privileges, hosting, Keychain/device use, SMS sending and production enrollment are not attested. No credentials, hosted calls or signing material were used.

Attempts1 and2 remain predecessor execution evidence (56 and60 checks respectively); their original seal/readback records are retained separately. `attempt2-README.md` preserves the preceding leaf explanation. `evidence-seal.json` binds every current evidence file other than the seal and its readback. `seal-readback.json` records independent hash readback and the current source binding.
