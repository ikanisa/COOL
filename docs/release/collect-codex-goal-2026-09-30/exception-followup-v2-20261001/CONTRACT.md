# Exception follow-up v2

Additive migration: `supabase/migrations/20261001190000_exception_followup_v2.sql`.
The pinned Supabase CLI 2.84.2 generated `20261001144443_exception_followup_v2.sql`; only that new empty file was renamed to the coordinated 190000 version before implementation.

All new public functions grant EXECUTE only to `authenticated`. They require Read Committed, the live original caller's actual Auth session, locked current `platform_owner`, `payments.read`, `notifications.read`, `system_health.read`, and explicit canonical verified email approval. Mutation additionally requires `notifications.manage`. Read does not add generic `admin_users.read/manage`. A transition-mode WhatsApp identity remains governed by unchanged v1; it is refused on all v2 surfaces. Private helpers have no API execute/schema grants. No tables, direct grants, financial, outbox, send or source mutations are added by v2; the action delegates exactly to v1's domain mutation/audit.

## Eligible directory

`admin_list_exception_followup_operators_v2(p_limit integer default 25, p_before_created_at timestamptz default null, p_before_operator_id uuid default null)`

Exact result keys: `contract_version: 2`, `scope: "platform_global"`, `checked_at`, `sample_valid_until`, `limit`, `rows`, `next_cursor`.

Rows contain only `operator_id` (opaque UUID), `display_label` (`Collect ID ` plus the canonical six-digit public ID), `created_at` (profile creation UTC6). The label is authorized on-screen directory data, never an email/contact, role history, Auth/session field, or reconstructed action. No total is exposed. Profile times are finite, not earlier than year 1 and not later than checked_at. Eligibility uses existing `collect_ops.recipient_available`: valid matching confirmed email approval plus current nonrevoked platform_owner with all three read permissions. It requires no active recipient session. This read is a selection snapshot, never future mutation admission.

Limit 1..25 is echoed exactly. Both cursor args must be present or both null. Ordering is strictly descending `(created_at, operator_id)`; cursor is the last shown row when an additional eligible candidate exists. Otherwise next_cursor is null. A later window can become empty after eligibility changes. Cursor timestamps are finite UTC-compatible year 1..9999. Every output timestamp is exact UTC6 `YYYY-MM-DDTHH:mm:ss.ffffffZ`. Read validity is checked_at+60s, not an extension of approval or recipient eligibility. Submission always rechecks actual recipient eligibility.

## Reviewed action

`admin_act_exception_workflow_v2(p_request_id uuid, p_exception_id uuid, p_expected_source_revision bigint, p_expected_workflow_revision bigint, p_action text, p_assignee_id uuid, p_due_at timestamptz, p_reason_code text, p_expires_at timestamptz)`

The nine argument types/meanings match v1. Expected source revision 1..1000000000; expected workflow revision 0..999999999. Actions: `assign|escalate|resolve`. Reasons: `review_started|owner_review_required|uncertain_send_review|contact_review|source_rechecked`. Resolve requires source_rechecked. Assignment requires a nonnull eligible assignee and finite future deadline at most 30 days from actual mutation authority check; other actions require null assignee/due inputs. Request expiry must be future and at most 120s when a new action commits. Replay under current authority may recover an already recorded exact original request after expiry, never create a different action. The actor stays original; a newly valid current session is allowed as in v1, without requiring the original submission session UUID. UUIDs accept general valid UUIDs; canonical text is lowercase. Due/expiry input years1..9999.

Exact receipt keys: `contract_version:2`, `request_id`, `exception_id`, `source_revision`, `workflow_revision`, `action`, `escalation_id`, `source_resolved`, `financial_action:false`, `send_action:false`, `recorded_at`, `request_fingerprint`.

The source revision is the expected/current source version; resulting workflow revision is expected+1. Assign/resolve escalation_id is null; escalate has the actual durable escalation UUID. source_resolved is true only for resolve; this requires actual source already cleared. Recorded_at is immutable original v1 server commit-evidence time. It remains dated evidence, never renewed by lookup. V2 ACK means an operator workflow action recorded; it does not prove source handling, external delivery or transport execution. All original v1 result/body behavior remains unchanged.

Fingerprint is lowercase SHA256 hex of exact UTF8 text with single LF separators and **no trailing LF**:

```
collect-exception-workflow-v2
<canonical request UUID>
<canonical exception UUID>
<source revision decimal>
<expected workflow revision decimal>
<action>
<canonical assignee UUID or ->
<due UTC6 or ->
<reason code>
<expiry UTC6>
```

There are ten lines. Decimal strings have no padding/sign. Hash includes every reviewed input and is derived on the server from typed arguments, not a supplied digest. Stored original request parameters derive the same authoritative fingerprint during lookup. Neither ACK nor lookup echoes assignee/due/reason as raw action reconstruction data. The UI may retain a metadata-only original request reference: original IDs, revisions/action, expiry and fingerprint; it must never replay or reconstruct a cross-operator mutation after reload.

## Original-only lookup

`admin_get_exception_workflow_request_v2(p_request_id uuid, p_request_fingerprint text, p_expires_at timestamptz)`

Exact result keys: `contract_version:2`, `request_id`, `request_fingerprint`, `expires_at`, `checked_at`, `sample_valid_until`, `status`, `receipt`.

Status `recorded`: same original actor and UUID found, stored full-input fingerprint and exact expiry match, receipt is the immutable v2 ACK. Its recorded_at is no later than checked_at. Wrong fingerprint or expiry raises 22023 `exception_followup_request_conflict` without returning receipt.

Status `not_recorded`: no request for this original actor+UUID found after acquiring request lock; receipt null. Another actor's request remains indistinguishable from absent. Status `in_progress`: current authority succeeded but original UUID request advisory lock was held elsewhere; receipt null. Both echo the reviewed lookup fingerprint/expiry. An echo is not proof that a request was enrolled. No status authorizes replay. A fresh not_recorded read with checked_at>=original expires_at permits clearing a stale local recovery reference, never automatic resubmission or replacement UUID.

Read validity is checked_at+60s. The same canonical original UUID/fingerprint/expiry must be used manually on every lookup. A function-local 100ms lock timeout applies before disclosure, including global roster authority held by an actual action. Timeout maps 55P03 to stable `exception_followup_authority_busy`; it discloses no request state and must retain the original recovery reference. It must not be represented as in_progress before current authority succeeds.

## Refusals and unchanged domain

22023: `exception_followup_directory_input_invalid`, `exception_followup_lookup_input_invalid`, `exception_followup_input_invalid`, `exception_followup_request_conflict`.
42501: `exception_followup_email_owner_required` or inherited current session/role/permission refusal.
55P03: `exception_followup_authority_busy` on bounded reads.
40001: inherited `operational_exception_snapshot_retry` for non-Read-Committed calls.

V1 domain refusals stay unchanged: request conflict/unavailable/expired/deadline invalid;55000 source revision/state/assignment required;42501 recipient unavailable. V2 cannot bypass v1's current recipient validation, source refresh, source/workflow revisions or durable escalation uniqueness. Public audit remains v1 actual actor + original request/source/workflow/reason/escalation evidence. Joined audit v1 does not include all workflow request/delivery/read history; this slice does not claim that integration complete.

The focused SQL packet uses retained row-free schema153 and exact additive subset, local privileged installer normalization and SET LOCAL synthetic authenticated claims. It is not the current whole186-or-later migration rehearsal, hosted installer ACL acceptance, GoTrue/provider/device/scheduler runtime proof or deployment.
