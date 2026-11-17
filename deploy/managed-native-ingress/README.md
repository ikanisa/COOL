# Managed native ingress candidate

This module supplies a narrowly scoped managed-Supabase BuriMunsi frontdoor;
importing it does not install a route, deploy a Worker, provision credentials,
or enable native operations. The existing self-hosted frontdoor remains separate.
It is a candidate until the real Cloudflare and Supabase boundaries and the
native client are qualified.

`createManagedNativeFrontdoor(env)` returns an async Request handler. It accepts
only GET, POST and PATCH on `/v1/burimunsi` and descendants, either directly or
below `/functions/v1/collect-api`, at the exact managed profile's
`member_api_origin`. It forwards once to the profile's fixed Supabase project and
never retries a request. A network error after dispatch has an unknown outcome.
It rejects `CF-Worker` before reading the client address, strips incoming
forwarding and ingress-witness headers, canonicalizes `CF-Connecting-IP`, and
uses a protected HMAC key to bind the request method, path, query, native/auth
headers, body, profile and a pseudonymous network bucket. The Edge verifier
requires that witness and never trusts a direct client's IP header.

The managed verifier binds the idempotency key, request ID and Admin marker in
addition to the existing authority and native headers. The self-hosted signature
keeps its existing header digest for compatibility; managed signers and
verifiers must be updated together when these additional headers are present.
The managed proof record must be canonical JSON with precisely these fields:

```json
{"evidenceSha256":"<64 lowercase hex>","format":"collect.native-ingress.managed-edge-proof.v1","frontdoorOrigin":"<profile member API origin>","networkSource":"cf-connecting-ip","profileSha256":"<exact profile hash>","pseudoIpv4":"off","reviewedAt":1,"status":"reviewed","supabaseOrigin":"<exact profile Supabase origin>","workerGuard":"cloudflare_worker_presence_reject"}
```

Its SHA-256 is `COLLECT_NATIVE_INGRESS_EDGE_PROOF_SHA256`; the JSON is
`COLLECT_NATIVE_INGRESS_EDGE_PROOF_JSON`. The same independent 32-byte
`COLLECT_NATIVE_INGRESS_KEY_BASE64` and its key ID must be held only by the
reviewed frontdoor and `collect-api`. The record is review provenance, **not** a
cryptographic Cloudflare attestation. A valid record or unit test does not
establish actual deployment or a trustworthy peer address. The witness expires
after 30 seconds. A signed nonce alone is not a durable replay ledger. Never log
the witness or secrets, and retain application/device idempotency and
unknown-outcome handling.

`verifyNativeIngress(request, env)` checks the signed method, target, body,
authority, network bucket and lifetime and returns an opaque, single-use token.
The real handler must then open its database and application fence and call
`claimNativeIngress(token, consume)` before provider setup, native setup or
dispatch. `consume` receives `{nonce, profile, policy, issuedAtMs}` and must
resolve `true` only after a committed, atomic, fence-bound insertion; duplicates,
timeouts, lost acknowledgements and store errors must deny without retry. It
must bound its own wait and abandon unconfirmed work. A false or uncertain
claim, an expired or cancelled request, or a reused token produces no witness.
This module defines that interface; an in-memory callback is not a durable
store. The required reviewed migration, database adapter and handler changes
are separate work.

The current `collect-api` entrypoint still calls the legacy
`admitNativeIngress` interface. It now denies managed requests before database
setup, even when their signature is valid. Its self-hosted behavior remains
compatible and does **not** gain durable replay protection until the handler
is integrated with the two-phase interface. The generic handler also needs an
explicit missing-verifier denial: its current optional-verifier branch must not
be treated as a safe managed deployment. No managed route is ready to enable.

Only exact POST `/v1/burimunsi/members/import` and
`/v1/burimunsi/members/import/preview` without a query receive the existing
524,288-byte and 6,991,532-byte wire limits respectively; other routes retain
8,192 bytes. The frontdoor must read these bytes before the backend can check
the HMAC, so provider-side rate, concurrency, memory and body limits must be
qualified before enabling large routes. The retained self-hosted frontdoor
still imposes its existing 8 KiB limit.

Before enabling this candidate:

1. Wire the intended Cloudflare Worker to call this handler **before** its
   generic Collect transport for the two native path forms. Configure the exact
   public hostname, bounded feature flag and secret through protected channels;
   avoid exposing the signing key to static assets or other services. The
   current platform-admin Worker has not been changed by this module. It only
   accepts `ADMIN_ORIGIN`, so this design requires that origin to equal the
   profile's `member_api_origin`, or else a separate reviewed Worker route.
   A shared Worker exposes its environment secrets to all of its code, not just
   this module. Receiver `/v1/functions/*` routes are a separate signed gateway
   protocol and must not be routed through this native-only handler.
2. Update and qualify the Android native API and native email-OTP destinations
   so both use the frontdoor origin. Current `CollectAdminTransport` uses one
   origin for both the pre-auth request and expected Auth JWT issuer, and
   `ManagedCollectBroker` supplies `BURI_API_ORIGIN` for both. Gradle currently
   requires that API origin to equal the shared Supabase origin. Split the
   frontdoor target from the verified Supabase Auth issuer rather than changing
   the issuer to the proxy host. The OTP request currently sets `Origin` to its
   request host, but the backend accepts that header only when it equals the
   Supabase origin; its outer origin allowlist may exclude the Supabase origin.
   Define and test a consistent native OTP rule, such as no `Origin` header for
   this non-browser request, without silently rewriting a browser origin. Keep
   existing Admin cookie/CSRF handling unchanged on its routes.
3. Test against the actual Cloudflare route that direct clients receive the
   correct `CF-Connecting-IP`, same-zone and cross-zone Worker subrequests and
   forged IP/forwarded headers cannot obtain arbitrary signed network buckets,
   and Pseudo IPv4 is off. Verify no unqualified Worker service binding or
   alternative route can invoke the signer. Cloudflare notes that same-zone Worker subrequests
   can alter `x-real-ip`; a header value alone is not proof of provenance.
   [Cloudflare HTTP headers](https://developers.cloudflare.com/fundamentals/reference/http-headers/)
4. Integrate the two-phase verifier and committed nonce store into the real
   handler, with mandatory verifier presence and a reviewed versioned migration.
   Confirm the deployed `collect-api` uses the appropriate function gateway
   policy; directly invoke managed native paths without a witness, with a
   forged witness, with altered signed requests, and with a replay. All must
   fail before business or provider effects. Bind actual deployment identity,
   key custody, profile and reviewed edge evidence before activation.
5. Test actual sign-in, revocation, network limits, long disconnect, the retained
   device queue and uncertain command recovery on the real phone. A request
   exceeding its route limit returns a definite 413 before upstream dispatch;
   larger native import routes require the separate abuse-control qualification
   above. A failure after dispatch remains an unknown 503 outcome.

The local tests use synthetic profiles, keys, mocked HTTP and request metadata.
They do not prove actual Cloudflare ingress, Supabase gateway behavior, device
reachability, provider delivery, financial authorization or release readiness.

```sh
node --test deploy/managed-native-ingress/worker.test.mjs \
  supabase/functions/_shared/tests/native-ingress-hardening.test.mjs \
  supabase/functions/_shared/tests/native-ingress.test.mjs \
  deploy/self-hosted/native-ingress.test.mjs
```
