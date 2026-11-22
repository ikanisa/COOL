# Receipt worker history storage and recovery

Migration `20261002070000_receipt_worker_history_storage.sql` removes admitted immutable payloads from five original operational rows into private logged PostgreSQL cold payloads in the same transaction. Original UUIDs, keys, metadata, FKs, quota counters and expiration evidence remain in their original relations. This is a logical storage boundary in the same database; it does not establish a separate hosting tier, capacity savings or page reclamation.

The five families are historical worker configuration, worker receipts, scan receipts, transport reconciliation receipts and typed transport observations. Exact UTF-8 JSONB text, payload SHA/length, metadata SHA and complete logical preimage SHA bind each original. New original INSERTs capture a binding atomically. Existing hot originals bind lazily under their exact row lock. No historical payload backfill occurs during installation.

Only an exact inline-to-certified-cold transition is allowed. Original DELETE/TRUNCATE, arbitrary UPDATE, metadata mutation, reverse relocation and cold object mutation are refused. The global immutable evidence function stays unchanged. All private history tables/functions remain denied to PUBLIC, anon, authenticated and service_role. There is no MCP or sender authority addition.

## Owner preparation and bounded maintenance

The actual cron owner API is `collect_receipt_worker_history.prepare(expected_revision, enabled, batch_limit, byte_limit)`. The shipping default is disabled, batch10 and byte cap4194304. On the unchanged installation, `prepare(1,false,10,4194304)` creates job `collect-receipt-history-maintenance` with schedule `* * * * *`, command `select collect_receipt_worker_history.run_schedule();`, database postgres and creator/runner postgres, **inactive**. The expected revision is checked before any change; use the current exact configuration revision for subsequent owner changes. No direct cron-table DML is needed.

Activation is a separately governed deployment/configuration action. The API creates/updates only this job. Worker, telemetry, network and sender gates remain their distinct controls. Restoring the database must leave both worker and maintenance schedules inactive until the normal release recovery checks authorize them.

`maintain(original_request_uuid, limit, original_expires_at)` is the bounded owner workflow. It accepts limit1..25 and an expiration no more than120seconds ahead, READ COMMITTED only. Each request moves at most the configured4MiB cap; an individual payload above1MiB and any unprovable/held graph stay hot. Exact worker-plus-embedded-scan payloads relocate together. Related-set probes refuse above32; this is not a total32 graph bound.

A fresh request returns inactive without recording work while disabled. A held candidate records HELD, SOURCE_BUSY or BYTE_LIMIT and moves zero bytes. Integrity uncertainty returns INTEGRITY_REQUIRED without fabricated absence or business acknowledgement. A processed maintenance receipt records physical candidates, not financial/delivery completion; source_scan_complete, financial_action and send_action remain false. Cursor rollover repeats earlier held keys. Interruption before commit rolls back bindings/objects/certificates/inline removal together.

Replay requires the original UUID, limit and expiration. Changed inputs conflict; an expired invocation is refused even for a known maintenance UUID. For a lost response, an authorized owner can read the original immutable history request and call `verify_recorded(result)`; preserve the original receipt and investigate an integrity failure. Never change the UUID/deadline merely to convert an uncertain outcome into a claimed result. Ordinary original worker/scan/transport APIs retain their established known-UUID recovery semantics.

## Holds and concurrency

Retention relies on actual immutable handled-event/handled-backlog or strict immutable supersession evidence and the protected source graph. Pending or live source work, uncertain/active transport, active exceptions, unfinished workflows, queued/unavailable escalation, unread inbox and relevant telemetry prevent relocation. Any immutable successor approval or materialized job tied to an original root remains a permanent conservative hold, including after revocation or archive ACK. ACK is not delivery finality.

Maintenance uses candidate subtransactions and TRY/NOWAIT acquisition, with later reads/FKs capped by200ms lock_timeout. Its gate order is private request/maintenance, trusted worker, sorted exact worker jobs, combined roster, workflow, sorted scan requests, scanner, transport reconciliation, sorted transport requests, telemetry sampler, exact source admission, payment/original roots UPDATE NOWAIT plus parsed/raw SHARE NOWAIT, then sorted exception-source gates. Refusal rolls back partial candidate locks and changes.

Certificates describe protected facts at publication time. An original producer may append independent pending work after the last graph check while source admission is held; that durable original work survives, and the shipping500 scanner re-admits it before refresh. The history certificate makes no claim about future source or transport quiescence. Financial producers acquire no new global lock.

## Complete database recovery seam

Back up the complete original relations plus the entire private history schema, owners, ACLs, triggers, indexes, FKs, configuration, progress and requests. A metadata-only journal backup omits the required cold evidence. The existing full database backup boundary remains the owning recovery integration.

Owner-only `inventory_page(after_family, after_key, 1..25)` reconstructs each original across hot/cold, including legacy unbound hot rows, returning its exact logical SHA, binding and tier. Advance the returned pair until checked=0 and both cursor values are null. It also includes dangling binding keys so corruption cannot disappear as an empty page. `verify_page(captured_page)` rejects unavailable original keys or changed logical bytes. Capture and compare fresh restored pages as well, including binding/tier fields. Do not replace unavailable measurements with zero.

`object_inventory_page(after_sha256, 1..25)` checks all durable object SHA/bytes, including objects no longer selected by an anchor; advance until checked=0 and last_sha256 is null. `verify_object_page(captured_page)` verifies those exact objects after restore. Both object and logical inventories are required.

For a live backup, capture pages and the full dump in one exported read-only REPEATABLE READ snapshot, bind pg_dump --snapshot to it, and retain the snapshot until both complete. Stop/overlay and native/scheduler stores remain separate root-owned recovery boundaries. The private proof used a quiescent isolated source, so it does not prove concurrent unified capture by itself.

Known original UUIDs with missing/conflicting cold bytes raise55000 receipt_worker_history_integrity through original SQL readers. Existing Edge handlers return their outcome-unknown/lookup-unavailable boundary and perform no blind retry; Admin uses its RPC failure state. A corrupt cold store must never become not_recorded, zero health or fabricated completion.

## Scoped local acceptance

Final private proof sql-attempt12 applied nine additional real definitions plus exact430/500/corrected600/700 over a retained192-source checkpoint. Its60 SQL checks passed. Separately,7 healthy and6 known-cold-failure checks used the real Edge handler connected to isolated SQL;14 checks decoded actual SQL through unchanged strict models.597 main command receipts and418 captured source/tool inputs are retained unchanged.

The isolated full dump/restore recovered2,042 original logical records, including2,032 hot and10 cold, and all10 objects. The actual captured source GraphQL wrapper definition/owner/ACL/nonmember dependency was reproduced after declared fresh managed-image normalization. Both maintenance and worker schedules remained inactive, network/cron runners disabled, and owned containers were removed. The ordinary application installer was NOSUPERUSER but retained CREATEDB/CREATEROLE/BYPASSRLS. Synthetic JWT/session/Vault inputs establish no hosted authentication or cryptographic parity.

Canonical review/promotion, refreshed full candidate replay, actual Admin SDK/widget acceptance, unified database/native/scheduler snapshot capture and drills, future800 compatibility, hosted operation, Android/device/provider tests and release acceptance remain separate requirements.
