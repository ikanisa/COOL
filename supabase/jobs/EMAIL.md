# Contribution email scheduler

This is a separate, inactive-by-default Cron/Vault lane for one opted-in contribution receipt per dispatch. It uses the same locally hosted Supabase database and Edge runtime as Collect. It does not inherit permission to send from Auth SMTP configuration, the main maintenance scheduler, or a successful build.

## Components and boundaries

| Component | Responsibility |
| --- | --- |
| email-bootstrap.sql | Owner-only inactive install, bounded queueing, exact reply reconciliation, activation and pause |
| scripts/supabase/email_jobs_operator.mjs | Hashed deployment validation, SQL rendering, private evidence-file checks and owner operations |
| collect-email-jobs | Dedicated token admission, actual database/profile verification, current application-fence admission and exact dispatch envelope |
| app.notification_email_job_dispatches | Immutable outer dispatch/admission identity and retained result, including an empty original probe |
| app.notification_email_deliveries | One original event/recipient obligation, final current consent/identity checks and retained SMTP uncertainty |
| collect_ops.email_dispatches | Durable native HTTP request identity, transport epoch, credential version, readiness and response digest |

The handler accepts exactly dispatch_id and email_admission. The admission contains contract = collect.contribution-email.v1, the current source_sha256, a separately reviewed approval_sha256, a positive admitted_from Unix timestamp and batch_limit = 1. Its reply echoes the exact dispatch/admission and returns emails with status, processed and results. Each result contains only state and delivery_confirmed = false.

An SMTP acceptance never becomes a delivery confirmation. A duplicate HTTP request reads its original stored result; it cannot drain another event. An original empty probe remains empty if eligible contributions arrive later. A lost claim/finish acknowledgment or provider result stays uncertain, with no automatic resubmission. The outer dispatch ID is also the retained email send-attempt ID when an event is claimed.

## Installation

Use the exact prepared release and its canonical COLLECT_DEPLOYMENT_PROFILE plus COLLECT_DEPLOYMENT_PROFILE_SHA256. The database must already have the complete notification and deployment-identity migrations, its owner binding, and the current initialized source fence.

Install the main jobs artifact before this email artifact: the main artifact creates collect_ops; email reuses that namespace. Render to a new private file:

    node scripts/supabase/email_jobs_operator.mjs render /private/new-email-bootstrap.sql

Rendering creates no extension, credential, HTTP request or active job. Apply the rendered SQL through the trusted owner psql/Operator.sql bridge on the private database. Installation is transactional, refuses an existing email job/configuration, and leaves collect-email-delivery-v1 inactive. Do not drop an existing journal to reinstall it.

The renderer binds the exact nine email routines by body digest, parameter/return types, language, volatility, search path and owner. The installed fence inventory preserves the main scheduler's guards and checks both lanes' function access, named jobs, queued native requests and unresolved dispatches. It includes the application dispatch journal. Adding an unreviewed routine, changing an email body, widening a runtime grant, or changing the installed cron identity makes coverage unavailable.

Runtime application roles cannot read or execute the owner scheduler or Vault/net interfaces. The owner CLI requires postgres as both session and current user and verifies the actual database's deployment identity. Its connection target is deliberately db:5432/postgres, with the supplied private CA and certificate verification enabled. Run connected commands in an explicitly configured operator context attached to the Compose private network, or use the trusted owner SQL bridge. A host process cannot assume that private Docker DNS resolves. Never publish a database port to make the CLI work.

## Configuration and evidence

Keep COLLECT_CONTRIBUTION_EMAIL_ENABLED=false until the specific receipt-email provider and opt-in flow have been qualified. Enabling it requires the current source, COLLECT_JOBS_EMAIL_APPROVAL_SHA256, COLLECT_EMAIL_ADMITTED_FROM and the separately configured transactional-email sender. Existing members remain opted out by default. Auth SMTP enablement is independent.

The dedicated COLLECT_EMAIL_JOB_TOKEN must match the private Vault entry named collect_email_job_token_v1. Provision that entry through the approved owner secret-custody process. The renderer and operator accept no raw Vault-token argument and print no credential value.

