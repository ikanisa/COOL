# V3 capture-session closure: owned-fixture candidate

This narrow successor addresses an interrupted capture whose local worker
has exited while its PostgreSQL backend still holds a WORK lock. It does not
apply a migration. `managedCaptureV3` is hard refused before reading a secret;
there is no qualified live managed dispatch or managed reconciliation adapter
in this directory. The prior v2 candidate and evidence remain preserved under
`../frozen-v2/`. No test accesses the actual local application service, real
credentials, Supabase or a provider.

The owned-fixture path first verifies an externally pinned source/tool
manifest and creates a private, one-use `active-capture` intent with a random
operation ID and unique application name. A supervisor binds the actual spawned
child before providing worker input. The worker opens one fixture PostgreSQL
session, reads its PID, backend start, system identifier, postmaster start,
database, role and operation name, and fsyncs that backend record **before**
acquiring a WORK or migration lock. If any intent, actor or backend record is
missing or ambiguous, the result remains unknown and no automatic retry is
permitted under the trusted root.

The actor-closure receipt is created only by the original tracked-child
supervisor after it receives the child's actual close event and observes the
owned process group absent twice. A missing receipt after a supervisor crash is
not replaced by guessing from a PID. This is not an OS guarantee about escaped
descendants, host failure, process inspection or hostile same-user changes;
the protected source, journal and single-actor boundary remain assumptions.

Read-only reconciliation requires the matching manifest, operation, actor,
backend and actor-closure records. It opens two independent fresh connections
and read-only transactions, requires `pg_read_all_stats` visibility or an
equivalent superuser privilege, verifies the original cluster/postmaster,
database and role, explicitly clears the PostgreSQL statistics snapshot before
each activity/lock read, and checks that neither the recorded PID nor the
unique application name appears and that the PID has no locks. A live or
reused PID, name collision, changed/inaccessible cluster, missing actor proof,
incomplete observation or different backend is unknown. A successful result is
only a bounded observation under trusted endpoint-routing and no-escaped-actor
assumptions; a cloned cluster, compromised runtime or later independent actor
is not excluded. The old intent remains in place even after reconciliation.

The source verifier itself runs after the operating system, Node, loader and
some modules have already started; those remain trusted. The manifest hash
must be supplied from independently reviewed protected evidence. The
fixture-only client callback is trusted test code and is not a production
security boundary. A hung asynchronous connection is treated as unknown at the
deadline; an event-loop or filesystem stall still needs an outer process
supervisor. A real successor still needs a fixed managed TLS adapter,
private credential/supervisor workflow, independently reviewed source and
source-manifest pin, bounded cancellation and actor/connection recovery across
supervisor failure, and the separately qualified post-sixteen fence and data
preimage. Managed apply and its migration reconciliation remain closed.

Run the owned PostgreSQL 17 tests from the physical checkout:

```sh
env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin LC_ALL=C \
  /Volumes/PRO-G40/Development/Node/bin/node --test --test-concurrency=1 \
  scripts/supabase/managed-archive-operator/v3/*.test.mjs
```
