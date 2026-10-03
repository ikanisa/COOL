# Trusted receipt exception worker

This endpoint runs the existing bounded receipt deferral scanner and exception
escalation pump in one database transaction. It writes exception observations
and private Admin inbox delivery only. It cannot create receipts, alter money,
acknowledge business events, invoke the Android sender or send externally.

Migration150000 installs an **inactive** `collect-receipt-exceptions` cron job.
It keeps every existing cron job unchanged. Once explicitly configured, the job
wakes this fixed endpoint every minute using pg_net. Each durable original UUID
has exactly90 seconds of authority, a configuration revision and fixed limits
(scanner1–25, inbox escalation1–20). Each scan independently bounds both source
seeding and work processing by its scan limit. UTC-day quotas reserve jobs and
their configured scan/escalation batch limits when the original is created;
lost, refused or expired jobs do not refund reservations. These limits are
worker batch reservations, not financial-action or SMS quotas.

Only one current original can execute. Redispatch preserves the same UUID,
revision and deadline, waits at least30 seconds and stops after3HTTP attempts.
The execute RPC atomically records the original scan ACK, exact scan-linked
worker receipt and any actual inbox delivery. Unknown HTTP outcomes reconcile by
original UUID. After expiry, the scheduler acquires the exact original lock and
records a durable `expired_without_receipt` fence before reserving another job.
It never frees uncertain reservations or blindly retries a financial/send
operation. Configuration changes fence previous jobs by revision, and disabling
the schedule waits for active execution before returning.

## Deployment inputs

Use the existing project `lhbowpbcpwoiparwnwgt`; the SQL transport refuses any
other URL. Deploy the current handler/index and merge deployment.toml into the
reviewed Supabase configuration. Provision these Vault names through the
approved secret-management workflow, without putting values in chat, source,
cron commands, logs, handset or the unattended Node profile:

- `collect_receipt_exception_project_url`: the exact existing canonical URL.
- `collect_receipt_exception_api_key`: that project's publishable API key.
- `collect_receipt_exception_worker_secret`: a dedicated generated credential
  (32–256 characters; no newline), also installed as the Edge secret
  `COLLECT_RECEIPT_EXCEPTION_WORKER_SECRET`.

Edge uses the already configured project `SUPABASE_URL` and
`SUPABASE_SERVICE_ROLE_KEY` only inside the trusted backend. Its RPC allowlist
contains exactly execute and original-request lookup. Authentication uses the
dedicated `x-collect-receipt-worker` header; an operator JWT or the general
INTERNAL_FUNCTION_SECRET does not authorize this endpoint. All responses are
strictly projected, redacted and `Cache-Control: no-store`.

Install150000 after110000/120000/140000 and the reviewed native130000 slice. The
scoped local UAT deliberately omits native130000; full-candidate replay is a
separate integration requirement. pg_net installation requires the actual
managed installer's extension privileges. The source never supplies or invents a
Vault key, credential, current operator approval or release acceptance.

Installer-only configuration (all API roles denied):
`configure_receipt_exception_schedule_v1(expected_revision, enabled, scan_limit,
escalation_limit, day_jobs, day_scan_sources, day_escalations)`.
Defaults are disabled,25,20,1440,36000,28800. Enabling validates the fixed
transport; it must follow hosted Auth/RLS/Edge/Vault/cron acceptance. To stop,
use the same function with the current revision and enabled=false. The
configuration revision and exact changes are retained immutably. A deployment
rollback pauses this schedule and retains all originals and evidence; do not
delete queues or blindly rerun uncertain requests.

## Wire contracts and health

POST execute has exactly: contract_version1, action=`execute`, request_id,
configuration_revision and expires_at from the prepared original. POST reconcile
has exactly: contract_version1, action=`reconcile`, request_id. Callers cannot
supply limits, recipients, amounts, text, URLs or actions. Execute rejects
expired input; reconcile remains available after the deadline. A missing
original before its deadline is uncertainty, never proof of no work.

Service-only DB RPCs:
`execute_receipt_exception_worker_v1(uuid,bigint,timestamptz)` and
`get_receipt_exception_worker_request_v1(uuid)`. The immutable11-field worker
receipt includes the original18-field scan receipt and6-field private inbox
result. The lookup returns the original receipt, a fresh60-second observation
and the retained original deadline. An overlapping execution returns in_progress
without recording completion.

`admin_get_receipt_exception_worker_health_v1()` requires a fresh approved
current operator session and permissions. It reports timestamp freshness,
transport configuration, reserved daily batch budgets, pending work and finite
alerts (WORKER_STALE, ORIGINAL_OUTCOME_UNKNOWN, ORIGINAL_EXPIRED_UNHANDLED,
DEFERRAL_BACKLOG, SOURCE_REFUSALS, TRANSPORT_UNCONFIGURED,
WORKER_QUOTA_EXHAUSTED). It exposes no recipient, phone, body, balance or source
ID. Observed health is not whole-source completion, inbox read acknowledgement
or financial/SMS delivery acceptance.

## Evidence limits

The isolated SQL target uses synthetic role claims and a clearly identified
synthetic Vault decrypted view because its cached runtime has no pgsodium root
key. HTTP tests exercise the real handler, including a loopback request and
actual SQL-produced fixtures; service transport fault cases use declared stubs.
These checks do not verify managed Vault cryptography, hosted JWT/RLS, actual
Edge availability, pg_net network delivery, production cron, device or carrier.
Keep the shipped job inactive until those deployment checks are completed.
