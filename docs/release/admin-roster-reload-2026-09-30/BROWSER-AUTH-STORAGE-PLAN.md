# Browser Auth storage correction — proposed architecture, not implemented

## Confirmed conflict

Current `lib/core/supabase/supabase_module.dart` explicitly configures `persistSession: true`. The normal Admin browser lifecycle attempt5 found Supabase Auth JSON containing `access_token` in localStorage and required that persisted original session for its A→B→A scenario. Logout subsequently removed that SDK storage. Its reference-only roster bookmark passes a narrower storage contract; it does not satisfy the unqualified goal of no Auth tokens in browser storage. Existing attempt5 remains scoped evidence, not full L01 privacy acceptance. No credentials have been removed or copied into this document.

The current deployment is static (`deploy/admin.wrangler.jsonc` assets only). There is no existing server session broker/BFF in this repository. Migration144 binds recovery to the original authenticated actor AND Auth `session_id`, checks live privileges/features, and expires original source/drafts. A new login cannot simply claim an old session ID.

## Contract decision that must be explicit

An opaque HttpOnly cookie identifying a server session is still a bearer authentication credential in browser cookie storage. Calling it a reference does not make it credential-free. Two distinct contracts are possible:

1. No Supabase access JWTs or refresh tokens in any browser persistent store, and no JavaScript-readable authentication credentials. A same-origin BFF can meet this using an opaque, HttpOnly, Secure, host-only session cookie; JWTs/refresh tokens remain exclusively server-held.
2. Literally no persisted authentication credential of any kind, including cookie references. Browser memory-only Auth can meet this, but full reload requires fresh authentication. Preserving the original session-bound roster recovery then needs a new, explicit server-controlled transfer/recovery protocol. Current142/144 do not authorize that transfer. It cannot be implemented by exempting SDK storage, trusting a supplied old session ID, or weakening ownership.

The first contract is the smallest architectural change that retains transparent recovery in the original Auth session. It requires an explicit acceptance definition allowing the HttpOnly reference. If the literal second contract is retained, keep L01 open and implement the transfer protocol described below. Do not mark either approach implemented from this plan.

## Recommended BFF implementation, if HttpOnly reference is allowed

### 1. Same-origin server boundary and private session vault

Add an Admin API server at the Admin origin, with strict method/path/body schemas and an allowlist of supported reads, RPCs and functions. Preserve a separate static public deployment. The server vault owns access/refresh credentials, original Auth actor/session ID, expiry, monotonic session generation and pending logout state. Encrypt credentials at rest and authenticate vault encryption context with actor/session identity. Never return JWTs, refresh tokens, provider secrets or vault contents to the browser or logs.

Create a cryptographically random opaque reference; store only its hash as the lookup key. Use an HttpOnly, Secure, host-only cookie with explicit SameSite policy and bounded expiry. Regenerate the reference on successful sign-in and invalidate the previous reference on account/session transitions. Keep the original Supabase Auth session ID during token refresh. Atomically serialize refresh-token rotation; two tabs must not independently consume the same refresh token. Use the actual upstream Auth expiration/revocation result, not the presence of a vault record, as authority.

### 2. Real OTP and session endpoints

Move the existing Admin send-code and verify-code transport behind the server boundary, preserving current OTP contracts, request IDs, anti-enumeration responses and budgets. The server receives the verified upstream Auth session, writes the vault, sets the reference cookie, and returns only non-secret identity/expiry/generation metadata needed for UI ownership. Its `/session` endpoint revalidates Auth and role/feature access before recovery; return401 or403 when unavailable. Every authenticated response is `Cache-Control: no-store`; exclude the whole API namespace from service-worker caching.

No browser `setSession(accessToken, refreshToken)` workaround: that would return sensitive credentials to JavaScript and retain the existing SDK dependency. Browser startup must fail closed when the broker is unreachable. Show a truthful sign-in/recovery state without automatically resubmitting writes.

### 3. Browser Admin transport and session abstraction

The current Admin client reads `SupabaseClient.auth.currentSession`, decodes JWT `session_id`, observes SDK Auth events, and forwards bearer headers throughout runtime modules. Introduce one Admin session/transport interface with non-secret actor/session/generation metadata. The web implementation uses the same-origin broker; keep native application Auth behavior separate. Replace all direct Admin JWT/auth dependencies through that interface, including login, sign-out, request fences, platform access, roster import, reconciliation, overview freshness, queues, lists, detail and runtime dialogs.

Preserve sticky invalidation: A→B→A is a new local generation even if the original session reappears. An in-flight request belongs to its captured actor/session/generation. Ignore stale completion and disable its editor/action. Browser BroadcastChannel/storage events may announce a change, but only a fresh broker read establishes identity; never trust an event's claimed permissions. Endpoint failure, stream closure, expiration and revocation clear the effective session scope.

### 4. Preserve user authority through every upstream call

