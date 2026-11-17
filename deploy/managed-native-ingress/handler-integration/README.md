# Managed native handler integration proposal

**Integrated in the working source; not deployed.** This directory retains the
reviewed preimages, patch and candidate copies of `serve.js` and
`collect-api/index.ts`. The patch was applied to the working source after its
preimage guard passed. The source scheduler also contains a later SMS-ledger
lane; the manifest pins the current source, and tests separately check that
the reviewed request handler is unchanged and that lane preserves admission
and reports unknown outcomes. The verifier defaults to the original checkout;
CI may supply its exact physical checkout path through `COLLECT_HANDLER_CHECKOUT_ROOT`.
Relocation never bypasses the byte checks. If an input changes, reconcile and retest it.

For an enabled managed native route, the candidate requires the verifier,
claim function and nonce adapter before database setup. It verifies the signed
request to an opaque token, initializes the database and existing application
fence, checks cancellation, and claims the token through the fence-bound
adapter. Storage, provider and native setup and dispatch follow only an
acknowledged committed claim. The database initialization and fence admission
are internal work that occurs before the claim; this proposal does not claim
otherwise. Missing functions, malformed results, direct unsigned calls, duplicate
nonces, claim errors and lost acknowledgements fail closed. Managed native
routes with the feature disabled stop before DB setup. The generic handler
cannot silently skip the verifier, and other function names cannot serve native
paths. The existing non-native and CORS preflight paths remain unchanged.
The current shared scheduler's default-off financial-work lane is retained,
including its pause, retention hold and unconfirmed-status behavior.

The `collect-api` candidate entrypoint passes the actual
`admitNativeIngress`, `verifyNativeIngress`, `claimNativeIngress` and
`consumeNativeIngressNonce` functions. Enabled self-hosted requests keep the
existing one-step admission and exact signature; a missing self-hosted verifier
is now denied. That legacy path does **not** gain durable replay protection
from this patch. Disabled self-hosted behavior remains unchanged.

## Validation and remaining integration

Run from the active checkout with the current Node toolchain:

```sh
node deploy/managed-native-ingress/handler-integration/verify-inputs.mjs
node --test deploy/managed-native-ingress/handler-integration/handler-integration.test.mjs
```

The synthetic harness imports the integrated working-source handler and
entrypoint, verifies their request-handling portions match the reviewed candidate, the real ingress signer/verifier/claim code, the real nonce adapter,
the real route detector and the actual managed frontdoor. Its DB, fence,
storage, provider and domain-dispatch adapters are controlled in-memory test
doubles. It checks verification and claim ordering, concurrent replay, lost
commit acknowledgement, missing options, cancellation, direct-route denial,
non-native and self-hosted compatibility, and a large managed preview. These
tests do not prove a durable database claim, deployed Deno behavior, Cloudflare
provenance, managed gateway settings, client compatibility or a device flow.
The scheduler checks import the actual financial-work and SMS-result modules
and exercise admission, redaction, default hold and pause. SMS-ledger processing
and other scheduled dependencies remain test doubles; these checks do not
qualify the new ledger worker or its financial effects.

A separately reviewed versioned nonce ledger and production roles/privileges
are required. The adapter must use a transaction whose `true` result is returned
only after COMMIT is acknowledged; a timeout or unknown commit must abandon
fenced work and never retry the same attestation. Before deployment, independently verify the
actual route, direct-backend denial, key isolation, body/rate limits and rollback.
No migration, deployment or real provider request is made by this proposal.
