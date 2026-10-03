# Collect manual shadow supervisor v1

These contracts describe local candidate migration `20260930210000_shadow_supervisor_runs.sql`; they do not assert deployment, Codex execution, provider configuration or delivery. The accompanying fixtures are synthetic responses, derived from the existing redacted operational-health fixture. Their hand-authored lifecycle digest is explicitly a placeholder, not persisted evidence. `collect-shadow-supervisor-v1.observed.fixture.json` instead captures the actual history result from the final isolated89-case UAT; backend-uat receipts and provenance are stored under `docs/release/collect-codex-shadow-2026-09-30`.

All five RPCs use the authenticated user's JWT, a live confirmed Auth session, current WhatsApp approval, a current `platform_owner` grant, and both `system_health.read` and `notifications.read`. Authority is locked in Auth/session, roster, grant/permission, lease order. No service-role grant, direct table access, delegated actor, country or tenant input exists. Scope is server-derived `collect_platform`. History is readable by any currently qualified platform owner; request lookup is limited to its original actor. Neither read exposes actor/session IDs.

| RPC | JSON request | Response definition |
| --- | --- | --- |
| `begin_collect_shadow_run_v1` | `{ "p_request_id": "UUID" }` | `begin` or `busy` |
| `sample_collect_shadow_run_v1` | `{ "p_run_id": "UUID", "p_fence_version": 1 }` | `sample_result` |
| `finish_collect_shadow_run_v1` | `{ "p_run_id": "UUID", "p_fence_version": 1 }` | `finish` |
| `get_collect_shadow_run_v1` | `{ "p_request_id": "UUID" }` | `get` |
| `list_collect_shadow_runs_v1` | `{ "p_limit": 20, "p_before_started_at": null, "p_before_run_id": null }` | `history` |

UUIDs may be any PostgreSQL UUID, not only version4. History limit is1..50; cursor fields are both null or both present. Dates are finite UTC-compatible timestamps. Pagination orders descending `(started_at,id)`, selecting strictly less than the cursor pair. `next_cursor`, when present, equals the last returned row and means an extra row was observed. `total` is the global history count at the read, independent of cursor. No offset API exists.

A single global lease lasts exactly120 seconds and cannot renew. A physical singleton-row write serializes begin decisions; fencing is monotonic1..1000000000, stopping before overflow. There are at most60 new runs per rolling hour. An existing request is never silently restarted: replay requires its original actor and session even after expiry/completion. A new session may only read the original actor's request for reconciliation. An active competing lease returns `busy` without revealing its token. An expired run cannot be sampled/completed. Later lease acquisition cannot be cleared by an old run. Completed replay returns its durable result only to the original current-authorized session and does not change a newer lease.

One immutable sample stores the actual `admin_system_health` v1 result plus assisted-SMS aggregates queried on the server. Sampling requires Read Committed,13 valid alert states and a valid source `checked_at`/`sample_valid_until` pair, exactly60 seconds apart. Source health must be generated during this run and remain fresh at persisted sampling, sample replay, and initial completion. A stale source is refused; telemetry does not become fresh by relabeling it. Sampling/finish accept no client counters, result, health or provider facts. Digest is SHA-256 over PostgreSQL's canonical `jsonb::text` bytes in UTF-8; it is an integrity fingerprint, not an external signature.

Counts and `total` are integers0..9007199254740991. Initial idle lease fence is0; run fences are1..1000000000. Summary alert counts sum exactly13; checks=13, samples=1, business mutations=0, provider sends=0. Health severity is attention if any health alert is attention, otherwise unknown if any alert is unknown, otherwise ok. Summary severity becomes attention when source health is attention or assisted-SMS `uncertain` or `send_started` is positive; otherwise it retains source health severity. `active_workers` only counts recent assisted-SMS heartbeats and does not attest Codex execution. SMS enablement is the current `hybrid_sms_notifications` flag, default false when absent.

Run `lease_expires_at = started_at +120s`; `sampled_at` is null iff summary is null. Present sample time is >=start and <lease expiry. Completed runs alone have `completed_at`, with start<=sample<=completion<expiry. Running/expired records have null completion. In a history response, running expiry is after `checked_at`, expired expiry is <=`checked_at`; completed records remain historical. Lease idle has null active ID/expiry; active expiry is after `checked_at`; expired expiry is <=`checked_at`. Server history has no TTL: clients may use60-second read freshness, while completed sample evidence remains dated.

| Guard reason | SQLSTATE |
| --- | --- |
| `shadow_session_required`, `shadow_permission_required`, `shadow_run_unavailable` |42501 |
| `shadow_request_invalid` |22023 |
| `shadow_request_conflict`, `shadow_fence_lost`, `shadow_snapshot_retry` |40001 |
| `shadow_lease_expired`, `shadow_sample_required`, `shadow_limit_reached`, `shadow_integrity_unavailable`, `shadow_health_stale` |55000 |

Underlying serialization40001/deadlock40P01 may also refuse a transaction. Clients preserve the request ID and reconcile through read lookup after timeout, disconnection or malformed success; they never infer completion or replay lifecycle writes automatically. SQLSTATE transport mapping is controlled by PostgREST; exact known guard responses are refusals, while an unknown transport/server result is uncertainty.

Only the three private shadow telemetry tables are mutated. No financial, receipt, outbox, attempt, provider, device, scheduler or heartbeat state is written. Durable telemetry has no Auth cascading foreign keys and survives session deletion. Completed records document manual shadow monitoring, not attested Codex execution or delivery.