Create an owned, independent mode-0600 readiness JSON file with exactly these fields:

| Field | Required evidence |
| --- | --- |
| format | collect.email.readiness.v1 |
| profile_sha256, endpoint | Exact prepared profile and supabase_origin/functions/v1/collect-email-jobs |
| source_sha256 | Current admitted backend source |
| deployment_sha256, runtime_evidence_sha256 | Installed source/configuration readback and runtime acceptance |
| provider_evidence_sha256 | The specifically configured receipt sender's verified behavior |
| token_custody_evidence_sha256 | Independent custody of this scheduler's private token and Vault version |
| copy_inventory_evidence_sha256 | Retained outbox, scheduler, native HTTP, provider and backup copies |
| quota_evidence_sha256 | Capacity and quota review for the selected monthly budget |
| verified_at | Canonical UTC ISO timestamp, verified within one hour |
| email_admission | Exact five-field, current-source admission described above |
| monthly_budget | Integer from 1 through 10,000 |

The operator adds evidence_file_sha256 from the file's actual bytes. It rejects symlinks, multiple hard links, nonprivate modes, foreign ownership, excess bytes, unknown fields, stale evidence and widened batches. Hash fields identify independently reviewed evidence; filling them with arbitrary digests is not qualification.

## Owner probe and activation

These commands are for the approved private operator context. A probe can send one real eligible receipt when the runtime is configured and enabled; it is not a harmless health check.

1. Record the readiness file with readiness /private/email-readiness.json. This pauses the lane and invalidates any probe for different readiness.
2. Generate and retain an original UUID with new-dispatch-id. That command submits nothing.
3. Invoke probe ORIGINAL_UUID once. If its response is lost, reuse only that original UUID for readback; never create a replacement ID to guess whether it ran.
4. Invoke reconcile to read the original native HTTP result. Reconciliation never submits another HTTP request. A missing, malformed, oversized, mismatched, failed or unknown result pauses the schedule.
5. Invoke activate READINESS_FILE_SHA256 only after the exact probe is confirmed. Activation requires the same readiness/admission and Vault credential version, a probe younger than 15 minutes, fresh readiness, current source, exact cron identity and no awaiting or unconfirmed request.

The installed schedule runs every five minutes and permits one request per slot. The chosen monthly budget includes probes and rejected dispatch records. Every request has its own retained UUID; a recycled numeric pg_net request ID cannot match an older transport epoch. A database/server or native transport recreation requires a new probe.

Use status for metadata and pause to stop both the lane flag and its named cron job. Pause remains available when application admission is closed. Reconcile before quiescing when possible: state-changing reconciliation uses the current write fence. A blocked or unknown result must be investigated against its original dispatch, sender and database records.

review-unknown ORIGINAL_UUID REVIEW_EVIDENCE_SHA256 records a separate owner review after the five-minute wait; it retains reviewed_unknown, clears the probe and leaves the lane paused. It does not claim delivery, settle the email outbox, or provide the local request-lifecycle proof required for a complete fence. The existing append-only lifecycle protocol remains separate and unchanged. No timeout, empty queue, reviewed-unknown label or row pruning is used as automatic lifecycle evidence.

## Retention, backup and qualification

No journal is automatically pruned. app.notification_email_job_dispatches is a shared blocked retention class without a personal selector. The exact notification schema profile includes every new table and preference column. external:collect_ops, external:vault, external:net and external:cron cover shared scheduler/secret/native-request copies; backup includes their data, schema, functions and privileges. Provider copies remain separately inventoried. An SMTP state is not an erasure receipt.

Local verification covers the real notification SQL/row guards and dispatch idempotency in an isolated PostgreSQL 17 fixture; owner scheduler SQL uses explicit Cron, Vault, pg_net and deployment-assertion doubles. The separate full-installation qualification must exercise the actual owner profile binding and native extensions. The handler tests use explicit database/fence/provider boundaries. None of these tests sends a real message, activates a live job, proves native pg_net worker behavior or grants deployed provider acceptance.
