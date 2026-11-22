# Managed native ingress candidate

This module supplies a narrowly scoped Supabase Cloud frontdoor for BuriMunsi.
Its route and client require qualification before enabling native operations.

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
addition to the existing authority and native headers. The managed proof record must be canonical JSON with precisely these fields:

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
The current `collect-api` entrypoint integrates that verifier and the
fence-bound nonce adapter. The signed frontdoor flow requires an approved
Cloud profile and reviewed route configuration.

The separately configured direct Supabase mode checks the exact project origin
and strips client-supplied forwarding headers. A signed request uses the
Worker verification and committed nonce claim.

Only exact POST `/v1/burimunsi/members/import` and
`/v1/burimunsi/members/import/preview` without a query receive the existing
524,288-byte and 6,991,532-byte wire limits respectively; other routes retain
8,192 bytes. The frontdoor must read these bytes before the backend can check
the HMAC, so provider-side rate, concurrency, memory and body limits must be
qualified before enabling large routes.

## Worker deployment checks

1. Bind the intended Cloudflare Worker to the profile’s member API hostname
   and route the two native path forms to this handler. Keep the signing key
   scoped to the Worker and `collect-api`. A shared Worker gives every module
   access to its bindings. Receiver `/v1/functions/*` routes use their own
   signed gateway protocol.
2. Configure the Android native API and native email-OTP destinations for the
   selected route. The Supabase Auth issuer is the Cloud project origin plus
   `/auth/v1`. Check native OTP and browser origin handling on the actual route.
3. Test against the actual Cloudflare route that direct clients receive the
   correct `CF-Connecting-IP`, same-zone and cross-zone Worker subrequests and
   forged IP/forwarded headers cannot obtain arbitrary signed network buckets,
   and Pseudo IPv4 is off. Verify no unqualified Worker service binding or
   alternative route can invoke the signer. Cloudflare notes that same-zone Worker subrequests
   can alter `x-real-ip`; a header value alone is not proof of provenance.
   [Cloudflare HTTP headers](https://developers.cloudflare.com/fundamentals/reference/http-headers/)
4. Confirm the deployed `collect-api` uses the appropriate function gateway
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
  supabase/functions/_shared/tests/native-direct-supabase-ingress.test.mjs \
  supabase/functions/_shared/tests/native-ingress-nonce.test.mjs \
  deploy/managed-native-ingress/handler-integration/handler-integration.test.mjs
```
