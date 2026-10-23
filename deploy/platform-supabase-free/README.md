# Collect Supabase frontend on Netlify Free

This is a new, undeployed frontend hosting boundary. It serves the existing
Flutter Admin artifact and forwards only the nominated Supabase function
protocols. Supabase remains the sole domain, Auth, database, object and AI
authority. There is no host database, session minting, SDK, credential storage,
business authorization or provider fallback in this directory.

The existing deployment proposals are preserved for provenance. They must not
be deployed as part of this target.

## Files and public configuration

- `netlify.toml` publishes the existing `../../build/web` artifact when the
  deployment working directory is `deploy/platform-supabase-free`. It does not
  launch Flutter or create an artifact. The sole build owner must produce and
  qualify that directory before any later packaging/deploy step.
- `netlify/edge-functions/collect-transport.js` is the documented JavaScript
  Edge entrypoint. Netlify supplies standard Fetch objects and `context.next()`.
- `transport.mjs` is a provider-neutral derivative of the reviewed Fetch proxy;
  its source identity and deliberate differences are in `PROVENANCE.json`.
- `public-config.mjs` holds only fixed public constants. Unknown fields,
  another backend, project, hostname or prefix refuse construction. It needs
  no environment variables, API keys or secrets. App public build defines
  remain the responsibility of the existing release producer.

The only host is `https://platform-admin.collect.ikanisa.com`, and the only
upstream is `https://rrlduytparvsjfmegalh.supabase.co`. The exact function prefixes
are `/functions/v1/collect-api` and `/functions/v1/admin-api`. Preview/alternate
Netlify origins cannot proxy production authority. No private files or Edge
source belong in `build/web`.

## Request and response contract

The Edge declaration runs on `/*`. Its API classifier catches bare `/api`, `/v1`,
`/functions` and their children, plus `/privacy/account-deletion` and its children.
Known logical aliases map to
one fixed function prefix. Unknown paths in these namespaces return an error
and never become an HTML SPA response. An Edge response ends Netlify's request
chain; the non-forced `/* -> /index.html` rewrite supplies static SPA navigation.
Physical assets retain static precedence. The handler uses an explicit
`context.next()` static continuation, preserving bytes and existing headers and
adding `no-store, no-transform` for an HTML response. Non-HTML asset bodies stream
unchanged. Every static request also invokes this thin function, which must be
included in runtime/usage qualification.

Method, body bytes, query order/encoding, idempotency key, cookies, requested
range, CSRF/request markers and gateway signing headers are preserved. Authority
overrides and path confusion are denied. Missing Origin on an Admin GET/HEAD
is filled from the configured public origin only after host and Fetch-metadata
checks; it is never synthesized for Admin mutations. CSRF and account decisions
remain in Supabase. Explicit cross-origin requests are refused except the
Google provider's exact GET document-navigation callback. The host never retries.

Only the approved `__Host-collect_admin` cookie is returned, with Secure,
HttpOnly, `Path=/`, no Domain, one Strict/Lax SameSite attribute and no duplicate
attributes. Cookie creation, expiry, refresh, role/MFA admission and revocation
remain in Supabase. Upstream CORS/cache overrides are removed and API responses
set browser/CDN/Netlify-CDN `no-store`. Edge caching is not opted in, and an
unexpected function error uses Netlify's `onError: 'fail'`.

Supabase's default function gateway may serve HTML as plain text. This transport
restores HTML only for explicit success renderer markers with CSP on the exact
challenge, privacy and Google callback routes. Error HTML and arbitrary API
HTML are refused. Native 302 is limited to the server-marked
`collect://auth/google` handoff with one state and one code or an exact known
token-free error. HTTP redirect following and other Location headers are refused.
After dispatch, mutation response failures report `proxy_outcome_unknown` with a
reason. Every Admin GET/HEAD is also effectful because session lookup can refresh
or revoke custody. Google callback GET can commit a managed provider exchange
before the response fails. An uncertain result is never an
instruction to blindly resend a write.

The application callback remains
`https://platform-admin.collect.ikanisa.com/functions/v1/collect-api/v1/auth/google/callback`.
Google's provider-console callback remains
`https://rrlduytparvsjfmegalh.supabase.co/auth/v1/callback`.
The exact additional Supabase redirect glob contains one literal backslash:

```text
https://platform-admin.collect.ikanisa.com/functions/v1/collect-api/v1/auth/google/callback\?state=*
```

JSON/TOML basic strings must escape that backslash. Supabase treats unescaped
`?` as a wildcard; `*` is not a query-schema validator. Its current Auth source
also accepts any path/query on the same scheme, hostname and port as Site URL
before evaluating this allowlist. Set Site URL deliberately and retain the
server's fixed callback, state, PKCE, surface and origin checks. Production
requires no broad preview, localhost or app-scheme provider redirect allowlist.
`collect://auth/google` is the final application handoff for this flow.

## Local evidence and remaining gates

Run from the repository root, using the existing Node installation:

```sh
node --test test/supabase-free-transport.test.mjs
```

These are bounded, synthetic Node Fetch tests. They import the actual server's
pure Google callback renderer, make no network/Auth/database calls, and perform
no deployment or build. They exercise real entrypoint routing, secure cookies,
CSRF/CORS forwarding, denied paths/origins, no retry, uncertain effects, callback
HTML/native outcomes, synthetic signing inputs and exact 7,100,000-byte request
and response hashes. They do not establish hosted performance or a native signer
contract. `VERIFICATION.json` records the frozen local inputs and result.

