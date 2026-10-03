# BE04 authorized assisted SMS workflow and session capability binding

The remaining positive SQL acceptance work is complete locally. The real healthy flow passes through all nine APIs, and old capabilities cannot be inherited by another session for the same user. This receipt supersedes the earlier BE04 batch for current capability-binding acceptance; hosted release remains open.

The first positive attempt reproduced a real gap after replaying all191 migrations: a second live session for the same user retrieved the original claim. `backend-positive-batch-attempt1/sql-uat.stderr` retains that failed assertion. The repair adds private, server-owned append-only evidence for claim requests, claim tokens, confirmations and attempts. Each capability is tied to its original actor and exact session before retained legacy work runs. Confirmation and send-start evidence retains the claim fence and body digest, and survives logout. Public audit rows are presentation evidence; they cannot authorize capability reuse.

The private relation has RLS, no client/service direct read or write grant, and immutable UPDATE/DELETE/TRUNCATE guards. It has no Auth cascade that could erase provenance. Existing RPC signatures/defaults and legacy financial, consent, content, destination and send-state implementations remain unchanged. The existing admission and post-work live-session checks remain in place.

| Current real SQL proof | Result |
|---|---|
| Exact current migration replay | 191 passed; every captured source still matches |
| Healthy authorized bridge | Health, queue, claim, content, confirm, send-start, observed outcome, safe release and heartbeat passed |
| Original-session idempotency | Claim, confirmation, send-start and outcome replays retain their exact capability/result |
| Another live same-user session | Six old request/claim/confirmation/attempt/release uses denied without receipt, private evidence or audit writes |
| Logout followed by a genuinely fresh same-user session | Four old claim/confirmation/send-start/attempt uses denied |
| Fresh authorized session | New claim, exact-content read and safe release succeed |
| Unbound retained legacy evidence | Claim, confirmation and attempt adoption denied with durable rows preserved |
| Immutable session provenance | Confirmation/send-start retain original session after logout; rewrite/delete/truncate and direct service access denied |
| Existing authority matrix | 63 denials across nine APIs retained |
| Existing live revocation orderings | 12 real blocking cases retained, plus clock-expiry rollback and snapshot denial |

`backend-positive-batch-attempt2/result.json` records20 passed phase assertions. Its source-bound SQL fixture contains all detailed positive, replay, bounded-evidence/release, idempotency-conflict, session-replacement and immutability assertions. Two synthetic valid outbox jobs are constructed using the existing trusted canonical financial API as the private fixture installer; public v2 calls execute the actual legacy bodies, without stubs or broadened service grants. The complete healthy seed rolls back before sequential user-deletion cases. No carrier or network send occurs, and this is not financial-finality policy certification.

`backend-positive-batch-attempt2/effective-schema-catalog.json` and its saved SQL query capture the revised effective metadata and application definitions without table rows. Source hashes and the settled migration hash are in `backend-positive-batch.json`.

Preexisting unbound capabilities fail closed; the migration does not invent session provenance or rewrite durable work. Safely unsent queued work can receive a new exact-session claim. Previously armed unbound evidence stays retained and requires a separate governed recovery path. That operational rollout boundary must be assessed before hosted deployment.

The unique network-none cached-image target published no ports, disabled Cron/pg_net dispatch and was removed after tests. Its row-free platform bootstrap and explicit local installer/pg_net prerequisite normalization do not attest hosted installer privileges. Hosted installation, Auth-provider/runtime verification, effective grants, rollout, physical carrier behavior and production release acceptance remain open. No shared or hosted target was changed.
