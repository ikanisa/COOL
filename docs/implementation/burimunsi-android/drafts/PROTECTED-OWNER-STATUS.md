# Protected owner identity: registered for testing

`protected-owner-identity.draft.sql` was registered, byte-for-byte, as
`supabase/migrations/20261111121400_collect_protected_owner_identity.sql`
(SHA-256 `8330530ee441825f4d06f4ba1d8664b81f50472502593c9d84592bd8cccded14`).
The SQL's original unregistered-draft comment is retained as part of the exact
reviewed bytes; its registration status is recorded here and in the lock.
It binds a verified existing owner or a fresh operator-initialized owner to a
protected singleton; immutable historical migrations remain unchanged. It does
not authorize an owner transfer. Its retention class remains explicitly unknown
and blocked rather than treated as erased.

A disposable PostgreSQL 17 rehearsal applied the current 44-migration chain and
initialized a different synthetic owner, then exercised confirmed synthetic
Auth/session proof, native login contracts, current-owner invitation authority,
owner identity controls and the retention inspection. No real Auth users,
provider, email or customer records were used. Evidence:
`/Users/jeanbosco/Documents/Supabase/burimunsi-observation-synthetic-20261111/run-036-owner-alternate-pass/`.
The existing-owner and alternate-owner SQL contracts, protected v1/v2 target
checks, actual Admin HTTP/PostgreSQL integration, and a Flutter-to-HTTP/PG
synthetic scenario were also exercised. The targeted concurrency rehearsal
tested session and grant revocation in both lock orderings against actual owner
attestation and guarded mutation batches. Its evidence is
`/Users/jeanbosco/Documents/Supabase/collect-owner-concurrency-20261111-02/`.

The session disclosure and transactional dynamic-authority branches are staged
behind the separate `COLLECT_ADMIN_OWNER_IDENTITY_ENABLED` and
`COLLECT_ADMIN_DYNAMIC_OWNER_AUTH_ENABLED` flags, both default off. Missing or
invalid protected identity must disable owner controls. The session DTO is not a
substitute for the existing cookie, current grant, fresh-email and mutation
transaction checks. Sender configuration is separate from owner identity; the
existing Workspace sender remains fixed in the legacy transport.

Registration changes source only. Both server flags remain off in the live
configuration; the synthetic results do not establish live migration, browser
cookie persistence, provider behavior, or deployment.
