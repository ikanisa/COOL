# Cloud native handler integration tests

Run `node --test deploy/managed-native-ingress/handler-integration/handler-integration.test.mjs` from the checkout.

The tests exercise the current Collect API handler and entrypoint, the Cloud
frontdoor, signature verification, application admission and committed nonce
claims. Synthetic adapters cover concurrent replay, lost acknowledgements,
cancellation, unavailable dependencies, a large approved preview, and ordinary
CORS and non-native routes. The scheduler tests exercise its receipt and
financial-work gates and check bounded output from the native SMS ledger lane.

The input manifest binds the exact local source and test fixture bytes used by
this suite. The preserved predecessor digest identifies the earlier review.
