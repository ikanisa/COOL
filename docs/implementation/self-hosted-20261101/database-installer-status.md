# Actual fresh-installer qualification

The maintained `DatabaseInstaller` executed against a fresh owned PostgreSQL17
cluster on loopback55447. It used a normal `postgres` owner with `CREATEROLE`,
without superuser/BYPASSRLS/inherited runtime privileges. Docker SQL transport
was explicitly replaced by native `psql`; native Auth/Realtime interface tables
were synthetic. No production database, external provider or existing cluster
was changed.

The first attempt stopped at SQL11 because the wrapper accepted `BEGIN;` but
did not recognize the original `BEGIN ISOLATION LEVEL READ COMMITTED READ WRITE;`
declaration. The wrapper now admits that exact declaration. The original16
migration files remain byte-identical. The failed receipt is preserved as
`database-installer-attempt1-result.json`.

The second fresh invocation passed six scenarios, recorded with complete source
pins in `database-installer-attempt2-result.json`:

1. All nine foundation migrations commit with their real installation receipts;
   a matching retry applies no duplicate migration.
2. A platform binding for the wrong profile is refused before the next migration.
3. The complete24 chain executes with transaction-bound source/rendered receipts;
   exact completion retry is a readback.
4. The original initialization UUID is accepted on readback; another UUID is refused.
5. Owner attempts to update, delete or truncate the journal fail and retain24 receipts.
6. A receipt conflict rolls back its accompanying real DDL in the same transaction.

The qualification helper is
`python -m scripts.self_hosted.qualify_database_installation`. It requires an
explicit synthetic flag, exact native toolchain, fresh private directory and
fresh receipt path. It only creates/stops its own fixed-port cluster. Both
attempts stopped their owned cluster; private credentials and raw diagnostics
remain private. The synthetic SQL10 review record is test-only and declares
production approval false. It cannot authorize a real platform catalog.

This closes a concrete fresh-installer implementation defect and verifies its
transaction/retry behavior. It does not prove the complete Docker stack,
actual managed-service catalog, physical restore, current production data
migration, provider delivery or release admission.

## Final complete chain

`database-installer-final-result.json` is a fresh invocation after the exact
gateway-fence migration25 was admitted. All six scenarios passed against all25
reviewed migration bytes, including the complete immutable installation journal,
exact retry, original initialization UUID, journal tamper refusal and rollback
of DDL on a conflicting receipt. The helper obtains the expected count from the
exact digest-checked deployment lock, rather than retaining a numeric24 branch.
The fixture used a newly created private directory and stopped its own55447
cluster. The earlier two attempts remain unchanged; they are not relabeled as
current25. Docker transport and native Auth/Realtime remain explicitly synthetic
boundaries in this final run as well.
