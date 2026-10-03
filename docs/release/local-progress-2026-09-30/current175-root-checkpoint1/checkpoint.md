# Current local integration checkpoint — 1 October 2026

## Ordinary installer migration replay

All 175 current migrations replayed in both clean and populated task-owned, networkless containers. The populated fixture began at the retained 124-version boundary using synthetic data. All 51 subsequent migrations preserved 18 financial, receipt, Auth and approval projections. The result contains 32 passing acceptance checks, 350 recorded migration executions, ordinary installer attributes before/after every application migration, no active cron launches, network dispatch or cron history, and both containers removed.

The installer was postgres with NOSUPERUSER and no direct cron.job write privileges. Its retained managed-image CREATEDB, CREATEROLE and BYPASSRLS attributes are explicitly recorded; this is not a low-privilege end-user test. Privileged platform setup precedes application migration 1 and installs the retained Auth/storage shape. Hosted role, Auth-provider and storage-runtime parity remain unverified.

Two failures were retained and corrected in the test platform setup:

1. pg_cron was installed under postgres before demotion, while cron.job belonged to supabase_admin. Installing the extension under the managed table owner made actual schedule/unschedule owner API calls pass without installer table DML.
2. A newly created extension did not reproduce the retained platform's postgres EXECUTE permission on cron.alter_job. Actual quiet154 readback proved that prerequisite exists and is denied to anon/authenticated. The isolated setup grants only this function's execution to postgres. No shared database grant or application migration was changed.

## Admin receipt and policy acceptance

The current receipt/policy/preference export passed 238 tests, zero failures/errors/skips, four actual Chrome checkpoint cases and fatal analysis. All 972 captured source inputs, exported sources and locked SDK inputs were unchanged. The suite exercises the saved receipt session/identity equality fix, private-provider refusals, exact SDK bearer/target, pending authority changes, cancellation checkpoint ordering, matching acknowledgements, uncertain transport/malformed/mismatched/503 outcomes, late departed-session results, policy expiry/permission/refresh and notification preference recovery.

One failed test expected the post-cancellation refresh HTTP request immediately after the success callback. The preserved production code invalidates the provider and schedules that read for a frame. The test now waits within its existing bound for the actual second HTTP request. Its exact two-request assertion and checkpoint/privacy/uncertainty expectations remain intact; the production refresh behavior was unchanged.

Archived synthetic SQL documents are decoder inputs in this client suite. It does not execute current SQL, verify provider truth, certify persisted audit delivery or prove complete Admin/PWA/Revolut fidelity.

## Remaining work

The register was refreshed with fresh quiet154/153-table readback, exact175-source/21-staged inventory, current scoped results and retained failures. All 24 local and 102 original production criteria remain unchanged. Six local groups remain closed; the 18 pending groups require their complete acceptance.

The same-dataset 1,000/10,000-row baseline/index/seek comparison is running in a synthetic schema/ACL clone. Candidate files are not published migrations. No benefit or final current query acceptance is claimed before authoritative completion. Final common-source native builds, full Admin/browser coverage, current compatibility/rollback/full suites and reproducible handover still require evidence.

See `evidence-index.json` for exact packet hashes.
