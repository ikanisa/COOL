# Managed identity: provider-role compatibility experiment

This directory contains a **synthetic-only** experiment, not a migration or a
production deployment tool. Its generator has no database, credential, CLI or
network dispatch; `executeManaged()` always refuses. Generated SQL has an
additional first-statement guard for the randomly named local fixture database,
its synthetic cluster name and a Unix-socket connection. That guard is a
mistake-prevention measure, not a defense against a hostile administrator who
controls the database or the test host. The existing binder, migration history,
provider-managed roles and real data are unchanged.

## Current project observations and prerequisites

Read-only catalogue queries to project `rrlduytparvsjfmegalh` on 2026-11-14
showed 14 history entries, ending at `20261023174000`. The fence predecessor
`20261022195747` was present with the expected single-statement SHA-256
`714abf2d24ce3d42a36525d18627362b02ff38c30810e988d365b5796d840497`.
The admission-archive predecessor `20261101012309`, identity predecessor
`20261101013157`, the identity table and the managed binder were absent. The
existing managed binder's installation precondition therefore cannot presently
hold. This is a catalogue inference; no installation was attempted.

The original scheduler function's source SHA-256 was
`5dc44f65fb52562bc6a0391a7f7b7d050c333c2276f98097943d9c1e340d926d`,
and its owner, language, security-definer, volatility, strictness, return type,
search path and ACL matched the current candidate's full predicate. The
`pg_cron` and `pg_net` extensions and their relevant relations existed; the
named Google expiry job was inactive. `collect_ops` contained only its guarded
expiry routine; jobs/email configuration and dispatch tables were absent. This
does **not** establish an empty HTTP queue, completed work, scheduler readiness,
or a writer fence. The scheduler body checks more than these catalogue facts.
The later email bootstrap replaces the scheduler body, so the original hash
cannot be treated as a permanent pin: any later scheduler variant needs its own
exact rendered preimage, coverage, ACL and concurrency qualification.

The two Admin MFA WIP versions `20261114110100` and `20261114110300` are not
being added to production history. The separate deferred-MFA fixture models an
ordered path that omits them while identifying distinct managed identity and
stopped-admission blockers. It is not proof the hosted chain has run or that
either blocker has been resolved.

## Administrative trust boundary

The current direct membership was `cli_login_postgres` -> `postgres`, granted by
`supabase_admin` with SET true, INHERIT false and ADMIN false. The CLI role was
login-capable, non-superuser, NOINHERIT, without CREATEDB, CREATEROLE,
REPLICATION or BYPASSRLS, and had no other direct memberships in the fresh
catalogue result. No non-superuser role had a membership path to a superuser in
that read. Exact role and membership OIDs were observed but must be freshly
retrieved; they are lifecycle-specific, can change, and are not embedded here.
Password expiry was not used as proof that a role, credential or session is
absent. The provider may refresh its own login role and credentials.

Supabase describes this as a provider-managed CLI login role for temporary
database access in its [role knowledge base](https://supabase.com/kb/troubleshooting/permission-denied-when-deleting-the-cli_login_postgres-role-808bae),
and documents [provider-granted role memberships](https://supabase.com/kb/troubleshooting/cant-revoke-a-role-membership-granted-by-supabase_admin-d08922).
The [CLI's login-role source](https://github.com/supabase/cli/blob/develop/apps/cli-go/internal/utils/flags/db_url.go)
shows the passwordless administrative flow. PostgreSQL distinguishes
membership from immediately inherited privileges and from SET ability in its
[role-information functions](https://www.postgresql.org/docs/17/functions-info.html).
These references do not establish whether any particular session is active or
whether its operator is trustworthy.

The experiment accepts the exact, freshly captured direct provider role edge
only under the explicit assumption that provider administrators, issued
administrative credentials and their sessions, other superusers and all other
non-cooperating owner-level actors are trusted and operationally controlled.
It rejects changed role attributes, membership OID/grantor/options, additional
CLI memberships, non-superuser membership paths to the owner or CLI role, and
non-superuser paths to any superuser. It keeps the original effective-function
ACL, predecessor, identity, scheduler, lock and session checks. This does not
enumerate every possible administrative capability, resolve outstanding
effects, or itself exclude concurrent DDL, management actions or new sessions.
Where the operator cannot establish the trust and exclusion assumptions, retain
the original restrictive membership guard.

An owned fixture demonstrates the material distinction: a session logged in as
`cli_login_postgres` can `SET ROLE postgres` and alter an owner function in a
rolled-back transaction. Nevertheless, the unchanged identity predecessor and
managed binding function reject it because `session_user` remains the CLI
login, even though `current_user` becomes `postgres`. Thus this compatibility
model does not solve the separate need for a qualified production execution
path with the required session identity. A catalogue SELECT observed as
`session_user = postgres` does not establish the correctness or safety of a
future mutating execution path.

## Synthetic verification

Run only in the reviewed local environment:

```sh
cd '/Volumes/COLLECT-STAGING-20261109/main-source'
/usr/bin/env -i PATH=/usr/bin:/bin LANG=C \
  '/Volumes/PRO-G40/Development/Node/bin/node' --test \
  scripts/supabase/managed-identity-provider-compat/synthetic-provider-binder.test.mjs
```

The fixture creates a new, socket-only PostgreSQL 17 child and invented roles,
history and rows, then confirms owned child shutdown and scratch removal. It
records the two absent predecessor statements as synthetic history while
installing only the synthetic identity subset: this deliberately avoids claiming
a tested complete migration chain. The source transformation requires an exact
original binder hash, a unique expected guard, a deliberate trust string, a
randomly named synthetic database and freshly read fixture OIDs. Tests cover
original refusal, the trust exception, same-operation repeat, synthetic account
preservation, runtime and CLI restrictions, privileged CLI DDL, membership and
attribute drift, scheduler drift, active/uncertain work, wrong source and
hard-refused managed dispatch. The synthetic scheduler is materially simpler
than the hosted operational system.

`SYNTHETIC-SOURCE-PINS.json` is a review inventory, not release authority. The
fixture checks the four local PostgreSQL launchers **and** the four wrapped
executables before and after use. The Node binary, modules, launcher, shared
libraries, OS and loader must still be trusted; in-process checks cannot defend
against code injected before they run. No real account, queue or admission data
are read or changed by these tests.
