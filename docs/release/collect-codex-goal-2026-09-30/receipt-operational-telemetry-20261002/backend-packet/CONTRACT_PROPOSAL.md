# Receipt operational telemetry — approved implementation contract

Status: root approved the contract and its unavailable/freshness, producer,
callback-age and supersession refinements. Implementation is staged for exact
source proof and root review. This technical product contract does not establish
visual design authority. Admin UI uses the owner-selected Revolut skill and
existing Collect components.

## Existing evidence to reuse

`admin_system_health` already reports parsing, financial review, push queues,
provider acceptance, transport request ACK latency and scheduler age. Its current
authority locks the actual Auth/session and owner permission rows before reading.
The original five-read MCP profile and its strict v1 health parser stay unchanged.

The exception worker health RPC already reports pending source work, original
request/receipt state, transport availability and reserved scheduling budgets.
It is not a receipt-business handling or Android delivery metric. The operations
policy already defines action/SMS-segment budget caps; those are configured
limits, not measured processing, device or carrier capacity.

Immutable business events, handled-event ACKs, reservations, automatic grants,
arm plans and signed callback rows contain the required durable timestamps and
source identities. The existing230 callback variant index supports exact
first/last-value consistency checks per callback binding, regardless of duplicate
observations. Existing exception workflows provide assignment, deadlines,
deduplicated internal escalation and source-bound resolution.

## One closed Admin reader

`public.admin_get_receipt_operational_telemetry_v1()` takes no caller-selected
recipient, group, arbitrary window or diagnostic text. It is a read-only,
security-definer, READ COMMITTED RPC using `collect_ops.actor(false)`: current
session, platform-owner authority and payments.read/notifications.read/
system_health.read. Recheck authority after any wait. Private source tables and
helpers remain inaccessible to anon/authenticated/service_role; grant only this
reader to authenticated. The same one-statement snapshot derives all metrics.

The response has exactly these top-level keys:

`contract_version`, `scope`, `checked_at`, `sample_valid_until`, `window_start`,
`window_end`, `window_seconds`, `policy_revision`, `mode`, `emergency_stop`,
`configured_collection_count`, `backlog`, `handling`, `budgets`, `callbacks`,
`unknown`, `alerts`, `evidence_limit_codes`, `financial_action`, `send_action`.

Version1; scope `receipt_operations_configured_collections`; window86400 seconds
ending at the database snapshot; sample validity60 seconds. All five metric
sections become null together for no configured scope, timeout, unavailable
measurement or a changed policy. A final current actor/policy revision observation
precedes publication. Metrics select the
current configured collections through indexed source predicates. The global
UTC-day budget section is explicitly global, matching existing cap enforcement.
An empty configured scope is unconfigured/unknown, never a clean zero sample.
No phones, body/reference hashes, text, balances, amounts, contacts, keys, vendor
diagnostics or provider payloads are projected. Counts and integer durations use
the existing exact JSON integer boundary; unavailable measurements are null.

Closed metric sections:

- `backlog`: `unhandled_events`, `oldest_unhandled_age_seconds`, `due_deferrals`,
  `source_busy_deferrals`. These count durable business work, not parser queues
  or exception-worker jobs. Superseded source versions remain pending until
  their own required durable handling ACK exists.
- `handling`: `events_created_24h`, `events_handled_24h`,
  `latency_p50_ms`, `latency_p95_ms`, `latency_max_ms`. Latency is the immutable
  event creation-to-handled-ACK interval, for distinct events handled in the
  window. Transport ACK time and run completion are not substitutes.
- `budgets`: `scope`=`global_utc_day`, `utc_day_start`, `actions_reserved`,
  `actions_cap`, `sms_segments_reserved`, `sms_segments_cap`.
  Compare observed durable throughput with these configured budget bounds,
  explicitly labelled as limits. Do not convert them into a CPU, scheduler,
  Android, network, carrier or delivery capacity guarantee.
- `callbacks`: `armed_attempts_24h`, `expected_segments`,
  `covered_sent_segments`, `covered_delivery_segments`,
  `complete_delivery_callback_attempts`, `conflicting_attempts`.
  A covered segment has an authenticated, arm-bound callback with one consistent
  `(result_code,tp_status)` value. Count distinct bindings/segments, never raw
  callback rows. Coverage says an observation exists, even when it reports
  failure; no delivered-success interpretation is inferred from the value.
- `unknown`: `uncertain_attempts`, `started_without_all_sent_callbacks`,
  `observed_sent_without_all_delivery_callbacks`,
  `callback_conflict_attempts`. These current subsets can overlap; they are not
  added to fabricate a unique delivery count. A missing arm is not called an
  actual send. A framework sent callback is not independent carrier proof.

The fixed evidence codes are:
`durable_handling_not_delivery`, `framework_callbacks_not_carrier_proof`,
`callback_coverage_not_delivery_success`, `budget_caps_not_measured_capacity`,
`costs_unmeasured`, `configured_scope_only`.

## Source cost and correctness

Add time/scope indexes for the24h handled and arm cohorts, preserving existing
callback variant and expected-binding indexes. The current unknown cohort unions
recent arms with a transactional mirror of older still-open arms; an attempt with
missing callbacks cannot vanish solely because its arm is older than24h. The
open-arm mirror uses per-attempt locks already owned by arm/callback producers.
Match the original230 closed consistency fold using bounded per-binding index
lookups. No callback value is interpreted as success.

