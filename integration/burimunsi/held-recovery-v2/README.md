# BuriMunsi held recovery v2

Held recovery v2 binds an original, confirmed SMS capture consent to one held submission. A capability response proves that the service reports the expected release and consent. A separate read-only acknowledgement can confirm an earlier submission without allowing a resend or creating a financial effect.

This integration fixture uses synthetic observations and an in-memory database and store. The protocol harness requires an explicit `enabled: true` and an exact source and migration digest. The active Edge profile, Android source sets and Supabase migration chain exclude this directory.

## Local checks

With Node and the existing `scripts/supabase` locked dependencies installed, run these commands from the repository root.

```sh
node --test integration/burimunsi/held-recovery-v2/*.test.mjs
integration/burimunsi/held-recovery-v2/android/verify.sh
```

The second command uses Kotlin 2.3.21 and JDK 17. It compiles the candidate journal against the current BuriMunsi core and an in-memory secure-store double.

The [protocol](PROTOCOL.md) covers the proposed transaction boundaries, SHA-256 pins and remaining qualification. Promotion requires independent evidence for the full managed migration chain, real role membership and concurrent catalogue drift, authenticated Edge and Android interoperability, and consent at every persistence boundary.
