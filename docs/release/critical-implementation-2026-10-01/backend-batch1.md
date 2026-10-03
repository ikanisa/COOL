# Assisted SMS originating-session fence — BE04 local batch

The originating-session fence now surrounds all nine assisted SMS RPCs. Local current-chain replay and real authority revocation/row-wait tests pass. This does not close production acceptance.

The service bridge carries the actor and exact session decoded only after the bearer is verified by Auth. SQL requires both actual service-role execution and the service JWT, then the approved `platform_owner` role and the relevant permission. This owner restriction follows the existing sensitive-admin policy in `20260930233000_sensitive_admin_authority.sql`; a weaker role with notification permissions is explicitly denied. Old sessionless RPC EXECUTE access is revoked. Existing financial finality, consent, current content, destination and claim fencing remain in the original implementations.

A final authority recheck after legacy work and audit prevents a session that expires during a row wait from retaining its write. Revocation locks remain held across the operation and transaction. Actor/session audit provenance excludes SMS text and destination.

| Evidence | Result | Scope |
|---|---|---|
| Exact current migration replay | 191 passed | Frozen application bytes on row-free, task-local platform shape |
| Sequential SQL revocation matrix | 63 denied invocations across nine APIs | Logout, session expiry, soft/physical user deletion, role, approval and permission revocation; no receipt/audit write |
| Live blocking order tests | 12 passed | Six revocations in both transaction orderings through heartbeat; blocking observed using PostgreSQL activity and blocker PIDs |
| Clock expiry during a legacy row wait | Passed | Final recheck rolls heartbeat mutation back |
| Established snapshot and second session | Passed | Repeatable-read denied; another live session never substitutes for the original |
| Operator unit tests | 7 passed | Pinned Deno 2.5.6, frozen cached dependency lock, type check |
| Actual Edge loopback HTTP | 90 checks passed | Pinned Deno 2.5.6, unchanged current source, synthetic recording Auth/PostgREST, providers disabled |
| Host-adapter HTTP suites | 49 Edge + 24 roster passed | Bun transpilation then sequential Node; this phase does not type-check |

Source hashes, commands/transport details and test limits are in `backend-batch1.json`, the frozen `backend-batch1-sql-attempt3/result.json` and `backend-batch1-real-edge-http.json`. All SQL/platform/production Edge inputs still match the successful SQL snapshot. Only host-test metric fixtures and operator-test formatting changed afterward; both were independently rerun. The actual current HTTP snapshot matches every current captured input.

`backend-batch1-sql-attempt3/effective-schema-catalog.json` and its query export metadata and application function definitions only: 22 schemas, 237 relations and 733 functions, with owner, RLS, function security/search path, object/column/default ACL and policy details. No table rows are exported. The catalog is bound to the replayed sources and pinned image.

The unique container used network `none`, published no ports, and disabled Cron and pg_net dispatch. It was removed after the tests and read-only export. The retained platform dump is row-free; the runner explicitly normalizes only this target's installer superuser, pg_net metadata and captured private-reader prerequisite. These are local fixture capabilities, not hosted installation evidence. The physical-user-delete case removes only the synthetic heartbeat inside its rollback fixture; the production retention FK is unchanged.

Failed attempts remain historical evidence: attempt1 needed the existing private-reader platform prerequisite; attempt2 passed all migrations but its disposable heartbeat prevented physical fixture deletion; the old host runner first omitted the current metric module, then exposed stale metric doubles and Bun shared-global interference (32 passed/17 failed). Updating the narrow metric fixture and sequential Node execution produced the final 73/73 host pass without changing product metrics logic or excluding cases.

The new positive SQL path proof covers health, masked queue and heartbeat, while every v2 API has negative authority and ACL proof. Full positive claim/content/confirmation/send-start/outcome/release financial-pipeline proof, signed Auth-provider runtime, hosted effective grants, deployment and physical carrier behavior remain outside this packet. Apply the SQL fence before updating Edge: the old bridge deliberately fails closed until switched. No hosted/shared database or provider was changed, and no release is authorized by this packet.
