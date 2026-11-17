# Collect Edge function capture preparation

This is a synthetic-only preparation. `captureManaged` unconditionally refuses;
no provider read, source capture or deployment is performed by the current
managed entry point. A usable live successor requires an independently reviewed,
source-pinned and cancellation-supervised launcher and fresh verification of its
provider response format. Do not treat this directory as a production backup.

The synthetic path tests a proposed encrypted archive for the fixed project and
three slugs `collect-api`, `admin-api` and `collect-jobs`. It uses only injected
fixture responses in a private temporary directory. Injection is a testing
convenience, not a network sandbox: a malicious caller could supply a transport
that performs unrelated network calls.

The archive contains the complete opaque fixture response bodies and selected
function metadata, sealed with AES-256-GCM. Project, operation and plan bindings
are authenticated. The key is a separate owner-only 32-byte file in a different
private directory, but independent key custody is not established. Readback
verifies authentication and local body digests without returning body contents.
The receipt retains slug, function ID, active status, version, update time,
provider-reported upload digest if supplied, response digest and byte count.
Metadata is checked before and after each body, while identity, inactive
functions, duplicate IDs, replay and deployment drift fail closed. After a
claim is created, the outcome records failure as unconfirmed; if an outcome
cannot be written, the retained claim itself requires reconciliation. There is
no automatic retry.

Supabase documents a [function metadata endpoint](https://supabase.com/docs/reference/api/v1-get-a-function)
and a [function body endpoint](https://supabase.com/docs/reference/api/v1-get-a-function-body).
The body endpoint documentation does not establish that its returned bytes are
identical to the originally uploaded EZBR representation. Therefore the receipt
reports whether the two hashes happen to match; it does not interpret a mismatch
as corruption or a match as proof of deployed behavior. Actual response format
and usefulness as source have not been observed or validated in this work.

Provider configuration and provider secret configuration are not captured.
Source text can itself contain sensitive literals, so the opaque bodies are
treated as sensitive even when the provider's secret configuration is absent.
No plaintext source or credentials are intentionally written to files or logs;
buffers and token strings still exist in process memory and may reach swap,
crash dumps or other system-level records. Buffer clearing is best effort.
There is no extracted source inspection, no deployability or restore test, no
cross-function snapshot guarantee, and no protection against same-user or
privileged changes after the point-in-time checks.

Run the synthetic checks from the physical checkout:

```sh
env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin LC_ALL=C \
  /Volumes/PRO-G40/Development/Node/bin/node --test --test-concurrency=1 \
  scripts/supabase/managed-edge-capture/capture.test.mjs
```
