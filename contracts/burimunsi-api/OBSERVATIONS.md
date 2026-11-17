# Native observation contract

This extension is disabled by default and requires its qualified private schema. A native phone/PIN session and its existing installation proof are required. The server derives account, collection, grant and installation from that proof; a request cannot select a receiving wallet.

`GET` and `POST /sms/observation-consent` return `{enabled,generation}`. The generation starts at zero when unset and increases on each permission change; an exact retry is idempotent. An older or conflicting value is rejected. `GET /sms/observation-profile` returns one current provider candidate-filter profile, valid for 24 hours. A separately operator-configured detection-only profile can be used while the receiving account itself remains unverified. Its collection/account scope prevents stale configuration from being reused after scope changes; it does not identify the wallet that received a message or approve the account for financial processing. If no separate profile is configured, the existing approved account profile can supply the filter. A disabled, stale, or invalid profile blocks capture.

`POST /sms/observations` accepts a stable request UUID and exact source text. The body is limited to 3,000 UTF-8 bytes. A live capture must have `complete: true`; catch-up must have `complete: false` and a non-null `inboxReceivedAt`. The service-centre timestamp and subscription ID may be null. Timestamps and subscription IDs are untrusted device metadata, not evidence of wallet ownership. The acknowledgement echoes the request UUID and SHA-256 of the exact UTF-8 raw body. `source_unresolved` and `financialEffects: 0` mean only encrypted private retention; they do not mean parsing, recipient identification, allocation or posting.

`GET /sms/observations` lists only the current authorized admin account's own consenting installation and grant. Its metadata-only `q` searches source IDs, not sender or message content. Its cursor is tied to the account, installation, filter and current snapshot. `POST /sms/observations/{id}/reveal` requires a review reason and records an audit event after checking the source, storage journal, current session, consent and separate read/reveal grants. This path does not loosen the existing canonical paired-receiver SMS reader. A managed Collect Admin review adapter uses its own default-off `BURIMUNSI_ADMIN_SMS_OBSERVATIONS_ENABLED` server flag, independent of the native `BURIMUNSI_SMS_OBSERVATIONS_ENABLED` flag; the adapter and its unregistered database draft are in source; they require qualification. Provisional extraction, evidence-based receiver resolution, posting and retention-catalog coverage remain separate work.

## Optional provisional display hints

A client may opt in to version 1 on an authorized raw reveal. With the separate `BURIMUNSI_OBSERVATION_HINTS_ENABLED` server flag disabled (the default), or if the approved capture-time provider tuple no longer matches, the response is `displayHints: null`. A non-null hint contains only exact UTF-16 spans and quotations from an incomplete inbox message, bound to its body digest and the approved profile version and JSON digest. It is provisional display text: it does not establish a sender, a recipient, a receiving account, a transaction or a financial effect. Legacy reveal requests omit the field. Admin clients additionally require their own default-off `BURIMUNSI_ADMIN_OBSERVATION_HINTS_ENABLED` build option.

The detection-only filter can supply display quotations only when its exact capture-time version, contents, collection/account scope, evidence identity and revision still match at disclosure. Changing or disabling it returns no hints; the filter never changes the receiving account's approval status. The testing migration is registered in source; the runtime feature remains disabled pending coordinated activation.

## Admin recovery: required before activation

The candidate Collect Admin MoMo source workflow has a read-only view of observation admissions for the operator's currently approved collection. A currently authorized collection Admin can see historical admissions from all contributors, including uploaders who were later revoked; revocation does not authorize the uploader to access them. It must show the source and request IDs, server admission time, and whether the retained source is confirmed or the storage/commit outcome is still unresolved. A missing journal row is not proof that no upload is in flight. The view must not expose PINs, bearer/device secrets or SMS text, and it must not imply that a receiver or payment has been identified.

The server must bind this view to the current managed Admin session, an active approval for each collection, and the independent `sms.read` grant and role ceiling. Original-text disclosure additionally requires the independent `sms.reveal` grant, the current canonical sensitive-operation assurance (including fresh Admin email verification where required), a reason and an audit event, with session, authorization, source and storage rechecked after object retrieval. The existing canonical source list and its access checks remain intact.

A pending or uncertain admission must not be deleted, automatically replayed, or reported as a successful capture. If an exact retry verifies retained bytes while the original upload outcome remains unknown, the server returns `observation_upload_unresolved` with HTTP 503; the encrypted reservation and original admission remain pending for operator recovery. The original phone can retry the same request and fingerprint while its account, installation and consent remain valid; the server reconciles that exact operation against the retained journal. If the original installation is unavailable or revoked, an operator needs a separately reviewed recovery procedure. Admission counts and saturation require a scoped diagnostic view that does not expose another collection's records.

The Admin API and its SQL are registered in the testing source but are not deployed, and the API flag remains off. The loss-of-installation recovery procedure and capacity diagnostic remain unimplemented. Activation remains blocked until those are implemented and the complete path is tested, including cross-collection isolation, revoked permissions, fresh-email expiry, audit failure, in-flight commits, unknown storage outcomes and saturated admission capacity. Retention inspection deliberately reports unknown mappings and object custody, and erasure remains blocked until a separate disposition is reviewed.

### Request-bound uncertain upload

A `POST /sms/observations` may return HTTP 503 with the existing error code
`observation_upload_unresolved`. When, and only when, the server has
revalidated the current authorized account and exact durable request plus its
matching encrypted reservation and monotonic unresolved-upload journal, that
response also contains these single-valued headers:

- `X-BuriMunsi-Observation-Unresolved: v1`
- `X-BuriMunsi-Observation-Request-Id: <original requestId>`
- `X-BuriMunsi-Correlation-Id: <X-BuriMunsi-Request>`

The values assert request identity over the existing authenticated TLS request;
they contain no SMS body or SMS-derived digest. They do not acknowledge an
observation, prove the provider's final outcome, or authorize a ledger effect.
The client validates all three headers against its in-flight request and retains
that exact encrypted queue entry. Missing, malformed or duplicate headers,
other 503 errors, authorization failures and capacity limits do not justify
continuing the queue under this special case. A later exact retry checks the
journal before any Storage call while the unknown flag remains set.
