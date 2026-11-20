# Collect Admin frontend transport

The selected backend is the Supabase Cloud project at `https://rrlduytparvsjfmegalh.supabase.co`. BuriMunsi also has separate Android Staff and Admin Sync applications. Admin Sync owns SMS capture permissions. This directory contains the existing web Admin transport and its source checks.

This package has no production deployment command. The production and qualification Wrangler files serve separate outputs of the same React package. Both require verification against the intended Supabase profile. Unknown backend values and mismatched deployment profiles fail closed without falling back to Cloudflare.

In Supabase mode, `src/supabase-transport.js` forwards only the fixed `collect-api` and `admin-api` protocols. Authentication, authorization, managed sessions, database operations, objects, financial logic and AI remain in the Supabase backend and its configured providers. The frontend Worker has no business database or authentication state. It stores no token, mints no credential and retries no upstream operation. This arrangement uses the existing frontend host without requiring a paid Supabase custom domain. Existing frontend-host quotas and costs still apply.

| Frontend path | Fixed Supabase function path |
| --- | --- |
| `/api/admin/**` | `/functions/v1/admin-api/api/admin/**` |
| `/v1/**` | `/functions/v1/collect-api/v1/**` |
| `/privacy/account-deletion` and children | `/functions/v1/collect-api/privacy/account-deletion...` |
| Already-prefixed forms under those two functions | Same fixed function and logical path |

Other function paths and invalid API roots return JSON errors rather than an application shell. The proxy preserves method, exact body bytes, query representation, Idempotency-Key, cookie, required CSRF/Admin markers, and the allowed gateway signature headers. It rejects caller-supplied authority, foreign origins, path confusion, redirects and unqualified compressed responses. Its upstream request requires identity encoding; responses are private/no-store. Ordinary static requests continue through the existing ASSETS binding without being parsed as proxy protocols.

The opaque Admin cookie is `__Host-collect_admin`, with `Path=/`, `Secure`, `HttpOnly`, one Strict/Lax SameSite attribute and no Domain. Duplicate attributes and extra cookies are refused. A valid backend cookie is preserved and belongs to the frontend response host. `X-Collect-Admin`, `X-Collect-Requested-With` and `X-Collect-CSRF` retain their existing backend contracts. The Admin owner and sender are configured privately; no account data belongs in this transport.

## HTML renderer contract

The default Supabase gateway can change HTML Content-Type. The proxy restores HTML only for successful responses with backend CSP and an exact backend renderer header:

- `/v1/security/challenge`: `X-Collect-Document: collect.turnstile.v1`.
- `/privacy/account-deletion` or its trailing slash: `X-Collect-Document: collect.privacy.portal.v1`.

GET bodies must be valid UTF-8 HTML; HEAD requires the same marker and CSP and returns no body. Other API HTML and error HTML are refused. Privacy JavaScript retains its own MIME type. The transport does not invent or weaken CSP. Duplicate challenge controls and a foreign `parent_origin` are refused. These markers, native/webview parent-origin rules, postMessage validation, privacy absolute paths and actual hosted gateway behavior require coordinated backend verification.

## Build and local checks

[React Admin](../../admin-web/README.md) is packaged by `make admin-web-build`. The production Worker configuration serves `build/admin-web/`, and the QA configuration serves `build/admin-web-qualification/`. Verify the paired source receipt before preparing an artifact for the host. Hosted sign-in and workflow qualification remain open.

Run the host-entrypoint regressions with `npm test` from this directory. Mocked transport checks do not establish backend, hosted or physical-device acceptance.

The current adapter digest is recorded in `supabase-transport.provenance.json`. Entrypoint tests exercise backend selection, default forwarding, static-byte preservation, target refusal, cookies/headers/body/query, qualified HTML and uncertain mutation handling. These are local mocked transport checks, not backend, hosted or physical-device acceptance.

## Remaining integration gates

Defaults of 16 MiB per request/response and a 30-second deadline are provisional. Compare them with real evidence upload/download, exports, AI operations, memory/concurrency quotas and host limits. Both bodies are buffered; streaming, WebSocket/Realtime, direct Storage/Auth/database REST are outside this transport. The runtime must honor AbortSignal and identity encoding. Caller-provided IP headers are not promoted into trusted authority; backend rate limits must account for proxy egress or a separately verified trusted-IP design.

After attempted upstream mutation, any transport/response failure returns `proxy_outcome_unknown` with its reason. The backend may already have committed. Preserve the same operation's idempotency key and reconcile with the backend; the proxy performs one fetch and never retries or falls back to Cloudflare.

Real native/backend HMAC tests must verify the exact configured prefixes. Mapping a logical alias to a function prefix changes the externally visible path; byte preservation alone does not prove signature canonicalization equivalence. Reconcile signed pending requests against their original backend before rebinding a dedicated gateway. Preserve ordinary signed-in member capture without wallet registration or gateway pairing.

Before rollout, qualify backend renderer/CSP/origin contracts, cookie and CSRF behavior, storage ACK/delete reconciliation, real project security, idempotency, hosted limits, native capture and retained gateway journals. The PWA caches only its credential-free static asset manifest; API/account responses are no-store. No secret, raw SMS, member record, password or session cookie belongs in assets. Version metadata must state actual backend capability and financial evidence level. A local build, test or dry run does not establish deployment, provider/device behavior, hosted updates or operator acceptance.
