# Collect Cloudflare recovery

The canonical database is `collect-platform` (`a6a0d284-c445-4fe3-8e64-af5fd42491ae`). The app uses `collect-platform-api`; the Admin uses its same-origin service binding. The platform starts from its reviewed schema; no legacy import is required.

`platform_backup.mjs` seals a full D1 SQL export, the matching public Worker configuration, the complete contiguous migration sequence and the exact configured recovery secret roles into an authenticated AES-256-GCM archive. The three core roles are `AUTH_JWT_SECRET`, `AUTH_TOKEN_HASH_SECRET` and `DATA_ENCRYPTION_KEY`. A nonempty public `TURNSTILE_SITE_KEY` additionally requires the exact `TURNSTILE_SECRET`. The explicitly qualified optional `DATA_DECRYPTION_KEYS_JSON` role is retained if present; omission of a configured Turnstile role, malformed/wrapped values, orphan provider secrets and unknown roles are rejected. Legacy captures with no configured site key remain readable with their three core roles. Future delivery/provider secret roles need explicit recovery qualification before activation. Receipts list names only, never secret values. Existing eight-migration archives remain readable; a newer capture must include each additional migration in order. The independent recovery key and cleartext inputs belong in a private directory outside the checkout. Never add them to Git, web assets, reports or CI artifacts. The tool rejects symbolic-link traversal, hardlinked input files, permissive private-file modes, substituted archive roles, damaged ciphertext and incorrect keys.

Use Node 24.19.0 and the locked Wrangler 4.151.0 runtime. With a protected output directory and `umask 077`, export with the exact release configuration:

```sh
node /qualified/node_modules/wrangler/bin/wrangler.js d1 export collect-platform --remote --output /private/capture/database.sql --config /exact/release/wrangler.jsonc
node scripts/cloudflare/platform_backup.mjs seal --sql /private/capture/database.sql --config /exact/release/wrangler.jsonc --secrets /private/worker-secrets.json --out /private/new-encrypted-capture
node scripts/cloudflare/platform_backup.mjs verify-local --archive /private/new-encrypted-capture/platform-backup.json --key /private/new-encrypted-capture/recovery-key.base64 --out /private/new-isolated-restore --wrangler /qualified/node_modules/wrangler
```

