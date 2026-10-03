# Private PostgreSQL archive admission proposal

This packet proposes a separate, bounded local-executable adapter and a four-file integration diff. `candidate5` is the final derivative; `candidate` through `candidate4` retain exact precursor bytes and their actual outcomes. It has not been promoted or run against PostgreSQL, Docker, Supabase, a provider, customer data, or production. It closes no readiness finding. The existing query/migration admission module, deployment controller, recovery comparators and all maintained files remain unchanged.

The proposed adapter accepts only exact PostgreSQL 17.6 client banners and numeric server version 170006. This is an engineering cohort to review, not a real approved compatibility matrix. Whole-file SHA bindings and review-reference strings do not authenticate a human reviewer or grant operation permission. No live approval, tool manifest or certificate was manufactured.

## Observed callsites and proposed scope

| Current boundary | Observation | Proposal |
| --- | --- | --- |
| `scripts/supabase_logical_backup.sh` | Explicit partial public-schema export, optional public data; currently selects an override, Homebrew or PATH client and permits any client major at least 17. | Replace discovery with an externally supplied archive manifest and operation binding; preserve the explicit partial-export confirmation, flags, help and exclusions. |
| `scripts/supabase_cli_helpers.sh` | Maintained psql admission and credential-file transport. | Add `collect_pg_archive`, `pg_dump_cli` and `pg_restore_cli`; retain every existing function. The new launcher requires an absolute caller-supplied Python executable. |
| `scripts/audits/collect_encrypted_database_backup.rb` | Full custom dump, optional exported worker snapshot, separate password-free `pg_dumpall`, encrypted vault, approved IP rule, TLS route, exact source contract, immutable local image and offline `pg_restore --list`. | Unchanged. A container adapter must preserve these contracts and authenticate the host/runtime/image plus actual clients and server. The new local API does not replace this route. |
| `scripts/tests/production_archive_restore.rb` | Isolated local container restore/decode and strict source/data/schema/ACL/roles comparisons; optional worker comparison. | Unchanged. These comparators remain necessary for recovery acceptance. |
| `scripts/qa/backend_release_delivery.py` | Approval operations cover migration, retired functions, Edge functions and strict readiness. | Unchanged. Its existing approval does not authorize backup or restore. |
| Hosted restore | No maintained hosted-target restore controller was found in the inspected shipping boundaries. | The new API rejects hosted restore before any executable runs. Only a separately bound local rehearsal restore is supported by the prototype. |

The full encrypted-backup image is `sha256:3f8ad1de081c241b0ed59468590ed789453f352daeff3bc4dff2b169b3bbf43a`. Its container, exported-snapshot and global-role paths remain separate open integration gaps. The Makefile backup command still lacks the explicit confirmation and therefore retains its default refusal; this proposal does not silently authorize it.

## Proposed behavior

The manifest binds the new adapter bytes, exact unchanged base admission bytes, absolute psql/dump/restore paths and hashes, exact 17.6 versions, profiles, numeric server cohort, finite artifact limit, and a root-certificate file for hosted capture. The separately hashed operation binds target, source bytes, validity window, profiles, output directory and any restore input and capture receipt. Unknown fields, duplicate keys, substitutes, symlink/hardlink clients, drift and argument overrides are refused.

Version probes receive a credential-free local environment. Immediately before capture or restore, the adapter rechecks tool, manifest, source, certificate and operation identities, executes a read-only target-bound numeric server query, and re-observes all three actual client banners. The first remote observation is that query. The adapter cannot prove the server version before its first remote read, or make the query and subsequent client connection one atomic observation.

Capture writes an exclusive owner-only artifact under a private owned directory, drains stdout/stderr within a monotonic deadline and byte limits, refuses warnings, and records a private receipt. Restore pins the custom archive and its original capture receipt, keeps the admitted inode open as stdin, runs an offline TOC listing, reads the exact target server version, and executes only the fixed single-transaction local restore command. A returned client receipt expressly marks full recovery, source-contract semantics, human approval, encrypted destination and production acceptance false.

The final runner also refuses a successful parent that leaves a residual process group, kills/reaps within the original five-second cleanup bound and verifies absence, and refuses completion after its monotonic deadline including delayed stream closure. SIGKILL EPERM can be cleared only by bounded parent reaping plus verified absence of the entire group; a surviving group keeps the signal error fatal. A client completion cannot disguise failed cleanup.

