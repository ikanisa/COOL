# Collect GoTrue 2.27.1 browser privacy fork

Upstream package: gotrue 2.27.1, hosted pub.dev archive SHA-256 `f6f42ea035953b2439664c1afb46630460edbb917093843a3a0618bfa45619f6` (the repository's previously locked archive). MIT license; original LICENSE and source retained. UPSTREAM-SHA256.json inventories all 79 original cached package files before changes. That upstream manifest is evidence, not a replacement license.

Bounded changes:

- Use the app's already locked flutter_lints for vendored runtime analysis; exclude only preserved upstream test/example cohorts from app analysis. Their original supabase_lints/dotenv/otp/cryptography dev toolchain is not part of the app lock and those upstream cohorts are not claimed as executed. All lib code and Collect-authored Auth tests remain under fatal analysis.
- Remove package workspace-resolution declaration to permit the local dependency override; package name/version and dependency versions remain upstream.
- Browser Auth BroadcastChannel never sends/adopts Session, access tokens, refresh tokens or user objects. Only versioned, project-bound, short-lived departed actor/session references may invalidate an already-matching live session. References confer no authentication authority.
- Capture departed session before asynchronous PKCE cleanup. A late A logout does not remove a fresh B; a same-session refresh remains signed out. Genuine current-session server refresh rejection broadcasts the same bounded invalidation. Existing event reasons and broadcast markers remain intact.
- Reject malformed, nested, foreign, future or expired channel input without logging it. Browser event/session logs omit credentials.
- Native GoTrue behavior follows the upstream branches. The separate Collect factory preserves native durable Auth and explicitly chooses memory-only browser Auth/PKCE.

New helper and browser-specific branches are tested by pure owner/shape/time tests and real SDK browser fixtures. Authentication authority remains the Auth server; client JWT parsing here only derives non-authorizing invalidation references. Final actual acceptance and source hashes are retained separately; this file does not assert provider, deployment, native release or license approval.
