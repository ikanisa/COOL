# Held SMS recovery v2 candidate

This is a default-off candidate. Do not activate it or apply its migration
until the exact source, migration order, catalog, operational fence, app and
device behavior have passed independent release qualification.

The authenticated capability is `GET /sms/observations/recovery-v2/capability`
with the single canonical decimal query parameter `expectedConsentGeneration`.
The client uses a fresh normal request binding and requires `Cache-Control:
no-store`. The strict native envelope binds request UUID, session generation,
account, installation and collection. Its data contains the fixed protocol
`burimunsi.held-recovery.v2`, `groupId`, `sourceSha256`, `migrationSha256` and
`consentGeneration`. The client must compare these to its own approved pins and
original protected-journal generation; it must not cache a capability.

The distinct endpoints are `POST /sms/observations/recovery-v2/hold` and
`POST /sms/observations/recovery-v2/ack`. GET and both POSTs require the exact
independently pinned lowercase SHA-256 values in
`X-BuriMunsi-Held-Source-Sha256` and `X-BuriMunsi-Held-Migration-Sha256`.
Missing, malformed, duplicated or changed values fail before the SMS body is
read. The adapter compares that tuple with its running configuration and checks
the source fence, migration history, current consent and catalog again in the
admission transaction. Both response types include the v2 protocol and the
original `expectedConsentGeneration`. The ACK remains read-only and always
reports `retryAllowed:false`; neither a capability nor an unconfirmed ACK
authorizes a repeated submission.

The running-source digest is supplied by the release environment and compared
with the admitted work tuple and database fence. The migration digest and
guard-function digest are compiled release pins and checked against the actual
database; the migration does not embed its own digest. These checks establish a
controlled release binding for the trusted service, not independent remote
attestation of a malicious server. The numeric consent generation is supplied
by the client and cannot prove what an unseen or compromised client originally
stored, or independently prove the original grant/version.

The in-memory PostgreSQL fixture installs the exact pinned predecessor function
bodies on synthetic tables and checks successful readiness plus trigger, ACL and
consent drift. Its support functions and data are synthetic and it has one
backend. It does not establish full-chain migration compatibility, production
catalog state, true two-connection races, live Edge/proxy behavior, or Android
interoperability. Legacy ATTEMPTING entries without the saved consent value
remain unresolved. Existing ordinary SMS requests are unchanged; the old held
routes remain unavailable through v2 production composition.