Each output directory must be new. Keep failed attempts and inspect their private diagnostics before retrying. The actual D1 export can block other database requests while it runs; use an agreed maintenance window for a populated service. See [Cloudflare export guidance](https://developers.cloudflare.com/d1/best-practices/import-export-data/) and [Time Travel](https://developers.cloudflare.com/d1/reference/time-travel/).

The verifier decrypts the archive, checks every captured file, restores the database into isolated local D1, then compares every user table and row, allocation sequence, index, trigger and view against an independent SQLite reconstruction. It creates all table definitions before inserting data to handle D1 exports whose child tables precede their referenced parents. Foreign-key and integrity checks must pass. It never starts an authenticated app, restores remotely, changes hosted grants or reactivates a session.

`verify-local` also emits `restore-tables.sql`, `restore-data.sql`, `restore-indexes.sql` and `restore-triggers.sql`. The data phase orders populated referenced tables before their dependents. Populated foreign-key cycles or views requiring another dependency order are refused for this phased path; they require a separately qualified recovery method. The original transactional `restore.sql` remains a local replay artifact.

For a hosted drill, provision a new database in the verified account and leave it unbound to any Worker. Create a separate configuration whose only binding, `RESTORE_DRILL`, identifies that new name and UUID. The recovered `wrangler.json` still identifies the original database and must not be used as the import target. Import the four generated phase files in the order above using the qualified Wrangler `d1 execute RESTORE_DRILL --remote --config /private/drill/wrangler.jsonc --file /private/new-isolated-restore/restore-tables.sql --yes` form. Capture each result privately. After an error or an unknown outcome, export and inspect the drill state before another write; do not resend an import blindly.

Export the completed drill through its separate configuration, then compare that SQL with the authenticated archive:

```sh
node scripts/cloudflare/platform_backup.mjs verify-readback --archive /private/new-encrypted-capture/platform-backup.json --key /private/new-encrypted-capture/recovery-key.base64 --sql /private/drill/hosted-readback.sql --out /private/new-readback-verification
```

This offline comparison checks all captured rows, schema objects, sequences, foreign keys and integrity. Preserve the separately captured provider account, target UUID, commands and results to establish where the SQL came from; this offline command alone cannot prove remote execution. Remove only the agent-created, unbound drill database after its recovery evidence is retained.

The 15 October 2026 API9 drill restored the fresh captured state into an independent hosted D1 and independently exported it again: 68 tables including `sqlite_sequence`, all captured rows, 24 indexes and 90 triggers matched, with zero foreign-key errors. Initial whole-file imports returned `D1_RESET_DO`; alphabetical data replay failed foreign keys. Those failures remain recorded. Parent-first phased replay succeeded. The original database was never an import or deletion target.

A successful DB result proves the captured database, configuration and key recovery scope. The R2 commands below separately verify captured current-object bodies and their recoverable metadata; they do not restore bucket version history, lifecycle rules or provider resources. External OTP/Turnstile/notification configuration, independent key custody, application cutover after disaster recovery, offsite retention, legal holds and accepted RPO/RTO remain separate requirements. An empty domain database does not prove an empty object bucket.

An exact restored snapshot can contain accounts and credentials revoked after capture. Keep the restored database unbound, network access and external sends disabled, and do not reuse its public Worker routes or provider credentials. Prepare a separately quarantined copy before considering application cutover:

```sh
node scripts/cloudflare/platform_backup.mjs prepare-quarantine --archive /private/new-encrypted-capture/platform-backup.json --key /private/new-encrypted-capture/recovery-key.base64 --operation YOUR_SAVED_OPERATION_UUID --at YOUR_CANONICAL_UTC_TIMESTAMP --out /private/new-quarantine
```

Save a fresh operation UUID and canonical whole-second UTC timestamp first, and retain them for unknown-outcome reconciliation. The timestamp must follow capture. Preparation authenticates the archive, requires the nine explicitly qualified migration bodies and the exact application catalog, and changes only a private in-memory copy. Later schemas require explicit recovery-policy qualification. `quarantine-plan.json` contains the fixed policy as parameterized statements. Execute those statements in **one transaction or one D1 `batch`**, only on a separately identified, verified isolated restore; this tool has no remote executor. Do not feed the plan to the live database or execute its statements separately. `quarantined-restore.sql` is a complete local SQLite transactional replay artifact, not a qualified hosted D1 import.

Quarantine revokes saved bearer sessions, suspends all active principals, revokes Admin accounts and removes their restored passwords, supersedes outstanding OTPs, disables pending/verified MFA factors, exhausts pending MFA challenges, and consumes outstanding invitation/reset links. Existing final revocations and deleted principals are preserved. Refresh tokens, native admissions, original provider work states, financial records, object references and request/verification history remain retained. Their originating revoked sessions prevent reuse. Account-owned grants and cookie rows change through existing authority triggers. A retained, archive-bound audit marker makes an exact retry a readback; conflicting operation reuse fails before mutation. A retry does not revoke credentials separately approved after that operation.

Export a separately executed quarantined restore, then use the dedicated verifier:

```sh
node scripts/cloudflare/platform_backup.mjs verify-quarantine-readback --archive /private/new-encrypted-capture/platform-backup.json --key /private/new-encrypted-capture/recovery-key.base64 --plan /private/new-quarantine/quarantine-plan.json --sql /private/quarantined-readback.sql --out /private/new-quarantine-verification
```

This compares every row, catalog object and sequence against the authenticated snapshot plus exactly that policy. The ordinary `verify-readback` intentionally rejects this changed snapshot. Offline comparison does not prove where execution occurred. Preserve the separate target, execution and export evidence. SQL quarantine does not stop provider sends or rotate Worker secrets. Before cutover, reconcile post-snapshot revocations, obtain independent custody approval, rotate signing/token credentials, reconcile encryption-key/object access and explicitly reapprove accounts with fresh credentials and MFA. No automatic account reactivation or owner recovery bypass is provided. Full application recovery and RPO/RTO acceptance remain open.

Run the tampering, key, archive-role and SQL isolation regressions with:

```sh
node --test scripts/tests/platform_backup_test.mjs scripts/tests/recovery_quarantine_test.mjs
```

Current Auth17 synthetic recovery, including the historical controls and exact
candidate13/17 view handling, runs with `node scripts/qa/recovery17_ci.mjs` from
the repository root. CI and `make cloudflare-platform-test` run this same command
with Node24.19.0 and the locked Wrangler4.151.0 dependencies. Existing explicit
vendor-module locators may be supplied for a qualified local runtime. The command
removes private `ACTUAL13_SQL` and development-refusal selectors from its child
environment: its216 synthetic tests do not include the separately recorded
private current13 capture case or establish production recovery acceptance.

The backend `test/recovery_quarantine.test.mjs` exercises this policy against real isolated workerd/D1/R2 and the actual authentication handlers, with synthetic accounts, populated financial records and controlled outbound acknowledgements. These tests do not establish hosted cutover or real provider admission.


## Authenticated R2 bodies and independent readback

The R2 commands stream object bodies into a separate AES-256-GCM bundle bound to the exact existing platform archive SHA-256, source ID, database and authenticated `PRIVATE_MEDIA` bucket. They reuse its recovery key with distinct manifest/body authentication contexts and fresh nonces; no new recovery secret is generated. Each body is named by the SHA-256 of its object key, so even an R2 key containing slashes or `..` never becomes a filesystem path. Original object keys, metadata, upload/version observations and plaintext-body hashes stay inside the encrypted inventory. Inputs and recovery outputs must be private, independent files outside the checkout. Do not publish an object inventory or recovered bodies.

The input is a private JSON capture with exactly these fields:

```json
{
  "format": "collect.r2.capture.v1",
  "bucket": "collect-platform-private",
  "source_id": "THE_EXACT_64_HEX_PLATFORM_SOURCE_ID",
  "captured_at": "2026-10-16T12:00:00.000Z",
  "before": {
    "prefix": "",
    "delimiter": null,
    "include": ["httpMetadata", "customMetadata"],
    "pages": [{
      "cursor": null,
      "truncated": false,
      "next_cursor": null,
      "objects": [{
        "key": "controlled/example.bin",
        "size": 6,
        "etag": "THE_ACTUAL_PROVIDER_ETAG",
        "version": "THE_ACTUAL_PROVIDER_VERSION",
        "uploaded": "2026-10-16T11:00:00.000Z",
        "httpMetadata": {"contentType": "application/octet-stream"},
        "customMetadata": {},
        "storageClass": "Standard"
      }]
    }]
  },
  "after": "THE_SECOND_COMPLETE_LISTING_WITH_THE_SAME_OBJECT_METADATA",
  "downloads": [{
    "key": "controlled/example.bin",
    "etag": "THE_SAME_ACTUAL_PROVIDER_ETAG",
    "version": "THE_SAME_ACTUAL_PROVIDER_VERSION",
    "sha256": "SHA256_OF_THE_FULL_DOWNLOADED_BODY"
  }]
}
```

The labelled strings are documentation placeholders, not valid capture values. `after` must be another complete listing object, not a string. Obtain actual unfiltered R2 listings before and after downloading every current body. Preserve all pages, including empty intermediate pages; use the provider's `truncated`/cursor state, never object count, to establish completion. Every nonterminal page must name a new next cursor, and the next page must identify that cursor; the final page must set `truncated:false` and `next_cursor:null`. A changed version, key, size or metadata between the two listings is refused. Each `downloads` observation must identify the actual etag and available provider version returned for that body. Workers R2 observations carry a version ID. The documented REST object listing does not expose that field; for that path use explicit `version:null` in both listing and download observations, preserve the actual etag/upload time/full-body hash, and retain the raw REST provenance. Receipts count unavailable version IDs, and never claim version-history recovery. Missing metadata must be captured, not guessed. See [Cloudflare's R2 object/listing contract](https://developers.cloudflare.com/r2/api/workers/workers-api-reference/) and [REST listing fields](https://developers.cloudflare.com/api/resources/r2/subresources/buckets/subresources/objects/methods/list/).

Place the exact downloaded body for each key at `/private/capture/objects/SHA256_OF_UTF8_OBJECT_KEY.bin`, with no other files or subdirectories. Each body must match its listing size and download SHA-256. Objects are streamed, including empty bodies; the qualified limits are 10,000 current objects, 5 GiB per object and a bounded 64 MiB control-file inventory. The tool rejects missing/extra objects, incomplete or filtered listings, aliases, permissive modes, changed input files and damaged ciphertext. It also refuses a bucket inventory missing any nonnull `object_key`/`*_object_key` referenced by the captured D1 tables.

```sh
node scripts/cloudflare/platform_backup.mjs seal-r2 --archive /private/platform/platform-backup.json --key /private/platform/recovery-key.base64 --inventory /private/capture/inventory.json --objects /private/capture/objects --out /private/new-encrypted-r2
node scripts/cloudflare/platform_backup.mjs restore-r2 --archive /private/platform/platform-backup.json --key /private/platform/recovery-key.base64 --bundle /private/new-encrypted-r2 --out /private/new-independent-r2-restore
```

`seal-r2` independently decrypts and hashes every newly written archive body before issuing its receipt. `restore-r2` reads that encrypted bundle independently, writes each exact body into a new private directory and emits a private `restore-index.json` containing the recovered metadata and original provider observations. Only a complete successful run emits `verification.json`; retain and investigate partial failed outputs before retrying into a different fresh directory. An authenticated R2 body is still the application's original ciphertext where applicable. The tool independently checks the recovered `DATA_ENCRYPTION_KEY`, `DATA_KEY_ID`, AES-GCM context, plaintext size and D1 digest for every captured payment-evidence, SMS-receipt and roster-source record. It never writes their decrypted application plaintext or prints credentials/content. Exact historical-kid selection is supported only through the authenticated optional keyring described below; there is no key probing or fallback to a different ID. Other object bodies are preserved and hashed; application-reader semantics for future object types require separate qualification.

For a hosted drill, create a separately named private bucket in the verified account, keep it unbound to public application routes and preserve its original empty-state/provider identity evidence. Use the private restore index to upload the recovered exact body bytes with the recovered HTTP/custom metadata and storage class. Provider-generated version, etag and upload time may change; preserve the original observations as provenance rather than fabricating them on the new upload. List the full isolated bucket before and after downloading every restored body into another private capture directory, using the same capture format and source ID but the isolated target bucket's name and actual new provider observations:

```sh
node scripts/cloudflare/platform_backup.mjs verify-r2-readback --archive /private/platform/platform-backup.json --key /private/platform/recovery-key.base64 --bundle /private/new-encrypted-r2 --inventory /private/isolated-readback/inventory.json --objects /private/isolated-readback/objects --out /private/new-isolated-object-verification
```

The verifier refuses the primary bucket's name, verifies that the backup remains decryptable, checks every target body byte against its independently recovered hash, requires the exact full key set and recoverable metadata, and repeats the application data-key/DB-reference checks. It performs no network calls, uploads, production writes or deletions. Separately retain the actual account, target bucket, requests/results and listing/download provenance; an offline JSON observation does not prove its provider origin. Current-object verification does not establish deleted/previous versions, lifecycle/retention policy, simultaneous DB/R2 snapshot consistency, legal-hold handling, independent key custody, accepted RPO/RTO, disaster cutover or full-system recovery acceptance.


## Optional retained data keys

`DATA_DECRYPTION_KEYS_JSON` is a qualified optional recovery secret role, not a newly configured service secret. Existing three-core/four-with-Turnstile captures remain valid without it. If a capture's exact secret-source file includes the role, its original string bytes are authenticated and recovered unchanged. Validation does not add, create, configure, rotate or deploy any key.

The role mirrors the shipping encryption contract: a string no larger than 4,096 UTF-8 bytes; an empty string means no historical keys, and `{}` is valid. A nonempty map contains at most eight literal ASCII IDs matching `[A-Za-z0-9][A-Za-z0-9._:-]{0,127}`, each mapped to literal canonical standard base64 for exactly 32 bytes. Only JSON whitespace is allowed around entries. Duplicate raw IDs, escaped aliases/values, trailing commas, nested/non-string values and noncanonical base64 are refused before JSON overwrite could hide them. Distinct IDs must have distinct key material. A redundant active-ID entry is allowed only when its bytes exactly equal the active key; a historical alias to the active material, two historical aliases sharing material or a conflicting active-ID entry is refused. The active `DATA_KEY_ID` and `DATA_ENCRYPTION_KEY` must remain valid even for an empty or historical map.

Application-object recovery selects the current key only for the current exact `kid`, or the explicitly retained key for that exact historical `kid`. It retains the original v1 envelope and AES-GCM context; an unknown ID, wrong key, wrong context, malformed ring or damaged body cannot produce a successful recovery receipt. The current encryption key remains the sole encryption key in the backend; this recovery tool never reencrypts application evidence under another ID. Old-key custody, rotation authority, retention/disposal and proof that all retained objects remain readable require their own accepted operational procedure. Local historical-key fixtures are compatibility evidence, not proof that a historical keyring has been configured or deployed.
