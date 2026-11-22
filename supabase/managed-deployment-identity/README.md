# Managed deployment identity

`bind-managed.sql` is an **uninstalled candidate**, not a versioned migration
or authorization to change a live database. It adds a separate owner-only
binding for the managed production profile. The existing self-hosted binder,
immutable identity and runtime assertion remain in place. An existing identity
cannot be converted or overwritten by this candidate.

For a first binding, the caller supplies the profile and its SHA-256, plus the
exact fenced controller operation, epoch and source SHA-256. The candidate
requires the expected project and baseline, settled admissions without
uncertainty, and the predecessor scheduler check to report no blocking work.
Null or missing values fail closed. It obtains the migration-history, work and
write advisory locks and locks the identity table before rechecking. The
predecessor scheduler function body and security attributes are pinned; the
owner role and effective managed-function privileges are also checked. A
new operation or profile cannot replace an existing identity. Repeating the
same operation and profile returns success only while all pinned preimages still
match; that read-only repeat does **not** attest that the supplied fence token
is still current or that the controller is still fenced.

**Known email-scheduler incompatibility:** this candidate pins only the
original `private._collect_fence_scheduler_status()` body. The owner-only
`supabase/jobs/email-bootstrap.sql` replaces it with a rendered dual-lane
scheduler inventory, and `supabase/jobs/EMAIL.md` orders deployment identity
binding before email installation. After that replacement, this candidate
rejects even a same-operation repeat with
`managed_deployment_scheduler_preimage`. Before using it after email
installation, separately review the actual rendered scheduler variant and its
function, dependency and catalogue preimages, then adapt and requalify the
candidate. Do not remove or weaken the existing pin merely to permit a repeat.
This documented incompatibility does not establish the current cloud state or
qualify either scheduler variant for production.

The candidate requires exact `version`, `name`, a single recorded statement,
and the full UTF-8 `statements[1]` SHA-256 for these predecessors:

| Migration | Source byte SHA-256 |
| --- | --- |
| `20261022195747_collect_application_mutation_fence.sql` | `714abf2d24ce3d42a36525d18627362b02ff38c30810e988d365b5796d840497` |
| `20261101012309_collect_admission_archive.sql` | `82b09d4d2abd5994429a978ccf80daa796fd83e5dc5d29bc54076f2b7565ad84` |
| `20261101013157_collect_deployment_identity.sql` | `916a7b3012135484c74f0a6b4707cdda39c637959f8564233fc8f6a8f5adbdc1` |

These checks do not verify the complete ordered migration history or prove
that the recorded SQL ran correctly. They do not cover the separate
`20261113130900_burimunsi_native_sms_posting.sql` migration. That shared file
is changing in another task and its hash is **not** a release input here.
Once the other task stops editing, freeze the full migration inputs; compare
the complete ordered history, names and statement bytes against the approved
source and lock manifest; resolve any mismatch; and rerun the affected tests.
If one of the three predecessor source files above has changed, review the
change and dependencies, update its pin and affected function/catalogue
preimage in this candidate, and rerun its tests before considering installation.
Do not repin the actively changing shared migration merely to make a check pass.

Before any real installation or binding, independently qualify the actual
managed endpoint and owner privileges, all predecessor ordering and catalogue
preimages, scheduler dependencies, active work and fence transition, and
exclude non-cooperating migration or schema actors. The locks cannot exclude
actors that ignore the protocol. The SQL checks the public callback **origin**
belongs to the supplied member or admin origin; it does not verify provider
registration or a working OAuth callback. The candidate does not map or merge
accounts, validate the same-person decision, migrate data or change the
cloud-primary account. Those are separate operations and proof obligations.

The SQL uses five-second lock and 60-second installation statement timeouts;
the caller still needs a bounded overall deadline and unknown-commit
reconciliation. The SQL accepts ASCII domain labels and rejects `xn--` labels
because it does not implement the runtime's IDNA rules. Enabling an explicit
managed profile before its matching database identity is installed and bound
will cause the runtime to fail closed.

Run the focused tests from the repository root, with the pinned
`scripts/supabase` dependencies installed and PostgreSQL 17 binaries available:

```sh
node --test --test-concurrency=1 supabase/managed-deployment-identity/bind-managed.test.mjs supabase/managed-deployment-identity/bind-managed-pg17.test.mjs
node --test supabase/functions/_shared/tests/deployment-database.test.mjs
```

The tests use PGlite and an owned, synthetic, private-socket native PG17
cluster. The native fixture uses a non-superuser `postgres` with `BYPASSRLS`,
executes the real identity migration and scheduler function, and models a
cloud-primary principal. Its recorded predecessor history and fence tables are
synthetic: it does not execute the complete predecessor chain or qualify
Supabase-managed privileges, provider isolation, a real account or production
cutover. No production installation or binding is established by these tests.
