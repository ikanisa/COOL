# Local application-fence qualification

`qualify.mjs` prepares three new synthetic PostgreSQL databases and runs the maintained `native-contract.mjs` plus `native-capacity.mjs` proof/release scenarios. It uses the existing pinned `pg@8.16.3` installation. Root supplies/reviews those two runners; they are required local inputs, not downloaded resources.

Run from the maintained project after installing its locked tooling. Supply `COLLECT_FENCE_ADMIN_DATABASE_URL` through the existing secure process environment. Its value must be a PostgreSQL URL with credentials, explicit port, literal `127.0.0.1` or `[::1]`, exact `/postgres`, and no query/hash. `localhost`, socket URLs, hosted names and non-admin database paths are rejected. Do not put the URL in command arguments, shell history, logs or files. The caller consumes/deletes this environment variable before spawning runners. It accepts no arguments or source-root override.

```sh
node scripts/supabase/emergency-fence/qualify.mjs
```

The physical repository root comes only from the maintained package location. Before database creation, the caller requires local fixture `00_local_auth_fixture.sql`, exactly the ten listed numeric migrations through `20261022200028_collect_private_member_realtime.sql`, and both maintained runners. It fingerprints those files, itself and package/lock metadata; it checks the fingerprints before/after each case. Symlinked source inputs and unexpected migration chains fail closed. `COLLECT_PG_MODULE` may select an absolute installed module path; otherwise the caller resolves the existing local `pg` package. Its installed version and the package dependency must both be `8.16.3`.

Each invocation selects one random 24-hex suffix and creates these databases from `template0`:

- `collect_fence_sql_<hex>_test`
- `collect_fence_capacity_proof_<hex>_test`
- `collect_fence_capacity_release_<hex>_test`

The longest name remains below PostgreSQL's 63-byte identifier limit. The caller connects to `/postgres` and verifies actual server identity/PG17/read-committed before CREATE DATABASE. For each new database it verifies identity and absence of application/private/Auth schemas, applies fixture00 and the exact ten reviewed migrations through the shared fixture loader (genuine hosted-binding refusal followed by the exact reviewed synthetic SQL10 binding), then initializes synthetic source `a` repeated64 with baseline `dfc7a4fafb696f73d207251c9f35cb892528eecd1929552fa575996874adc3e3` through the owner API. This is synthetic initialization, never a production source label. The local fixture creates restricted synthetic roles; it must never run against a managed project.

The contract runner receives only `COLLECT_FENCE_SQL_TEST_DATABASE_URL`; each capacity runner receives only `COLLECT_FENCE_SQL_CAPACITY_DATABASE_URL`. URLs are environment-only. Child environments contain only essential local process settings, the selected `pg` module, `COLLECT_CI_SYNTHETIC=true`, and their one fixture URL. Provider/Auth credentials, unrelated database URLs and `NODE_OPTIONS` are not inherited. The caller uses `spawn` without a shell. Setup and each child are bounded at150 seconds; child termination escalates after5 seconds. A timeout or connection loss is unconfirmed: no automatic retry, alternate UUID initialization, DROP DATABASE, schema reset or history cleanup occurs.

All databases are preserved after success or failure. A private physical OS temporary directory holds a durable plan, create intent/acknowledgement, per-case safe results and `FINAL.json`; its path and synthetic database names appear in the final safe summary. Raw child stdout/stderr and PostgreSQL errors are not persisted or echoed because they could contain connection details/assertion operands. Instead results retain output byte counts and SHA256, exit/signal/timeout state and validated bounded PASS counts. A failed/partial database remains evidence, not a source to rerun. Root may inspect it read-only before starting an entirely new unique qualification invocation.

PASS requires all three maintained runners to report their exact synthetic scope, unchanged97 application tables, zero provider calls and false hosted/SB29 acceptance. The contract case also retains one unresolved admission and one unknown obligation; these are intentional native assertions, not cleanup failures. Capacity cases preserve their synthetic proof/operation history and blocked release states. This checks local SQL contract/capacity/MVCC behavior. It does not establish actual hosted Free capacity, runtime/provider timing, managed Auth/Storage behavior, arbitrary-loss recovery, an approved source-upgrade mechanism, RPO/RTO or cutover acceptance.

## Proposed existing-job CI invocation

Add one step to the existing `local-qualification` job after locked tooling installation and before downstream acceptance. No workflow edit is included in this proposal. Derive `/postgres` from the job's existing synthetic `COLLECT_TEST_PG_URL` in memory; never echo the derived URL:

```yaml
- name: Qualify application fence on three fresh retained local databases
  run: |
    node --input-type=module <<'NODE'
    import {spawn} from 'node:child_process';
    const admin = new URL(process.env.COLLECT_TEST_PG_URL);
    admin.pathname = '/postgres';
    const child = spawn(process.execPath, ['scripts/supabase/emergency-fence/qualify.mjs'], {
      env: {...process.env, COLLECT_FENCE_ADMIN_DATABASE_URL: admin.href},
      shell: false, stdio: 'inherit',
    });
    child.on('error', () => { process.exitCode = 1; });
    child.on('exit', code => { process.exitCode = code ?? 1; });
    NODE
```

