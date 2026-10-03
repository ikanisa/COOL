# Joined entity action history — local Admin implementation

The Admin now has a read-only action-history route for a manual shadow run,
SMS Gateway device, supervisor identity, operational exception or SMS receipt.
Manual shadow run details link to the exact run's history; the general Audit
logs list remains available. Other entity histories can be opened through the
validated entity route; no unsupported identifier is inferred from general
audit metadata.

The fixed `admin_get_operator_entity_audit_v1` read requires a current platform
owner with `audit.read`, `system_health.read` and `notifications.read`, plus
`payments.read` for receipt/exception histories. The backend additionally
verifies and locks current email-owner/session/approval authority. Frontend
roles are not treated as evidence of that backend approval. The SDK captures
the original authenticated session and bearer for one bounded request; there
is no automatic retry or mutation in this view.

The DTO validates exact keys, echoed kind/id/limit, source/action pairs,
source-specific actor/request/revision/fence/reason relationships, UTC
timestamps, a 60-second read interval, newest-first unique event ordering,
paired keyset boundaries and the last-row cursor. Non-shadow records require
the original actor and event/request identity. A null shadow actor remains
explicitly unrecorded. Unknown extra fields and malformed successes fail
closed. Session/identity/permission changes hide retained rows and cursors.
Expired reads hide rows/paging until an explicit refresh. No empty history is
inferred from permission, transport or unavailable-record failures.

The UI shows original request/event/actor IDs, retained source identity,
recorded timestamps in Africa/Kigali and the actual revision/fence/reason
where supplied. It explains incomplete historical coverage and absent shadow
backfill. An action record makes no claim about financial finality, escalation
delivery, current health, policy approval or SMS delivery.

## Evidence scope

Six byte-identical synthetic observations from the parent's isolated SQL
59-case rehearsal are copied into `test/fixtures/admin_entity_audit`; their
provenance records each original path/hash. The DTO tests consume those exact
outputs. Invalid/null/pagination/clock changes are explicitly derived test
cases. SDK calls use an injected mock HTTP client and synthetic sessions;
widget tests run locally. The shadow navigation fixture shifts its historical
dates and binds its run ID to the audit observation solely for a UI test.

Final commands, actual logs, before/after source hashes and rendered captures
are retained in this leaf. Each final check binds transitive local Dart
imports/parts, shared integrations, fixtures, contract/migration and installed
dependency configuration. Initial failures and the interrupted attempt are
retained; Flutter's interrupt exit code 0 is not a successful completion.
See `verification.json` for the exact final results, without adding counts to
older stages or the parent's SQL count.

## Design and remaining acceptance

The sole design authority is the owner-selected
`revolut-design/SKILL.md`; existing Collect theme/components are its adapters.
The inspected static POS-002 light Orders reference is a separate POS source.
It supports quiet grouped rows and readable hierarchy only. This entity
history is a Collect operator-detail adaptation; a current authenticated
Business action-history comparator has not been established. No alternative
palette/reference has been added. The authority gate checks reference hygiene,
not visual fidelity.

Dark/light local captures load Inter and Material Icons and use the actual
registered route/shell. Responsive and semantics checks are scoped to local
widgets; spoken screen-reader, actual browser keyboard/focus/return behavior,
hosted authenticated reads, deployed migration/bundle acceptance and complete
historical retention remain separate. This packet is local implementation
evidence, not a production freeze, reviewed release or 100% design match.
These sources postdate source05 and are not part of its compiled artifact.

The original six-file scoped suite passed216/216 with181 input hashes unchanged.
The capture-only native-loop/transition correction was followed by a32/32 page
file rerun, a1/1 final asset-loaded capture and clean affected-file analysis.
Counts are separate scopes and are not added. Five shared/capture paths changed
after the216-case run; verification lists both hashes. The copied181 current
inputs passed exact readback and identify the final capture harness/shared state.
The earlier suite cannot be represented as a full test of those later shared
bytes. Both final1440×2200 dark/light images were visually inspected.
