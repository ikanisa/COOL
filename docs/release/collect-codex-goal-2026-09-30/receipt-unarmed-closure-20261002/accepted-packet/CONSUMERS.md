# Unarmed closure — actual consumer boundary

The staged migration appends guards; it does not replace any predecessor function body or weaken any primary uniqueness constraint.

| Existing path | Current producer/authority | Closure boundary |
| --- | --- | --- |
| Assisted claim and re-read | `collect_claim_receipt_v2` / `collect_get_claimed_receipt_v2` in current `20261001233000_assisted_sms_originating_session_fence.sql`, wrapping retained financial-policy implementations | Closure refuses every prior claim/confirmation/attempt/session-evidence row or claim marker. New claim-request INSERT and any attempt to reopen/update the original are permanently guarded. |
| Assisted confirmation | `collect_confirm_receipt_v2` wrapping retained confirmation producer | New confirmation INSERT guarded; any already existing confirmation makes closure ineligible. |
| Assisted start | `collect_record_send_start_v2` wrapping the retained current content/finality checks | New assisted attempt INSERT guarded; existing attempt makes closure ineligible. |
| Initial Android identity v1 | `gateway_dispatch_grant_v1` in `20260930211605_android_gateway_identity.sql` | Existing v1 issues no dispatch arm; the private `collect_gateway.dispatch_arms` INSERT receives an additional closure guard. The existing arm-binding guard remains intact. |
| Automatic grant v2 | `gateway_dispatch_grant_v2` / `reserve_dispatch` in `20261001130000_android_dispatch_authority.sql` | Serialized on operations policy and actual original outbox; suppressed original cannot be selected. Automatic attempt INSERT also locks/checks closure, including privileged direct paths. |
| Automatic final arm v2 | `gateway_arm_dispatch_v2` | Uses operations policy/run→original outbox→attempt; closure uses the same order. Issued grant identity stays retained with state granted, but suppressed original rejects normal final arm. Automatic arm INSERT also receives a permanent closure guard. |
| Automatic callbacks/archive | `gateway_callback_v2`, `gateway_archive_attempt_v3` | Closure never accepts an armed attempt or any callback. Existing armed evidence remains writable through its existing authenticated callback path; every distinct callback insertion advances lineage even if the original state text does not change. |
| Primary ensure | Current language and source-busy `collect_receipt_operations.ensure_snapshot` | Continues to return the same retained primary receipt. A closed/suppressed primary is never converted into a retry or successor by ensure. |
| Existing cancellation | `admin_cancel_unstarted_receipt_v1` | Remains unchanged. Its stricter prior-automatic-attempt refusal remains useful; the new closure service alone can irreversibly fence an unarmed ordinary automatic grant. |
| New owner inspect/close/lookup | Current email owner session + roster/permissions via `collect_receipt_actions.actor` | Inspect is read-only. Close serializes and rechecks actual evidence/CAS/authority after waits. Lookup recovers the original exact owner UUID and never grants a send. |

Only new successor schema/config/content decision, read/close/recovery APIs and guards are in this slice. Sending configuration is disabled by default. Successor queue, automatic protocol, native route/retention/recovery and Admin controls are later slices, not claimed implemented by closure tests.