Forward the server-held user access JWT for existing RLS/RPC/function calls. Do not switch roster, financial or operator actions to unrestricted service-role mutations. Keep all existing live owner/role/feature checks in142/144 and other migrations. An allowlisted proxy is not authorization by itself. Pin origin/method/content-type, reject cross-origin credentials and unsupported endpoints, apply body bounds and protect cookie-authenticated writes from CSRF with server-validated Origin/Fetch Metadata plus an appropriate per-session anti-CSRF mechanism.

Preserve serialized roster payload bytes and their UTF-8 digest; do not parse/reserialize the embedded payload or derive hashes from `jsonb::text`. Preserve request IDs, expected preview/commit acknowledgments, CAS draft versions, source/draft TTLs and idempotency contracts. Server transport must not automatically retry ambiguous writes. Recovery/status reads and explicit reaffirmation remain the only route back to execution after loss of a response.

### 5. Reload and recovery behavior

On full reload: read the non-secret roster references; establish a currently verified broker identity; require it to match the original actor/session; query the private server draft/status; recheck access and expiry; display recovered content read-only until the existing explicit resume/reaffirmation step. Refresh of the same Auth session may renew server-held JWTs without changing ownership. A different Auth session, absent/expired reference, revoked role/feature or expired source must fail closed. Unacknowledged source absent from the server still requires reattachment.

No roster names, reasons, title, file bytes or Auth tokens in localStorage/sessionStorage/IndexedDB/CacheStorage. Session-storage bookmark remains the nine current references/digests. The allowed opaque HttpOnly reference, if approved, is disclosed as an authentication credential rather than counted as zero browser credentials.

### 6. Logout and compatibility migration

Server logout first invalidates the broker record/reference and attempts the existing upstream sign-out scope. Expire the cookie and return a clear outcome; if upstream status is uncertain, retain a private pending-revocation record and do not restore client authority. Cross-tab notification clears every editor and local bookmark. Static cache may remain if it contains no private runtime/Auth/API response.

For the first broker build, fail closed on legacy browser SDK session data: explicitly remove only known Admin SDK Auth keys after the new architecture is ready, and require a fresh verified sign-in. Do not silently trust/import old localStorage JWTs into the broker. Clear only owned stale recovery references whose original session cannot be established. Preserve server-side lineage and committed financial records. Retain prior service-worker update/rollback artifacts; a new broker-dependent shell needs its own compatibility tests and release gates.

## Alternative: literal zero stored credential plus explicit recovery transfer

Disable browser persistence, retain only in-memory Auth and require fresh verification after every reload. Add a tightly scoped, server-issued recovery capability whose persistence and authentication meaning are explicitly agreed; without any durable credential/capability, fresh Auth must identify the actor and an independent server lookup must enumerate eligible interrupted work. Same-actor equality alone is insufficient for transferring a session-bound draft.

A dedicated transfer endpoint would require live fresh Auth, original actor equality, current role/feature authorization, explicit user selection and reaffirmation, source TTL, per-draft CAS, audit event, and a one-time transfer to the new session. Invalidate the prior session's mutable editor/intents, reject concurrent/double transfers, retain original session provenance, and require a new preview/acknowledgment before any execution. Do not transfer an already executed request into a new executable intent; recover immutable commit status only. Re-signing in cannot manufacture missing unacknowledged source. This is a substantive change to the currently frozen142/144 security contract and needs new migration/UAT/race evidence; it is not a quick client persistence toggle.

## Local implementation acceptance

- Unit/transport tests for OTP/session schemas, vault refresh serialization, revocation/expiry, CSRF/origin/path allowlist/body budgets, and no secret response/log leakage.
- Runtime mock tests for the common Admin session interface, sticky A→B→A invalidation, same-session refresh, late completion, disabled/loading controls and explicit action reaffirmation.
- Real normal-entrypoint Chrome tests after sign-in, draft save, reload, two tabs, response loss, offline/update/logout. Enumerate localStorage, sessionStorage, IndexedDB, CacheStorage and cookies through actual browser/CDP APIs; assert no JWT or refresh-token values anywhere. Under the allowed-reference contract, verify cookie HttpOnly/Secure/SameSite/host/path/TTL and that `document.cookie` cannot read it.
- Actual local PostgreSQL142/144 receipt and adversarial/concurrency tests for preserved original-session authorization. If transfer is selected, add an independent migration and actual two-session transfer races; do not modify or relabel previous evidence.
- Rebuild the real Admin production entrypoint and all callers, not a test-only persistence override. Verify separate public bundle, cache API exclusions and legacy-key migration with an actual old→new browser update.
- Retain hashed source/build/report packets and source-bound regressions. Hosted broker deployment, vault provisioning, real provider Auth/revocation and production-origin cookie behavior remain separate external release gates; local fixtures cannot close them.

## Sequencing

Choose the precise browser-credential contract, then implement server broker/vault tests, common Admin session transport, production entrypoint wiring, all runtime-module callers, legacy storage migration, and normal browser/SQL acceptance. Publish the corrective L01 evidence only after full required acceptance passes. Until then retain L01 open; keep the existing draft/privacy protections and secure reload behavior operational.
