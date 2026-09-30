# Post-141 reconciliation checks — prepared source

Date: 30 September 2026. This supplement records **Ruby syntax and source-contract checks only**. The author performed no Docker inspection, database calls, hosted Auth requests, provider sends or deployments. SQL execution and the resulting database acceptance belong to the separate root-owned run.

## Frozen inputs and harness

`scripts/tests/reconciliation_post141_deployment_uat.rb` SHA-256:
`9c060d84b7fd5c432954423f1c3319f71e23329ac8cf02752a62a72e9e3e38df`.

The harness requires exact hashes for the staged installer, migration 141 and the original dated 140 workflow UAT. The inputs and generated SQL hashes are retained in `post141-source-contract.stdout`. Neither the original SQL UAT nor the migration/installer is edited by this harness.

## Root execution

Run sequentially after all other fixture tests have disconnected:

```sh
COLLECT_RECONCILIATION_QA=isolated_clone ruby scripts/tests/reconciliation_post141_deployment_uat.rb > docs/release/governed-reconciliation-2026-09-30/post141-deployment-result.json 2> docs/release/governed-reconciliation-2026-09-30/post141-deployment.stderr
```

The required fixture is `supabase_db_collect_fin_concurrency_qa_20260929`, Docker labels for project `collect_fin_concurrency_qa_20260929`, host port **55722**, and the matching task-local Supabase configuration. The database must be `postgres`, the SQL owner `postgres`, with exactly **141** migration rows, latest version `20260929180000`, the installed gate-aware wrappers, disabled cron, `pg_net.batch_size=0`, empty token/delivery tables, unused original `99900000` fixture identities and no other active client transaction. The script refuses any mismatch.

## Prepared checks

1. Assert the staged installer's exact initial sequence contains only `BEGIN`, the 141 advisory lock and the read/check block before any schema, function, grant or row mutation. Run the actual staged source with only its terminal `COMMIT` changed to `ROLLBACK`. Require psql exit **3**, SQLSTATE **55000** and the exact `reconciliation_staged_installer_superseded_use_numbered_migrations` error. `ON_ERROR_STOP` stops execution at that guard; an unexpected successful path also rolls back and fails the test.
2. Compare complete row hashes and catalog-control hashes before and after that attempt. Coverage includes application/private schemas, Auth, realtime and the migration registry; catalog coverage includes function definitions/owners/ACLs, schema and relation ACLs, RLS, columns/defaults, triggers, constraints, indexes and policies. Direct financial service grants and browser finalization remain denied.
3. Derive an explicitly identified **integrated 141** variant from the pinned original 140 UAT. Change only the count/version/error guard, add the stronger fixture checks and use a distinct `RECONCILIATION_WORKFLOW_INTEGRATED141_UAT_PASS` marker. Preserve all original actors, scenarios, assertions, evidence, savepoints and the final rollback. Require **58** assertions and the same complete baseline after rollback.

No trigger-disabling cleanup or `setval` is used. PostgreSQL sequence counters consumed by synthetic inserts are not transactional and are explicitly excluded from row-restoration claims. The script does not test overlapping sessions; the separate reconciliation concurrency harness owns that evidence.

## Checks performed on the source

- `ruby -c scripts/tests/reconciliation_post141_deployment_uat.rb`: **Syntax OK**, exit 0.
- `ruby scripts/tests/reconciliation_post141_deployment_uat.rb --source-only`: pinned inputs and derived-source contracts pass, exit 0; **zero database calls**.
- Runtime: system Ruby 2.6.10, arm64 macOS.

Exact commands, log hashes and source fingerprints are in `post141-source-validation.json`. These checks do not establish PostgreSQL parsing, execution, rollback or deployment acceptance.