For lifetime unhandled age/count, use a private derived pending-event
projection keyed by immutable event UUID, collection and creation time. A
transactional event INSERT adds its source; a handled-event INSERT removes it.
Backfill exact unhandled sources while holding producer table locks before
publishing the triggers. No global aggregate row lock is added to financial
producer transactions. This avoids scanning millions of already handled
historical events merely to find the oldest pending event. The mirror is derived
evidence, never a handling authority, watermark, retention deletion or queue
claim. Verify projection/source equality after install and concurrent producers.

Do not insert a lower-bound/sample count as an exact metric, or substitute a
small sample's latency percentile for the declared window. If an enforced
database statement timeout prevents a complete sample, return an explicit
unavailable sample/refusal and keep prior unresolved alerts open.

## Durable, deduplicated alerts and responses

Keep the reader free of writes. Add one separately authorized service sampler
with an original request UUID, fixed source scope and bounded expiry. It records
one atomic immutable sample and an exact original-request receipt; UUID reuse
with changed input refuses. Installing the migration starts no cron or external
communication. Sampler permission stays separate from the unattended identity, run and send
authorities. Default configuration is disabled. No scheduler is installed by
this migration.

Engineering threshold version1:

- `BACKLOG_AGED`: nonempty durable backlog aged at least300 seconds.
- `HANDLING_LATENCY_HIGH`: p95 handling latency at least120000ms.
- `ACTION_BUDGET_EXHAUSTED` / `SMS_BUDGET_EXHAUSTED`: actual day reservations at
  or above current enforced caps.
- `DELIVERY_CALLBACK_GAP`: armed attempt at least300 seconds old missing a
  consistent delivery callback for at least one expected segment.
- `SEND_OUTCOME_UNKNOWN`: retained uncertain/conflicting attempt, or armed send
  at least120 seconds old without all consistent sent callbacks.

Each rule has one durable alert head per rule and exact configured-scope
fingerprint, immutable observation revisions, and one active episode. Repeated
identical observations retain the same alert revision; changing numeric evidence
updates its observation without issuing duplicate escalation for the episode.
Time-window rollover and age growth do not change the exception source signature.
Exact configured collection/revision changes explicitly supersede old scope heads,
retain immutable history and expose a superseded workflow state; they do not
pretend that old conditions cleared or were resolved.
Each alert names a real event/receipt/run/configuration source and a closed
response code: `investigate_backlog`, `investigate_handling`, `review_limits`,
`investigate_attempt`, `reconcile_unknown`. The RPC projects only opaque source
and exception UUIDs, never privileged send/resend controls.

Reuse existing exception assignment/deadline/escalation workflows by
adding the finite `receipt_telemetry` derived source kind and the corresponding
six finite telemetry reasons to every actual source/reason/workflow consumer.
SOURCE_BUSY260 stays intact. Telemetry sources have no transaction SMS route. Source refresh reevaluates the current underlying
condition; acknowledgment does not clear it. Stale/unavailable samples cannot
resolve an alert. Clearing requires a complete new current measurement proving
the predicate cleared. Original observations and response/workflow receipts
remain immutable. Escalation means the existing internal Admin inbox commit;
this sampler sends no SMS, email, push or external message.

## Acceptance scope

Use an exact ordinary-owner synthetic SQL fixture over the retained required
prerequisites only; do not claim full-candidate replay. Prove empty/unconfigured
and active samples, old/current source boundaries, duplicate handling prevention,
paused deferred work, exact durable latency, global reservation/cap alignment,
multipart missing/duplicate/conflicting callbacks, no false delivery inference,
alert deduplication, changed original request refusal, unavailable/stale refusal,
source-bound clearing and resolution, concurrent producer/mirror preservation,
and denial/expiry/revocation/READ COMMITTED authority fences. Capture representative
EXPLAIN cost for deep handled history and duplicate callbacks. Add the strict
Admin decoder only after root approves the DTO; its source and actual observed
SQL fixtures bind the affected parser checks. No five-read MCP expansion, hosted
write, real provider/device test, physical throughput/cost promise or visual
fidelity claim belongs to this slice.

## Scoped prerequisite identity

Migration filename: `20261002030000_receipt_operational_telemetry.sql`. The
SOURCE_BUSY260 prerequisite is canonical `20261002020000` with exact SHA
fe529b7b48ba0e57a5dccf5f0c38eb72cb67a0976d4a074fbdbfcb9a4cdb3cd2.

The local proof selects177 source08 migrations plus15 exact receipt/Admin
prerequisites,192 total. It excludes unused160 worker transport and four
concurrent foreign migrations2330,2340,2350,2355. No excluded function is
stubbed. The reusable checkpoint was dumped after all192 actual applications.
Restoring that dump requires the captured managed pg_net-access role and the
exact GraphQL wrapper from its own managed DDL hook; executed restore bytes and
source identities are recorded. Restore is not a new192-migration execution or
a managed-host compatibility claim. Platform bootstrap uses a synthetic local
superuser; application installation is demoted to ordinary NOSUPERUSER.
