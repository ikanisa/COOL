# Gateway source and application-fence qualification

## Later complete-current orchestration

The final maintained current native run 4 passed the **14 gateway
fence scenarios and all 34 gateway protocol cases** on the complete 25 chain.
The result is
[`mobile-validation/current-native-final-4/RESULT.json`](../mobile-validation/current-native-final-4/RESULT.json),
with broader qualification-source SHA-256
`fcf1ead40a86061a9454f25f1fa80900d7c3bd025b5483b7765bae92a98cff9a`.
Actual PostgreSQL, restricted admission and the original immutable identity were
used; provider HTTP remains synthetic. Earlier failed attempts and the separate
passing run 2 are preserved. This later pass does not rebind the earlier
receipt below or establish physical delivery, Docker or production acceptance.

## Result

`df3a58ed-2a55-4a59-8761-308189180533.json` records **14 passing native scenarios** on the complete 25-migration chain. The real deployment identity was bound under the normal owner before initialization. Runtime requests used a separately created non-superuser, non-bypass, non-inheriting login whose only membership was `collect_sms_runtime`. The gateway received no general application or owner credential.

The exact source bundle was `6c2474a67f4a665cdb304b54038196f6fd680602d08af4328ad472fd77d16161`, containing 254 files, with no drift during the run. Additive migration `20261101030502_collect_sms_application_fence.sql` had SHA-256 `94e166bd70669743fe8ad1dc1c4aa504d82549f831c658d582d786049c354515`. All preceding 24 migration bytes were checked against their retained pins. Later packaging changes require a new complete-current receipt; this record remains tied to its captured source.

The successful database had 102 application tables, 35 private tables and 125 existing `collect_fence_statement_v1` ALWAYS statement guards. Those counts were read natively after the passing run. The gateway's own guards and restricted wrapper functions are additional, separately inspected objects.

## Defect and implementation

The retained `../gateway-fence-gap-native.json` proved the original defect: a restricted gateway role could pass the real deployment profile assertion and insert a row while Collect was quiescing. The probe transaction was rolled back and row absence was verified. The gateway's independent advisory writer lock did not establish Collect source/epoch authority. A first probe was correctly refused because the normal owner lacked `SET ROLE`; that refused attempt is retained separately.

Migration 25 adds the immutable private gateway-admission ownership map and narrow registration, work/write assertion, close and status functions. They use the existing controller, capacity accounting, WORK/WRITE locks, exact original admission and stopped-work checks. Existing gateway mutation triggers now require that tuple. The gateway's login cannot inspect or close another lane's admission, and the mapping is an explicit blocked shared operational retention class.

The runtime registers every HTTP or maintenance request against the actual profile and current source. It gives each request its own database context, uses a separate bounded control-lease pool, owns deferred work, and guards callback/FCM requests. New work is refused during quiesce. Existing work may finish under its original identity. A lost close acknowledgement is resolved by original-receipt readback; a lost registration acknowledgement is retained without creating a replacement admission.

## Observed checks

| Check | Result |
| --- | --- |
| Fresh installation and prior bytes | Complete 25 installed under the normal owner; prior 24 unchanged. |
| Identity and role isolation | Actual binding used; owner/general runtime role escalation and private/application reads denied. |
| No admission | Direct gateway DML and adapter reads refused. |
| Cached handler after drift | Wrong profile and wrong source refused on each new request. |
| Ingress | Both exact Functions prefixes and closed internal HTTP aliases worked; arbitrary hosts/forwarded authority, wrong browser origins and missing tokens were refused. |
| Lane ownership | Gateway could not inspect or close an ordinary application admission. |
| Existing protocol | Application/device provisioning, registration, callback configuration and message enqueue used real admitted SQL without changing response contracts. |
| Unknown FCM | Synthetic lost acknowledgement retained an uncertain dispatch and pending wake obligation. |
| Held callback and drain | The actual WORK lock prevented drain; new API and maintenance admission closed. Original work could finish in quiescing. |
| Closed context and immutable history | A finished context could not write; ownership-map erasure was refused. |
| Actual source upgrade | A still-running old handler remained refused after the native source/epoch transition; the admitted new source worked. The qualification evidence values were synthetic. |
| Lost close acknowledgement | One close committed, then exact original readback resolved its acknowledgement; no close replay occurred. |
| Lost registration acknowledgement | One original active admission remained and blocked a completed drain; it was not replaced or automatically settled. |
| Source and provider boundary | Captured source unchanged; three synthetic HTTP attempts and zero real provider calls. |

The final fixture remains quiescing because of the deliberately lost registration acknowledgement. The uncertain FCM and callback counters remain retained. Physical Android sends, carrier outcomes and recipient delivery were not simulated as successful settlement. Local work completion can be proven while external obligations remain unresolved; the receipt explicitly keeps production and physical-send acceptance false.

## Preserved failed attempts and test corrections

The first new harness attempted multi-statement migrations through a pool with more than one connection and was refused by `postgres.js` with `UNSAFE_TRANSACTION`; its receipt is retained. Another preflight refused source drift before any case ran. Two partial runs used an owner read against FORCE-RLS gateway tables and waited synchronously for a drain while deliberately holding its WORK lock. Those harness errors were corrected by using the actual admitted gateway read context and asserting the native lock refusal before releasing the original callback. Their logs and fixtures remain preserved; they are not counted as passes.

A subsequent run exposed a real late-context error path: creating a database promise after work had closed could leave a rejected promise unowned. The adapter now refuses that context before creating the promise. The final native run passed the late-write case and all remaining source/acknowledgement cases. No authority check, unknown-outcome assertion or timeout was weakened to obtain the pass.

## Reproduction and remaining work

The maintained runner is `scripts/supabase/testing/gateway-fence.ts`. It requires `COLLECT_CI_SYNTHETIC=true`, the explicitly owned inactive original 16 integration template and cluster descriptors, a fresh `source_manifest` JSON through `COLLECT_GATEWAY_FENCE_SOURCE_MANIFEST`, and an owned output directory. PostgreSQL is real; managed Auth columns and provider HTTP are explicit synthetic boundaries. The runner creates a fresh database and a distinct restricted role, retains failed fixtures and never touches live services.

The current orchestrator also runs the original 34 gateway protocol cases separately under a real gateway work context. That suite, native Edge service routing, full Docker networking, actual Android/SIM handoff, provider delivery, maintenance scheduling, physical backup/restore and admitted cutover remain separately scoped evidence. This qualification does not establish global physical single-writer settlement or production readiness.
