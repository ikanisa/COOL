# Proposed149 fresh Auth recovery protocol

Status: design for parent review; not implemented or executed. Root selected literal zero persisted browser Auth credentials. This supersedes the earlier plan's conditional BFF recommendation; no cookie/broker/capability exception is proposed. L17 final compact correction is being validated first.

## Auth and persistent browser state

- Browser Supabase Auth uses `persistSession:false`, auto refresh in memory, and a memory-only `GotrueAsyncStorage` for PKCE. Merely changing persistSession leaves the current SDK's default SharedPreferences PKCE verifier storage active. Native Auth behavior is unchanged.
- Before browser Auth initializes, delete only this configured project's exact SDK Auth key and its historical SharedPreferences-prefixed equivalent, plus exact owned legacy PKCE keys. Verify deletion; an inaccessible/unclear store must produce a truthful sign-in/storage failure instead of accepting token persistence. No arbitrary browser wipe and no credential values in logs or evidence.
- Full page reload begins unauthenticated; user completes fresh sign-in. Existing refs/digests/versions remain non-authorizing. No refresh token, access token, OTP code, file bytes, roster/title/reason, or durable recovery capability is added to browser storage. Browser storage scans include localStorage, sessionStorage, IndexedDB, cookies and CacheStorage under actual normal Admin builds.

## Identity eligibility and locking

Each RPC derives actor and destination Auth session from the verified JWT using frozen `require_roster_caller()`. A caller-supplied old session is never accepted. For mutable recovery, derive original/leaf/root source sessions from private immutable rows, recheck their live Auth sessions with `require_roster_actor`, current verified phone, owner role, WhatsApp approval, permissions and feature. Revoked/deleted/expired original authority or reapproval after its session cannot be revived by new sign-in. Destination session must differ and be newly created within10minutes, after the interrupted leaf session/source. All operations retain notification Auth gate then combined roster advisory lock ordering.

A completed initial server preview is required. Missing/unacknowledged source, awaiting preview and failed preview provide truthful read-only state; they cannot manufacture a transfer or cause automatic extraction retry. Noncommitted source/draft TTL is inherited from the original24-hour source.

## RPC and receipt mapping

All new envelopes are exact-key/versioned and bound to the current destination session in memory. IDs/digests are non-secret; none grant authorization. Client validates every expected reference, SHA, version, expiry and status before applying values.

| RPC | Input | Output / effect |
| --- | --- | --- |
| `admin_list_interrupted_roster_imports` | bounded keyset cursor and limit, no old session | Own eligible leaf refs, source digest/kind, created/expiry times, state and CAS etag. No names, phone numbers, filename, group title or reason. Current same-session branches may be shown separately for read-only recovery. No write. |
| `admin_inspect_interrupted_roster_import` | selected import ID and expected etag | Live recheck; exact original acknowledged initial/latest preview and saved editor payload+exactUTF8SHA, read-only state. Explicit selection precedes this read. No executable intent is returned. Unsaved/unacknowledged content is absent and reported as such. |
| `admin_transfer_interrupted_roster_import` | transfer request UUID, selected source ID, expected etag, human affirmation | CAS wins once for the source. Returns immutable transfer metadata, root/old/new import/upload/revision refs, inherited source SHA/TTL, new draft checkpoint/SHA and `requires_human_review:true`. Creates only a new private session-bound branch and audit linkage. No approval, provider or financial effect. |
| `admin_get_roster_transfer_status` | original transfer request UUID | Same initiating destination session only; immutable transfer result or truthful missing. Never retries a write. After success, normal144 recovery reads the newly bound branch/current draft. |
| `admin_get_interrupted_roster_commit_status` | selected committed import ID | Current authorized owner read of immutable commit receipt; no draft/intents/new branch/executable retry. Strict decoder binds original request/import/revision/collection/count/hash and marks already committed. |

Candidate etag binds actor/destinationSID, root/leaf source identity/fingerprint/expiry, latest revision ID, current saved checkpoint+payload SHA, all staged intent identity/hash state and commit existence. Changed edits/reviews/intents or consumed/expired state invalidate the candidate. Revocation/features are checked independently at execution and cannot be cached inside the etag. Request replay requires the exact original input fingerprint and same actor/destinationSID. Conflicting request UUID, stale etag and another-session replay fail closed.