The default transport buffers up to 16 MiB each way and has a 30-second deadline.
The source roster JSON limit is 7,100,000 bytes. This is why the target uses
Netlify Edge Functions: ordinary Node Functions have a 6 MB buffered limit,
effectively about 4.5 MB for binary requests. Edge has 512 MB memory, 50 ms CPU
per request excluding network waits, and a 40-second response-header deadline.
Its published 20 MB limit is compressed code size, not a documented body cap.
Large payload buffering/HTML checks must be measured on Netlify before parity
can be claimed. Long decoder/AI workflows may exceed 30 seconds and need their
existing durable status/recovery contracts or a separately qualified async path.

The release owner must close these gates before cutover:

1. Package this exact entrypoint/config and a qualified Supabase Flutter artifact.
   No Netlify SDK/bundler/emulator or hosted check has run for this source. Verify
   actual route precedence and source/module discovery rather than inferring it
   from Node tests. The producer must verify public build defines, metadata and
   static CSP; no Cloudflare service, injected beacon or source credential may
   remain in the shipping artifact. No UI redesign is needed.
2. Preserve artifact byte hashes, service-worker manifests, cache rules, robots
   and same-origin static CSP. `_headers` does not apply to Edge responses: API
   security headers are emitted here. Disable snippet injection, pretty URLs,
   prerendering, optional toolbar/badge and split testing; qualify actual hosted
   bytes and offline/deep-link behavior. This config does not assert those
   account settings have been changed.
3. Attach the existing custom hostname, qualify DNS and automatic TLS, and make
   the Netlify project public for OAuth/device navigation. New projects can start
   private. Admin authorization remains in Supabase. A non-Cloudflare DNS target
   must be chosen if the owner's complete exit includes DNS. Preview hostnames
   do not acquire production origin permission.
4. Qualify browser HttpOnly/host-only cookie creation, cold session lookup,
   refresh, CSRF, logout and revocation against the deployed Supabase functions.
   Qualify compression/decompression and Set-Cookie behavior in the actual Edge
   runtime, including uncertain-response recovery without automatic retries.
5. Qualify Google popup and physical native success, cancellation, verification
   denial, provider uncertainty and lost callback/exchange responses. Keep
   `GOOGLE_AUTH_ENABLED=false` until the actual provider/settings/device checks
   pass. The retained challenge renderer marker currently names Turnstile;
   a complete Cloudflare exit requires the separately owned CAPTCHA replacement
   and client/server renderer qualification.
6. Test real installed native/backend HMAC over the configured logical/prefixed
   paths and exact bytes. The local signing test is synthetic. Netlify exposes a
   Fetch URL, not a proven raw unnormalized request target; test its ingress
   normalization and never substitute spoofable forwarding headers. Reconcile
   old native pending journals before any binding migration, retaining stable
   owner/hash identity and fresh scoped consent/enrollment where required.
7. Measure 7.1 MB roster, evidence/AI limits, CPU/memory, concurrent traffic and
   latency. Do not infer acceptance of a domain payload from the transport size
   test. Qualify long operations and scheduled provider work independently.

Netlify Free permits commercial projects and custom domains with automatic
HTTPS. Its current shared monthly allowance is 300 credits with a hard cap;
all projects on the account pause when exhausted. Production deploys consume
15 credits each, outbound traffic 20 credits/GB, web requests 2 credits/10,000
(including static and Edge), and serverless compute uses 10 credits/GB-hour.
These compete for one budget. This is a bounded Free target, not a promise of
unlimited operation or a paid availability commitment. Keep usage/abuse budget
and independent Supabase Free limits in the release decision. Private GitHub
organization integration is paid; later approved CI can package prebuilt files
with a manual Edge deployment without connecting the private organization repo.

## Primary references checked on 2026-10-20

- [Commercial Free permission](https://www.netlify.com/blog/introducing-netlify-free-plan/)
  (permission statement only; its old resource allocations are superseded).
- [Current pricing](https://www.netlify.com/pricing/) and
  [shared hard-cap behavior](https://docs.netlify.com/manage/accounts-and-billing/billing/billing-for-credit-based-plans/billing-faq-for-credit-based-plans/).
- [Edge API](https://docs.netlify.com/build/edge-functions/api/),
  [declarations](https://docs.netlify.com/build/edge-functions/declarations/),
  [limits](https://docs.netlify.com/build/edge-functions/limits/),
  [error/cache options](https://docs.netlify.com/build/edge-functions/optional-configuration/),
  [Node limits](https://docs.netlify.com/build/functions/configuration/).
- [Manual Edge deployment support](https://docs.netlify.com/build/edge-functions/get-started/),
  [custom DNS](https://docs.netlify.com/manage/domains/configure-domains/configure-external-dns/),
  [HTTPS](https://docs.netlify.com/manage/domains/secure-domains-with-https/https-ssl/),
  [project visibility](https://docs.netlify.com/manage/security/secure-access-to-sites/project-visibility/).
- [Supabase redirect glob syntax](https://supabase.com/docs/guides/auth/redirect-urls),
  Auth source at immutable commit `ce9a8eee0cc042be8c7a42981a7ddae631e41d91`:
  [Site URL/allowlist matching](https://github.com/supabase/auth/blob/ce9a8eee0cc042be8c7a42981a7ddae631e41d91/internal/utilities/request.go),
  [glob compilation](https://github.com/supabase/auth/blob/ce9a8eee0cc042be8c7a42981a7ddae631e41d91/internal/conf/configuration.go).
  Hosted target Auth-version equivalence has not been established.