The existing isolated CI service uses PostgreSQL17 and loopback port55439. Root's separate fresh local cluster may supply port55443 through its private environment. Neither requires changing the runner's unique-name guards or reusing/resetting existing fixture databases. The caller can run on macOS and Linux without private cache paths or platform-specific executables.

## Idle PostgreSQL connection failure

Every `pg.Client` installs a fixed-code `error` listener before connecting. An idle/disconnected error poisons the whole invocation, aborts further setup/query dispatch, prevents a later child from starting and terminates an already running child. No raw error message/stack/URL is logged. Already dispatched SQL or child effects remain unconfirmed evidence; no reconnect, retry, reset or database removal occurs. The three original SQL/capacity cases and their input/owned-database guards remain unchanged.

## Actual runtime/SQL pending-effect witness

`native-runtime.ts` is a separate maintained Deno caller, not a fourth SQL/capacity scenario. Root prepares a fresh database named `collect_fence_runtime_<8–32 lowercase hex>_test` on a literal loopback address with an explicit port, applying fixture00 and the same exact ten reviewed migrations, then calling owner initialization once with synthetic source `a` repeated64 and the documented baseline. The database must contain zero admissions, only the initialization operation, zero owned witness rows and an OPENepoch1 nonblocking scheduler. The current SQL9 bytes, reviewed SQL10 fixture binding and runtime4 import closure are pinned in this witness. It never creates, resets, restores or drops a database, initializes control, or retries a mutation.

Supply only `COLLECT_FENCE_RUNTIME_TEST_DATABASE_URL` in Root's secure environment; never in arguments, logs or source. The witness consumes/deletes it. Root uses a fresh PG17 fixture with the exact restricted synthetic `postgres` role flags from fixture00; an existing cluster with incompatible global roles must be preserved and replaced by a new isolated cluster, never silently ALTERed by this witness.

From the maintained repository (the fixed physical package root, without any private-cache imports):

```sh
deno run --config=supabase/functions/deno.json --cached-only --frozen --allow-env --allow-read=. --allow-net=127.0.0.1:55443 scripts/supabase/emergency-fence/native-runtime.ts
```

The Deno driver is actual cached `npm:postgres@3.4.7`; offline/cached-only resolution must already be available. The driver reads standard PG option environment names, so the command permits environment access; the witness deletes its credential variable and the fixed ambient PG option names before connection construction without logging their values. Root should launch with a minimal environment. The narrow network permission must match Root's selected literal address/port. The witness uses actual `connection`/`fenceConnection`, actual `sqlFenceBackend` and actual `openApplicationWork`; no separately constructed WORK lease or stand-in SQL backend is accepted. A separate real owner connection performs status/quiesce/drain only. The actual SMTP adapter and transactional wrapper use an injected local synthetic transport whose single raw `sendMail` promise is held; no SMTP socket, Auth/Storage/provider request, external fetch or human message occurs.

The actual10-second consumer timeout must reject while that raw promise is still pending. The admitted real PostgresDatabase writes one immutable synthetic `request_receipts` unknown response under the original request identity. Committed QUIESCING denies a new admission. An actual owner drain fails its150ms lock timeout while the production controller still holds sharedWORK; status and pg_locks confirm active work. `finish()` remains pending until original raw settlement, then records settled/completed_with_unknown_obligation (1dispatch/1unknown), retains the exact receipt and allows owner drain to FENCED. The originally observed timeout/receipt is never upgraded by a late SMTP success and no send is replayed. This is a synthetic immutable-request-receipt caller, not an invitation/provider acceptance workflow.

The witness fingerprints all97 application tables before and after, excluding only its exact newly inserted synthetic user/request rows, and separately compares those owned rows byte-for-byte. All unrelated application rows must remain unchanged. Private admission/control/operation rows change only through the real owner/runtime APIs; one retained unknown remains. Safe stdout reports bounded check counts and hashes only. Any error emits a fixed stage/code, preserves the database and exits without replay or cleanup writes.

This is local pairing evidence only after Root executes it. It does not establish hosted capacity, provider settlement, universal managed-internal fencing, arbitrary-loss restore, fullSB29, RPO/RTO, selected recovery strategy or cutover. The optional actual HTTP raw-body-cancel native case is outside this finite witness; existing offline raw-body tests remain separate evidence.

For maintained preparation of two separate pristine runtime/Realtime fixtures, see [`../testing/member-realtime-native.md`](../testing/member-realtime-native.md). That preparer does not run `test_schema.mjs` against the runtime witness database. The three SQL/capacity scenarios above retain their separate databases and scope.
