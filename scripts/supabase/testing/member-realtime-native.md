# Two fresh local runtime and Realtime fixtures

`qualify-member-realtime-native.mjs` prepares two new PostgreSQL17 databases and runs the maintained actual-runtime SMTP witness and the separate Realtime interface subset. It uses the existing locked `pg@8.16.3` and Deno2.9.6, without another dependency, database reset or test fence bypass.

Use Node24. Supply `COLLECT_CI_SYNTHETIC=true`, `COLLECT_DENO` as the physical absolute executable path, and `COLLECT_MEMBER_REALTIME_ADMIN_DATABASE_URL` through the existing private environment. That URL must have username `collect_test`, a password, literal `127.0.0.1`, an explicit numeric port and exactly `/postgres`, with no query/hash. IPv6, `localhost`, hosted names, encoded usernames, normalized path tricks and command arguments are refused. Never place the URL in arguments, source, logs or a shell command. The caller consumes/deletes its credential variable before spawning a child. Its physical source root comes only from its maintained location, without an override.

```sh
node --test scripts/supabase/testing/qualify-member-realtime-native.test.mjs
node scripts/supabase/testing/qualify-member-realtime-native.mjs
```

`COLLECT_PG_MODULE` may point to the existing physical absolute `pg` entry/package path; otherwise the maintained package resolves `pg`. Both installed and declared versions must be8.16.3. The optional `DENO_DIR` must already be an existing physical absolute directory containing the locked cached modules. Deno's exact2.9.6 version, physical executable and hash are checked before loading the driver or opening a database connection. No installation or cache download is performed. The existing workflow must populate its cache before this offline step.

The two names share a fresh random24-hex suffix:

- `collect_fence_runtime_<suffix>_test`
- `collect_member_realtime_<suffix>_test`

The caller observes actual PG17/read-committed identity, the literal address/port, current and session role `collect_test` and SUPER/BYPASS before CREATE; each new fixture must also be owned by `collect_test`. The fixture's separate `postgres` role must retain all seven restricted flagsfalse; the caller never ALTERs any role. An existing incompatible local cluster must be preserved and replaced by a separate correctly configured cluster by its owner. There is no port55439 assumption and no managed URL path.

Each CREATE is preceded by a durable private intent and an absence check, uses `OWNER collect_test TEMPLATE template0`, and occurs once. Each new database must be empty and owned by `collect_test`. The real `loadReviewedPlatformFixture(...).apply(...,{includeAuth:true})` then applies fixture00 plus the exact ten curated migrations. It executes the genuine hosted SQL10 binding against the different local profile and requires its metadata refusal/rollback, then applies the reviewed identical code with only the two metadata literals substituted. It does not infer or approve a new descriptor from the current database.

The genuine owner API initializes once with synthetic source `a` repeated64 and baseline `dfc7a4fafb696f73d207251c9f35cb892528eecd1929552fa575996874adc3e3`. The caller requires OPENepoch1, zero admissions/proofs/unknown obligations, exactly one initialization operation, no users/receipts/messages and Realtime disabled. It never invokes `test_schema.mjs`: those suites create their own admissions and would invalidate a pristine runtime witness.

The first child uses the explicitly supplied Deno binary with `--cached-only --frozen`, explicit maintained config/lock, `--allow-env`, read access restricted to this source tree and network permission only for `127.0.0.1:<port>`. It runs `scripts/supabase/emergency-fence/native-runtime.ts`. That witness retains its original17 runtime/SQL/config pins and enforces the actual held SMTP transport promise, ten-second consumer timeout, real sharedWORK/drain timeout, original unknown receipt preservation and finalFENCED with one retained unknown. Its97 application-table invariant excludes only its two exact owned synthetic rows.

The second child runs `member-realtime-native.mjs` with the current Node executable and its own fresh database. It deliberately seeds local synthetic Auth/app actors, memberships and messages. Its receipt must identify `new_unique_loopback_realtime_interface_only`, subsettrue, full_matrix_qualifiedfalse, provider_calls0, managed_project_writes0 and sb22Satisfiedfalse. The runtime witness's97-table unchanged assertion is not attributed to this subset. The parent never reports all member journeys or the complete Realtime matrix as passed.

