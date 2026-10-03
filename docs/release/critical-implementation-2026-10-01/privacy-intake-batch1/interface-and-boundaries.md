# Privacy request intake boundary

This slice records an own-account request and exposes its intake receipt. It does not erase data, restrict account access, remove Auth users or sessions, alter retained principals or existing foreign keys, authorize a retention decision, invoke a processor, or complete BE05.

The subject comes from trusted Auth identity. An ordinary member does not need a collection role or platform-owner authority. Submission requires the actual live Auth session belonging to that subject, a confirmed nonanonymous and nondeleted identity that is not banned, a finite session creation time in the preceding ten minutes, a valid finite session expiry when present, and a future numeric JWT expiration. Status requires a live session and valid expiration but does not require the ten-minute creation boundary. SQL calls require READ COMMITTED; stale transaction snapshots return SQLSTATE 40001.

| Interface | Input | Result |
| --- | --- | --- |
| `request_account_deletion_v1(uuid,text)` | Required client submission UUID; optional reason | JSON receipt with canonical request UUID, submission UUID and replay/reuse flags |
| `request_account_deletion(text)` | Original optional `request_reason` argument | Original UUID return contract, using the same guarded intake path |
| `get_account_deletion_request_status_v1(uuid)` | Own canonical request UUID or own submission alias | Own minimized intake receipt; unknown and another subject's UUID return the same denial |

Reasons are bounded before normalization: at most 500 characters and 2,000 bytes, with control characters rejected. Surrounding ordinary spaces are trimmed and an empty reason is treated as absent. The reason remains in the existing own/Admin request record; the new status receipt contains only a reason-present flag and a fixed reason code. The private fingerprint includes contract version, scope, trusted subject and normalized reason.

An exact UUID and payload replay returns the same canonical request. An equivalent active request submitted under a different UUID also returns that canonical request. Reusing a UUID for a changed payload or another subject fails; a changed payload under another UUID conflicts with the subject's existing canonical scope. A matching historical pending or in-review request can be adopted without changing its reason, status or timestamps. At most 32 submission UUID bindings are accepted per canonical request; an exact existing replay continues to work at the limit. The legacy adapter does not allocate aliases on retry.

For this intake-only version, each subject has one immutable canonical intake record. Its receipt reports `pending_review`, `policy_review_pending=true` and `subject_scope_review_pending=true`; erasure, account restriction, Auth removal, retention approval and processor-start flags remain false. A later reviewed workflow must define scope changes, disposition, resubmission, processing and operational status. This fixed receipt is not an erasure certificate or an operator processing queue.

Private tables and helpers have no client or service-role privileges. The existing deletion table retains authenticated SELECT only: own reads and the established platform-admin support predicate now both require a live SID. The new status RPC remains own-only even for a platform owner. The legacy UUID adapter's formerly weak admission is strengthened; its return type and argument name are preserved. Existing member clients must handle required fresh sign-in and conflicts; this batch does not implement that user interface or attest hosted Auth behavior.

| Condition | SQLSTATE | Message |
| --- | --- | --- |
| Missing, revoked, expired or wrong-subject session; invalid role or JWT expiry | 42501 | `privacy_request_session_required` |
| Live session older than ten minutes on submission | 42501 | `privacy_request_fresh_session_required` |
| Unknown or another subject's status identifier | 42501 | `privacy_request_unavailable` |
| Missing typed UUID | 22023 | `privacy_request_invalid` |
| Invalid reason | 22023 | `privacy_request_reason_invalid` |
| UUID identity/payload conflict | 22023 | `privacy_request_conflict` |
| Existing canonical scope with a changed payload | 22023 | `privacy_request_active_scope_conflict` |
| Alternate UUID limit | 54000 | `privacy_request_submission_limit` |
| Unsupported transaction snapshot | 40001 | `privacy_request_snapshot_retry` |

The maintained global Auth-revocation lock is acquired before actor row locks. Subject and submission advisory locks serialize concurrent requests; session and clock predicates are checked again after the wait. Actual transaction races must show either intake commits while its session is still live and revocation subsequently takes effect, or revocation wins and intake is denied without a new request.

The complete lifecycle remains open: subject and mixed-subject scope review, lawful retention decisions and holds, operational restartable phases, derivative and export handling, Auth/principal retention, native device cleanup, processor and backup/restore evidence, client recovery UX and external acceptance. No retention duration or owner approval is invented here.
