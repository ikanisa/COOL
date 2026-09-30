# Admin declared scope and local gap review

This packet records source discovery and scoped local acceptance. It does not certify every Admin route, action, state, audit record, deployment or provider integration.

## Preserved evidence

- `inventory-attempt2`: 24 declared routes, 71 discovered RPC/function symbols, 55 mapped active endpoints, 19 providers, 16 dialog sites, 134 callbacks and 91 API call sites. All 230 captured source hashes were stable. The 492 named declaration matches are lexical discovery, not an AST or runtime reachability claim. Sixteen legacy/unrouted symbols require explicit reachability decisions.
- `prior-probes-attempt1`: actual installed Supabase/GoTrue SDK with synthetic MockClient HTTP. Eight tests ran: two positive controls passed and six defects failed their desired acceptance. All 480 captured inputs remained unchanged. The failures include an actual delayed PKCE-storage/logout scheduling race.
- `acceptance-attempt1`: preserve the failed first fixed-source gate. Thirteen new controlled-session fixtures used dynamically typed metadata maps and failed before entering runtime; the original six probes passed. No failure is reclassified as acceptance.
- `acceptance-attempt2`: 265 tests passed, three actual SQL receipt tests skipped, 14 scoped analysis inputs clean and 486 repository/test/SQL/lock/package-config inputs unchanged. The retained final test line includes `~3`; the original report's count parser therefore recorded `null`, while exit status and logs remain accurate. A corrected parser will be used for the next gate; this historical report is retained unchanged.

The client packet precedes the pending GoTrue web broadcast fork and the root's final health UI changes. A final current-source gate and actual root-owned SQL receipt compatibility are required.

## Six reproduced defects and implemented corrections

| ID | Prior-source failure | Correction | Current scoped evidence |
| --- | --- | --- | --- |
| GAP-A01 | Repository identity accepted another actor's `user_id`. | Exact identity shape, typed immutable capability arrays and binding to captured request actor. | Original probe plus complete identity/type/actor fixtures pass. |
| GAP-A02 | Detail response accepted a different requested record. | Validate request identity, returned ID and exact typed fields for the seven active detail RPCs; preserve real `{}` not-found. | Original probe, all seven source-shape fixtures, identity substitution and decision-field negatives pass. Actual SQL compatibility is pending. |
| GAP-A03 | `metrics:null` became a healthy empty overview. | Require the metrics envelope, unique typed metric rows and nonnegative safe integer counts. Valid zero and valid empty remain distinct. | Original probe, null/string/fraction/negative/unsafe count negatives and SDK permission/session cases pass. |
| GAP-A04 | Invalid runtime metadata became navigation/queue defaults. | Exact nested navigation, queue, filter and signal fields, bounded values and duplicate checks. Missing legacy RPC handling remains explicit. | Original probe and malformed/foreign navigation/nested contract negatives pass. Shell presentation still requires the separate failure-state correction below. |
| GAP-A05 | Old logout resumed after a new login and cleared the newer Admin session. | Recognize only the actual local user-initiated late event carrying the exact currently live actor/SID/token; preserve only an already matching nonnull scope. Old requests remain permanently invalid. | Actual SDK storage-barrier probe passes; genuine/broadcast/mismatched logout, Auth error/done, expiry, A-B-A and null-scope resurrection negatives pass. |
| GAP-A06 | Expired roster JWT still owned and could dispatch import work. | Constructor claim/SDK expiry checks, bounded expiry timer, checks before and after each await, same-SID refresh only while the lease remains live, and sticky invalidation. | Original probe, real wall-clock no-event expiry and awaited success/error expiry, all five dispatch families, same-SID refresh and disposal cases pass. |

JWT parsing is a local ownership fence. Server Auth, live session, effective permission and SQL locking checks remain authoritative. Synthetic HTTP and stream fixtures do not prove hosted revocation or provider delivery.

## Source-confirmed remaining work in this scope

1. Bind the final gate to the project-owned GoTrue fork and final runtime source. Prove actual credential-free cross-tab behavior separately from these native SDK probes.
2. Decode the root's guarded actual SQL read receipts through the strict helper, including nullable/suppressed SMS rows and `admin_system_health('system')`. The root is the only database writer.
3. Correct group detail's Members source key: current SQL emits `active_members`, while the field spec reads `member_count` / `members_count`. Reproduce it in a widget probe before changing the field spec.
4. Render runtime configuration loading/failure explicitly. `AdminShell` currently uses `.valueOrNull`, so a rejected malformed response still silently falls back to static navigation. Static permission checks remain safe, but the service failure is invisible.
5. Complete the full per-route allowed/loading/empty/denied/revoked/failure/session matrix. Existing protected-route loops cover signed-out, non-Admin, missing capability and request retry; they do not establish every other state.
6. Complete each active action's reason, invalid/cancelled input, permission change, pinned session, uncertain/malformed ACK and persisted audit matrix. Selected grant, retry, reconciliation and roster tests are strong scoped evidence; they are not whole-action acceptance.
7. Review the remaining runtime metadata read (`admin_get_queue_sla`) and audited approval read (`admin_get_whatsapp_approval`) for exact shape, target binding and typed null handling. Both are declared active support entrypoints; their existing validation is weaker than the new routed detail decoder.
8. Resolve the sixteen legacy/unrouted discovered endpoint names against actual reachability. No active export/download flow was found; Dart `export` directives are not an export capability.

Full L03/L04/L05/L07/L16 acceptance remains open until the corresponding complete matrix and current evidence are recorded.