Children receive only essential process settings, the selected driver, the explicit synthetic flag, optional physical Deno cache, and their single fixture URL. Proxy, loader, ambientPG, provider/Auth and unrelated credentials are not inherited. The parent installs an idle-error listener before every database connect; any such error poisons the invocation, stops further queries/setup/children and terminates a running child. It never reconnects or replays CREATE, initialize or a failed child.

Source pins cover exact00+10, the real shared loader/static descriptor/interface/metadata expression, both runners, original runtime files, Deno config/lock, package/lock and this caller. They are checked before/after each connection/child and around setup. Changing these inputs requires a new reviewed cohort. Deno executable parity is also checked around child execution. The hardcoded expected pins describe this reviewed ten-migration cohort; they are not permission to accept a later source automatically.

Setup and each witness are bounded at150seconds; version observation is bounded at5seconds. Child output is capped at64KiB per stream (version4KiB). Timeout/overflow/connection error triggers SIGTERM then SIGKILL after5seconds; death/reaping is observed only to a further bounded deadline. Unacknowledged death remains unconfirmed and never allows the next case. Connection closure has a bounded observation. Already dispatched work may remain unknown; no cleanup writes, repair, reset or DROP follow.

All successful/failed databases are preserved. A new private0700 OS temporary directory retains wx0600/fsynced plan, create/initialization/child intents and typed safe observations/results. Raw child stdout/stderr, PostgreSQL errors and assertion operands are never echoed or persisted. Only byte counts/hashes and validated safe scope fields are retained. A private failed refusal tree from the local test is also preserved. Check counts include invariant/pin loops and do not count separate user journeys.

The refusal suite executes no real driver, Deno runtime, network or successful native witness. It covers CLI URL/identity/argument/synthetic/Deno boundaries; missing maintained Deno config before executable dispatch; source refusal before connection; a mocked read-only identity observation that must not reach CREATE/setup; clean child environment; and refusal of Realtime acceptance overclaims. These tests do not replace actual native qualification.

This caller must be executed/reviewed on the coherent source before local qualification can be claimed. Neither its presence nor a local PASS establishes hosted policies/Broadcast delivery, fullRT matrix, Free hosted capacity, provider/device acceptance, managed-internal fencing/recovery, key custody, RPO/RTO, fullSB22/SB29 or cutover. Existing captured nine-migration witness evidence remains its own historical epoch.

## Existing CI consumer proposal

Add the refusal command to the existing `local-qualification` job after checkout/locked tooling. Run the native command after that job has explicitly warmed/validated Deno2.9.6's locked cache and created its isolated PG17 role profile. The workflow already supplies the explicit synthetic flag, driver and Deno paths. No package or workflow edit accompanies this proposal.

Derive the `/postgres` URL from the existing local fixture environment in memory. Never echo it. This step has no dependency on `test_schema.mjs` state and may follow the existing SQL suites because it creates two entirely new databases:

```yaml
- name: Verify two-fixture caller refusals without a database
  run: node --test scripts/supabase/testing/qualify-member-realtime-native.test.mjs
- name: Qualify pristine runtime and Realtime subset on two new retained databases
  run: |
    node --input-type=module <<'NODE'
    import {spawn} from 'node:child_process';
    const admin = new URL(process.env.COLLECT_TEST_PG_URL);
    admin.pathname = '/postgres';
    const child = spawn(process.execPath, ['scripts/supabase/testing/qualify-member-realtime-native.mjs'], {
      env: {...process.env, COLLECT_MEMBER_REALTIME_ADMIN_DATABASE_URL: admin.href},
      shell: false, stdio: 'inherit',
    });
    child.on('error', () => { process.exitCode = 1; });
    child.on('exit', code => { process.exitCode = code ?? 1; });
    NODE
```

Root/mainCI owner must integrate the actual coherent input cohort and supply an owner-controlled secure local environment. This document is a source-only proposal, not an executed CI or native result.
