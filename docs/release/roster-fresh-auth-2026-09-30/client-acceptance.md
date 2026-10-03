# Fresh roster recovery: local client acceptance

Status: **PASS for the completed local Auth/roster client scope.**

The final packet is `auth-export-attempt10-final-client/validation.json`.
`client-acceptance.json` binds its source and output hashes to the independently
executed root SQL packets. No database, hosted service or provider was called
by the client acceptance runner or this evidence seal.

## Verified results

| Evidence | Actual result |
| --- | --- |
| Copied current Auth/roster Dart tests | 145 passed; zero failures/errors; two optional historical fixture skips |
| Required actual149 SQL receipt decoder | Named machine test completed successfully, without a skip |
| Scoped Dart analysis | No issues |
| Real Chrome, vendored GoTrue privacy fixture | 28 checks passed |
| Production Supabase initialization and actual Admin roster helper/dialog in Chrome | 22 checks passed |
| Root-installed149 rollback UAT | 51 assertions passed; exact recorded table/catalog/cron rollback preserved |
| Root-installed150 execution of149 concurrency harness | 36 scenarios; 31 verified overlapping blocking waits; 149 table/catalog/cron fingerprints restored |
| Input integrity | 6,109 copied inputs, SDK library bindings and compiled web files unchanged |
| Current source integrity | Entire captured live source unchanged at gate completion; 557 runtime input bindings unchanged when sealed |

The required149 decoder is identified by its unique named machine event.
The two historical fixture skips do not substitute for that required test.
The root race runner deliberately did not reset sequence counters; its
`sequences_restored: false` is preserved in the seal.

## Corrections and their purpose

| Implemented control | Why it is required | Acceptance evidence |
| --- | --- | --- |
| Browser Auth credentials and PKCE remain in page memory; peer messages contain only denial references | A reload or another page must not recover renewable credentials or authenticate from a channel message | Actual GoTrue privacy checks and production reload/peer-refresh checks |
| Production initialization removes owned legacy keys from both browser stores and rejects denied cleanup | Previously saved credentials must not remain usable after adopting memory-only browser Auth | Normal production initialization: owned-key readback, unrelated-value preservation and actual opaque-origin sandbox denial |
| Production roster dialog is wrapped in the captured sticky Admin authority scope | Same-session permission, role, loading, repository or identity changes must clear private rows and prevent late replies from restoring them | Ten direct production-helper cases; normal Chrome peer logout and retained-loading disposal |
| Valid dialog completion uses the host authority scope after the dialog gateway is disposed | Closing a successful dialog must still allow the exact ACK to reach the host once | Direct helper ACK/disposal test and normal browser committed completion |
| Both `collections.moderate` and `users.read` are required before direct helper launch | A direct call must not open the private editor with incomplete authority | Separate denied direct-call tests for both permissions |
| Six roster mutation RPCs explicitly opt out of SDK retry | Future dependency changes must retain explicit write-dispatch policy | Twelve actual locked-SDK network-loss/503 cases; one POST per explicit caller |
| Fresh transfer uncertainty is reconciled through a status read | A lost response must preserve the operation identity and require a deliberate read of its result | Actual production browser: one application fetch, one wire transfer POST, one server effect, followed by status/recovery reads |
| Recovered editors reset review and submission affirmation | An earlier Auth session's approval cannot authorize the fresh branch | Actual149 decoder, root concurrency proof and normal new-review/explicit-commit path |
| Browser recovery bookmark contains references and digests only | Saved editor content, names, phones and credentials must remain outside browser persistence | Normal production bookmark field allowlist and both-page storage inspection |
| Acceptance runs from a captured source/dependency export | Mutable build outputs must not stand in for the tested client | Before/after source, dependency, SDK library, compiled output and receipt hashes |

The browser fixture invokes `createSupabaseClientFromEnvironment`, production
providers, `createAdminAssistedGroup`, the real gateway, draft, wrapper and
dialog. It supplies synthetic loopback Auth/transport responses; retained149
SQL response structures are used with explicitly reported dynamic transfer
and commit request-ID adapters. Source proof bytes and lineage remain bound
to the root-produced receipt.

## Lost-response diagnosis retained

The earlier claim that Postgrest automatically retried the transfer POST was
incorrect. The bound Postgrest implementation retries GET/HEAD only.
`browser-transport-probe1-before-headers` records one application `fetch`
invocation producing two wire POSTs after a socket reset before response
headers. Neither request carried an SDK retry-count header. The exact replay
returned the same ACK and produced one synthetic transfer effect, consistent
with the independently verified SQL replay contract.

The final uncertainty case instead loses an incomplete HTTP response after
headers. It records one application dispatch and one wire POST, leaves the
dialog awaiting the transfer outcome, and completes through an explicit
status read, new review and explicit commit. The mutation retry opt-out is an
explicit policy; it is not presented as a fix for Chrome retransmission.

## Evidence preservation and scope

The original attempt4 timeout, attempt5 passing packet, attempt6/7 failures,
attempt8 user-directed interruption, attempt9 fixture observation failure and
controlled transport/browser probes are retained. The interruption records
zero remaining owned processes and no newly started browser phase.

The final Chrome packet also proves exact fresh-B peer logout, private draft
removal during retained identity loading, no resurrection after authority
resolution, reference-only cross-tab denial messages and no unhandled browser
runtime errors. Its framework interactions wait for actual draft state after
checkbox clicks; the earlier immediate semantic-attribute timing failure is
retained in `browser-normal-probe4-retained-channel-history`.

This is local acceptance of the production client and recorded installed SQL
contracts using synthetic transport. Hosted deployment, provider execution,
device/store acceptance and whole-system readiness require their own evidence.
The parent release report owns the final L01 and whole-project status.

There are no remaining implementation or acceptance tasks in this assigned
local Auth/roster client scope.
