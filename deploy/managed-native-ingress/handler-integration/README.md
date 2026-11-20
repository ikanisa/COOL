# Managed native handler integration

Collect native ingress uses the managed Supabase Cloud project. The synthetic
integration suite exercises the shipping Edge handler and managed front door with
in-memory database, Storage and provider adapters. It checks signature and nonce
admission, concurrent requests, unknown commit outcomes, cancellation, direct
access rejection and large preview requests.

Run from the repository root.

    node --test deploy/managed-native-ingress/handler-integration/cloud-only-handler-integration.test.mjs