## New branch and lineage

A private immutable149 transfer record has unique `from_import_id`, transfer request ID and destination import ID. It records root, prior and destination actor/session refs, original revision/checkpoint/SHA, transfer fingerprint and stable receipt refs; it stores no new unbounded roster payload. The original142 source, extraction, revisions, results and commits are never updated/deleted.

Transfer creates a distinct source/upload identity under the fresh destination session with original source metadata, digest, parser/schema versions and original expiry. Revalidate original acknowledged initial candidate rows/confidence using the frozen deterministic preview validator; create new revision1 with `can_submit:false` and mandatory review. Preserve/reference the one genuine original extraction record/model where relevant; never insert a fictitious provider attempt or repeat source verification/provider work. Explicit transfer audit identifies all inherited proof. New source identities are recovery branches, not new uploaded-resource reservations, and cannot be replayed through upload/provider endpoints.

The latest acknowledged editor payload, if still based on the latest old revision, is copied as a new exact serialized private editor draft with its parent rebased to the new revision. Otherwise the latest acknowledged reviewed rows are shown as editable draft values, never carried as approval. Original title/reason are restored only when acknowledged; no later unsaved edits are invented. Reset visited pages/identity confirmation/affirmations. A new explicit review RPC and its expected ACK must occur before any new submission. Staged review/commit intents are not copied into an executable context.

The response-loss receipt is metadata only. Do not place full draft/preview response bytes in immutable149 audit storage; current draft payload remains bounded/purgeable144 server storage. A successful status check then reads normal144 branch recovery under the destination session; concurrent newer checkpoint is handled as current server state, not falsely presented as the original transfer ACK.

## Invalidation and compatibility

New149 moves preserved142/144 function bodies behind revoked private aliases and installs signature-compatible public guard wrappers. Frozen142–148 migration files remain unchanged. Guards deny old/transferred leaf draft saves, stage/execute, review, commit and editor recovery; committed audit reads remain deliberately read-only. Service preview/finish/upload replay must reject synthetic recovery-branch source identities. These changes are new protocol behavior and require runtime database compatibility evidence.

Original root expiry and aggregate budgets survive each handoff: at most8 handoffs,19 human review revisions (20 including initial),40 staged intents across the lineage, existing per-actor/source/session ceilings and512KB exact recovery payload bound. Actor source quota counts created recovery branches. Physical purge remains bounded/owner-only and removes expired transient payloads while immutable142/149 lineage and commit proofs remain.

## Required source and actual runtime proof

- Exact Auth policy/legacy key tests, memory PKCE and no cross-project deletion, storage exception behavior, browser reload unauthenticated and fresh sign-in required; no credentials anywhere in persistent browser stores.
- Strict Dart candidate/inspection/transfer/status/commit envelopes, tampered IDs/SHA/etag/session/TTL/unknownkeys rejected; all source text hashes use exactUTF8 serialized bytes, never assumed JavaScript JSON equality with jsonb::text.
- Actual PostgreSQL frozen142/144/145/147 compatibility plus149 adversarial rollback fixture: old-session revocation, reapproval, feature disable, wrong actor/new session, expired root, missing/awaiting/failed source, AI/XLSX lineage, stale editor, stage doesn't approve, new review required, committed status cannot rerun, replay/conflict and bounded purge.
- Actual two-session races: transfer vs transfer; transfer vs old checkpoint save; transfer vs old review/stage/execute/commit; transfer vs revocation/feature disable/expiry; response-loss/status replay. Verify one winner or fail-closed result, original immutable hashes preserved, no duplicate roster/financial writes. Parent alone executes DB fixtures.
- Actual normal Admin browser integration: full reload → fresh sign-in → bounded own lookup → explicit inspect/select/affirm → private branch recovery → new reviewed ACK → explicit submit; separate tabs CAS/stale invalidation, original sessionA→freshB→freshC chain, response loss, storage failure, logout/offline/update privacy and no provider retry. Prior attempt5 remains scoped lifecycle evidence, not zero-credential acceptance.