PostgreSQL documents custom archives as an input to `pg_restore`, and notes that a single-database dump does not include global roles and that selected-schema dumps can omit dependencies. The partial export keeps those limitations visible. [PostgreSQL 17 pg_dump](https://www.postgresql.org/docs/17/app-pgdump.html)

The restore proposal uses stdin, an offline archive listing and a fixed single-transaction invocation as documented by PostgreSQL. The listing does not make archive SQL trusted. [PostgreSQL 17 pg_restore](https://www.postgresql.org/docs/17/app-pgrestore.html)

Connection passwords remain in explicit owner-only files, outside argv and local version environments; HOME password fallback is disabled. [PostgreSQL password files](https://www.postgresql.org/docs/17/libpq-pgpass.html)

## Actual validation, including failures

| Receipt | Actual outcome | Scope |
| --- | --- | --- |
| `attempt1/result.json` | **23/25 passed; 2 setup version timeouts; failed** in 33.005963 s | Initial 25 genuine process/stdio cases. No request occurred in either setup timeout. |
| `attempt2/result.json` | **5/5 passed** in 6.931195 s | The two affected timeout cases and three added helper/CLI/path-consumer cases. |
| `attempt3/result.json` | **27/28 passed; 1 setup version timeout; failed** in 41.011136 s | Exact final 28-case archive/consumer cohort, with safe call and receipt traces. |
| `attempt4/result.json` | **2/2 passed** in 2.596513 s | Only the two newly added hosted TLS/certificate-drift cases, using synthetic executables and certificates. |
| `successor-attempt1/result.json` | **3/7 passed; 2 failures + 2 errors; failed** in 8.788081 s | Candidate2 residual-group/deadline and directly affected consumers. Four consumer bodies were stopped before the requested behavior by setup version timeouts. |
| `successor-attempt2/result.json` | **4/5 passed; 1 error; failed** in 2.838960 s | Candidate3 direct runner checks. Immediate stdout overflow encountered SIGKILL EPERM before parent reaping; warning/timeout branches were not reached. |
| `successor-attempt3/result.json` | **2/3 passed; 1 error; failed** in 0.772868 s | Candidate4 cleanup correction still encountered that EPERM race. Live-group permission refusal and detached-stdio group cleanup passed. |
| `final-latest-attempt1/result.json` | **36/36 passed** in 43.677043 s | Exact candidate5 full affected cohort after runner correction and independent native termination; unchanged one-second fixture bounds. |
| `original-partial-contract/result.json` | **3 runs, 25 assertions, no failure/error** in 0.144069 s | Byte-identical original partial-export help/default-refusal/unknown-argument tests against the derivative script. |

The final candidate5 full affected cohort passed all 36 cases. Every precursor failure remains failed, including the 28-case 27/28 cohort. It is not reclassified by the narrower successful checks. Its failed wrong-service case timed out in the unchanged base psql version probe, before the test body or any database request. The same negative body passed in attempt1 and in the exact final candidate5 full run; `semantic-reuse.json` binds that method, its fixture and candidate1’s unchanged non-CLI API AST relative to attempt1. `final-preservation.json` separately binds the unchanged admission class and test bodies across the runner correction. The exact fixture shebang already selected the pinned Python 3.12.14 executable; no PATH or `/usr/bin/env python3` repair applies. The one-second bound was preserved. No load/filesystem cause was proved and no unchanged broad retry was run. Root subsequently authorized one full final affected cohort after both a concrete runner correction and the independent native process becoming terminal. See `fixture-timeout-diagnosis.json`.

Every actual outer process completed and its owned process group was absent. Each archive-focused attempt records exact argv, UTF-8 clean caller environment, before/after candidate and maintained hashes, stdout/stderr hashes, deadline and elapsed time. The original Ruby receipt records its exact original test bytes, execution inputs and outcome. Safe traces contain synthetic metadata only, with no password/service files, raw archives, customer rows or real approval values. Reconstructed attempt1/attempt3 inputs are explicitly labeled; their exact bytes match the original contemporaneous receipts. Attempt2 and attempt4 input copies are separately labeled post-run captures.

`original-inputs-after.json` confirms all 19 maintained file hashes, sizes and modes remain equal to the initial capture, including all original **28 admission + 45 delivery + 5 secret-transport method ASTs**. The copied base module, dotenv loader and original three-test Ruby contract are byte-identical. Unchanged original suites were not rerun.

The independent ordinary recovery5 result is reused with exact packet/result/readback hashes: 27/27 passed in 301.559782 s under its unchanged 600/540/60 bounds, strict predecessor restore, 85 ordinary forward migrations, final 209 catalog/ACL and 18 projection checks. This is a distinct synthetic local recovery milestone. The new adapter did not execute those comparators and does not inherit their recovery acceptance.

## Remaining gates and limitations

- Real protected operation approval, actual shipping compatibility review, provider permission and current hosted runtime acceptance remain external gates. Metadata hashes are bindings only.
- Hosted restore is explicitly absent. Full encrypted capture, worker exported snapshots, global roles, Supabase embedded-client provenance and container adapters are not integrated by this patch.
- The new `source_binding` pins opaque source bytes. It does not replace `CollectRecoverySource` validation or invoke the existing strict catalog, effective ACL, roles, data, worker and projection comparators. Its recovery-accepted fields stay false.
- The new helper requires an absolute Python launcher but does not attest the Python runtime, OS, dynamic-loader dependencies or executable race-free launching. Their provenance must be reviewed separately. File hashes alone do not attest execution dependencies.
- Capture streams to disk, but subsequent archive hashing/admission uses the base bounded file reader and can materialize an artifact up to 1 GiB in memory. Large-archive resource acceptance remains open. Strict 0700/0600 behavior also requires a filesystem capable of preserving these permissions.
- Client completion does not establish encrypted destination custody, complete backend/system recovery, production signing, application artifacts or release readiness. BE-08/BE-09/ARC-08/ARC-11 remain open; production remains NO-GO.

Root review is required before any promotion or shipping execution. `integration.diff` is the exact proposed four-file change, with baseline and candidate hashes in `diff-inputs.json`; supporting copies are not proposed maintained changes. `runner-successor.diff` isolates the narrowly reviewed group/deadline/cleanup correction from candidate1 to final candidate5. `final-preservation.json` proves every precursor test body remained intact and the admission class is unchanged.
