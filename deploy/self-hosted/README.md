# Collect on locally hosted Supabase

This package runs Collect's business backend, database, Auth, Storage, Realtime,
Edge Functions, notification outboxes and OpenSMS custody in the locally hosted
Supabase installation. The mobile application and Admin consume an explicit,
hashed deployment profile. Managed-project defaults are retained only for
existing builds without an explicit profile; they are not the destination of
this package.

The implementation and qualification record is in
[`docs/implementation/self-hosted-20261101`](../../docs/implementation/self-hosted-20261101).
Local qualification does not establish a live installation, complete restore,
provider delivery, signed Android update, installed PWA acceptance or production
cutover. The original numbered production criteria remain the release criteria.

## Architecture and boundaries

The reviewed upstream is Supabase self-hosted v0.8.3, commit
`bc27d2661edd09a5d0b8d76ce33da6d4071a756e`. `upstream.lock.json` records every
vendored file and `images.lock.json` records immutable image digests. The
application uses PostgreSQL 17; a moving container tag is not an accepted
replacement. Vendor files stay byte-identical. Application configuration is
generated separately by `scripts/self_hosted/prepare.py`.

The resulting Compose deployment has 13 services. Only the Caddy proxy publishes
host ports (80 and 443, plus 443/UDP). Database, Studio, the native API gateway,
pooler and internal services remain private. The public Supabase origin exposes
the native service paths; it does not expose Studio. All public Auth paths pass
through the reviewed phone/anonymous-upgrade proxy before the private gateway.
The proxy forwards ordinary native Auth behavior and blocks routes that would
bypass Collect's journaled phone/guest contracts.

| Component | Authority and credential scope |
| --- | --- |
| PostgreSQL | Full application, Auth, Storage metadata, gateway and operational state. |
| `collect_edge` | `NOINHERIT`, non-superuser login; explicitly selects `collect_runtime`; cannot become the database owner. |
| `collect_sms_edge` | Separate non-superuser login; selects only `collect_sms_runtime`; no general application/private-table access. |
| Native Auth | Verifies real email/phone proof and retains sessions; auto-confirmation is disabled. |
| Collect API/Admin/functions | Require the exact profile, source and current database fence; receive only their function-specific environment. |
| Job operators | Owner connection exists only inside an explicitly invoked private operator container; job functions receive their separate job tokens. |
| Client bundles | Public profile, origins, publishable key, feature flags and CAPTCHA site key only. |

The Node frontend host reuses the maintained Admin Worker and transport. The
existing Cloudflare frontend implementation also supports the explicit profile.
This supplies a self-hosted frontend option without moving business writes out
of Supabase or asserting that the existing Cloudflare deployment was changed.
SMTP, approved SMS/WhatsApp delivery, Android FCM and an approved AI provider are
delivery/processing integrations, not a second backend database.

## Reproducible identities

`profile.example.json` contains exactly nine string fields. Select the actual
public HTTPS origins before building. `environment` is either `qualification`
or `production`; `mode` is `self_hosted`. The profile hash is SHA-256 of the
canonical sorted JSON. `COLLECT_DEPLOYMENT_PROFILE` contains that JSON string,
not a filename. The Google callback origin must be an admitted application
origin; use the Admin origin when both member and Admin Google flows are enabled.

Five identities have different purposes:

1. **Profile SHA** binds the exact deployment and public origins.
2. **Backend source SHA** binds the complete prepared backend/operator source
   inventory, locks and vendor bytes.
3. **Frontend source SHA** binds Flutter, static website, assets, public content
   and the required current capture/review inputs.
4. **Client-config SHA** binds the actual public settings used by the builds.
5. **Artifact manifest** binds every installed Admin/public output byte.

A matching hash proves identity, not delivery, review approval or operational
acceptance. The database stores the immutable profile binding. The old logical
project reference retained in financial/control history remains lineage; it is
not used to discover a public host.

## Prepare a new release

Use the pinned toolchains recorded by the repository. The host path requires a
local Linux Docker 28+ engine, Compose, Python, Node, OpenSSL and `age` for cold
backup/recovery. Remote Docker endpoints are refused. Source preparation needs
no running Docker daemon and sends no provider request.

Create a real profile in a private working location. Run from the repository
root, using a fresh physical release directory:

```sh
python -m scripts.self_hosted.prepare \
  --profile "$COLLECT_PROFILE_FILE" \
  --output "$COLLECT_NEW_RELEASE_DIR" \
  --tls acme --acme-email "$COLLECT_ACME_CONTACT"
```

For an isolated qualification profile, `--tls internal` is available. A
production profile refuses that mode. Domain ownership, DNS, firewall and
certificate issuance still require verification on the selected real host.

Preparation creates fresh signing, encryption, database, job and gateway keys
once; it does not overwrite an existing directory. Private files are 0600 under
a 0700 release root. The database receives its leaf certificate and public CA;
the CA signing key is kept separately. The runtime verifies the private CA and
the database hostname `db`. Do not mount the CA signing key into services.

**This is a fresh installer, not a data migration or key-rotation command.** An
existing Collect installation has encrypted data, Auth/session mappings and
unresolved obligations. Preserve its original encryption/signing-key custody
and use the separately accepted migration/cutover procedure. Generating new
keys is not a way to import or decrypt old ciphertext. Never re-run the fresh
installer over an existing production database.

## Configure capabilities privately

Edit only `private/provider-settings.json` in the prepared release and then run:

```sh
python -m scripts.self_hosted.configure --release "$COLLECT_RELEASE_DIR"
python -m scripts.self_hosted.release_operator \
  --release "$COLLECT_RELEASE_DIR" verify-source
```

The exact settings contract is `PROVIDER_SETTINGS` in `prepare.py`. Configuration
validates the settings, projects each value into its correct service scope,
regenerates public `client.json`/`public.env` and seals the resulting files. It
does not send a message, activate a scheduler or rotate a retained key. An
interrupted or independently edited configuration fails verification until
configuration is completed deliberately.

Production publication requires real SMTP and Turnstile configuration. Both
the public site key and private Turnstile secret are required together. All
five documented public test site keys and all three test secret keys are
rejected for production. Explicit qualification builds may use those fixtures;
that cannot qualify a real production account or CAPTCHA challenge.

| Capability | Required configuration and remaining qualification |
| --- | --- |
| Email Auth | TLS SMTP endpoint (465/587), credentials and sender; actual verification/recovery deliverability. |
| Anonymous browsing | Explicit flag and CAPTCHA; same-UUID journaled upgrade and live GoTrue proof. Guest identities have no business principal or Admin authority. |
| SMS using OpenSMS | `opensms_hook`, dedicated OTP application, approved local gateway and signed native GoTrue hook. Actual approved device/SIM delivery remains separate. |
| WhatsApp | Separately qualified native `twilio` or `twilio_verify` mode. The pinned custom SMS hook cannot distinguish requested WhatsApp; OpenSMS hook mode refuses WhatsApp. |
| Receipt SMS | Independent receipt-only gateway application/token, policy/source approval, one-use send grant and current recipient consent. |
| Contribution email | Verified recipient opt-in, provider configuration, approved start/source, bounded budget and inactive email scheduler qualification. |
| Android push | Approved FCM account/project, current device/token, start/source and consent. |
| Gateway wake push | Separate `OPENSMS_FCM_PROJECT_ID`, `OPENSMS_FCM_CLIENT_EMAIL` and `OPENSMS_FCM_PRIVATE_KEY`; the gateway never inherits the member-push service identity. |
| Google | Matching native Auth/runtime flags, credentials, exact callback and current approved redirect configuration. |
| Receipt AI | Explicit model/key/processing approval; financial actions remain independently authorized. |
| Roster PDF/image AI | Held until a compatible Supabase-native decoder and its complete corpus/isolation evidence exist. The old Python/SQLite decoder is not admitted as a Supabase backend. Deterministic text/CSV remains independent. |
| Retention v2 | Exact policy-approval SHA, current grant/email proof, sealed inventory and bounded row execution; external-copy and physical-object erasure are separate unresolved domains. |

All sends, push, new guest registration, AI and new privacy execution remain
disabled/paused by default. A configured approval hash does not create the
independent review or provider proof it names.

The member push package is `app.cool.mobile`; the `.dev` package is admitted
only for qualification. Production gateway configuration requires current
device readiness and actual SMS-part evidence. Callback destinations are an
explicit, bounded list of HTTPS host names. Configuration validates identity
and shape; real IAM permissions, SIM/device execution and FCM delivery still
need acceptance on the selected installation.

Gateway HTTP requests and private maintenance use the same current-source,
epoch, admission and drain protocol as application work. The gateway has narrow
SQL wrappers and an immutable admission-ownership map; it cannot assume the
application runtime role. Database batches, callbacks, FCM requests and pending
work stay attached to the original admission. Unknown delivery outcomes remain
unknown and can block a drain; restarting a worker does not authorize a resend.

## Install a fresh database in stages

These commands are intentionally separate. Mutations plan by default and need
`--apply`. Keep the original operation UUID through an uncertain response; read
back before considering another attempt.

```sh
python -m scripts.self_hosted.release_operator \
  --release "$COLLECT_RELEASE_DIR" start-private --apply

python -m scripts.self_hosted.database \
  --release "$COLLECT_RELEASE_DIR" foundation --apply

python -m scripts.self_hosted.database \
  --release "$COLLECT_RELEASE_DIR" capture \
  --output "$COLLECT_FRESH_PLATFORM_OBSERVATION"
```

The first nine original migrations install the inactive foundation. The
application runtime role is provisioned before the platform metadata capture.
SQL10 intentionally binds a reviewed native Auth/Realtime catalog. The capture
is labeled `observed_not_admitted`; it does not turn itself into a review.

A platform review must compare the actual pinned installation, role ownership,
Auth/Realtime interfaces and catalog expression. Its binding record must have
the exact `collect.selfhost.realtime-binding.v1` shape validated by
`database.validate_binding`, status `reviewed`, and the profile, backend source,
image lock, metadata, expression, original/rendered SQL10 and independent review
evidence digests. Only the two existing catalog-hash literals in SQL10 may
change in the executed rendering. Original migration source bytes stay intact.

```sh
python -m scripts.self_hosted.database \
  --release "$COLLECT_RELEASE_DIR" complete \
  --binding "$COLLECT_REVIEWED_PLATFORM_BINDING" --apply

python -m scripts.self_hosted.database \
  --release "$COLLECT_RELEASE_DIR" initialize \
  --operation-id "$COLLECT_RETAINED_INITIALIZATION_UUID" --apply
```

The full inventory is 25 migrations: the original16 plus nine additive
migrations. Every migration and its installation receipt commit together.
Updates, deletes and truncation of the installation journal are refused.
Completed steps are verified on retry; they are not reset or replayed. The
initialization UUID binds both profile and initial controller source and has an
exact readback path. This path is for a new installation; retained source
upgrades follow the existing fenced source-upgrade protocol.

## Build and install both frontend surfaces

Build the actual maintained Admin target through
`scripts/admin_pwa_release_build.sh`; explicit qualification uses its
`--qualification` mode. The public website uses
`scripts/public_landing_prepare_build.sh`, the Ruby static builder and the
unchanged screenshot freshness gate. `lib/main_public.dart` is not a substitute
public website release pipeline. Supply public values from the exact configured
`client.json` through a JSON-aware process launcher; do not shell-source private
environment files.

Preserve outputs from both builds in separate physical directories. The build
receipt must satisfy `collect.selfhost.frontend-build.v1` in `assets.py`: exact
profile/source/frontend/client identities, toolchain, command arrays and the
complete byte/hash inventory of each surface. It must reflect commands actually
executed. Incomplete source provenance is refused.

```sh
python -m scripts.self_hosted.assets \
  --release "$COLLECT_RELEASE_DIR" \
  --admin "$COLLECT_ADMIN_BUILD_DIR" --public "$COLLECT_PUBLIC_BUILD_DIR" \
  --build-evidence "$COLLECT_FRONTEND_BUILD_RECEIPT"
```

Installation scans the actual bundles for the prepared private/provider
credentials, refuses symlinks/unexpected hidden files and verifies every copied
byte. A changed public setting requires new matching builds. Existing different
assets cannot be silently replaced. Matching installed artifacts support exact
readback.

## Schedulers and provider activation

Prepare the locked Node operator dependencies, then native Cron/pg_net/Vault
custody. Tokens are dedicated to each lane. An existing Vault name must match
the actual decrypted token hash internally; metadata alone is insufficient and
the plaintext token is never returned.

```sh
python -m scripts.self_hosted.scheduler --release "$COLLECT_RELEASE_DIR" \
  prepare-dependencies --apply
python -m scripts.self_hosted.scheduler --release "$COLLECT_RELEASE_DIR" \
  prepare-native-custody --apply
python -m scripts.self_hosted.scheduler --release "$COLLECT_RELEASE_DIR" \
  --lane main install-inactive --apply
python -m scripts.self_hosted.scheduler --release "$COLLECT_RELEASE_DIR" \
  --lane email install-inactive --apply
```

Install the main lane before email. Both install inactive. Follow the existing
main operator contract and [`supabase/jobs/EMAIL.md`](../../supabase/jobs/EMAIL.md)
for exact reviewed readiness, retained probe UUID, readback, bounded activation,
pause and unknown-outcome review. Do not use a new UUID to erase a lost reply.
The shared fence must account for both lanes and all retained obligations.
SMTP acceptance is not recipient delivery, and a timed-out external call is
not a safe resend instruction.

## Publish, observe and recover

After the admitted preproduction checks and release/cutover prerequisites:

```sh
python -m scripts.self_hosted.release_operator \
  --release "$COLLECT_RELEASE_DIR" publish --apply
python -m scripts.self_hosted.health --release "$COLLECT_RELEASE_DIR"
```

Publication requires the exact current OPEN controller source/profile, least
privilege role graph, actual TLS authentication with both runtime credentials,
verified client artifacts and production configuration. It starts functions,
frontend and proxy. It does not authorize a data migration, declare providers
qualified or satisfy the original production release criteria by itself.

Health reports service states, source mismatch, unknown obligations, finite
capacity, disk space and database certificate lifetime without row contents or
secrets. Nonzero exit can feed the selected monitoring service. Actual alert
delivery, on-call ownership and approved workload/SLO/RPO/RTO still need real
host evidence. Finite controller/operation histories have explicit limits;
settled-admission archiving does not make every history unbounded.

To include the stopped-lifecycle proof count and remaining capacity at each
current threshold, add `--capacity-detail` to the same health command. The
optional detail uses the owner-status read and is withheld when the source or
budget is unconfirmed. Counts can change during or after the read; they do not
predict a date of exhaustion or authorize an admission, release or upgrade.
The operation-receipt threshold of 9,998 is the admission cutoff; the stored
hard limit is 10,000 and some control actions reserve additional entries. This
observation neither archives nor deletes history.

Cold backup requires the actual committed v3 FENCED controller, completed local
lease drain and nonblocking inactive schedulers. Use the original operation and
epoch with the maintained owner APIs: begin quiesce, commit, then v3 drain in a
separate transaction. A stopped process is not proof that its external effect
settled. The backup command refuses to invent such a proof.

```sh
python -m scripts.self_hosted.recovery backup \
  --release "$COLLECT_RELEASE_DIR" --output "$COLLECT_FRESH_BACKUP_FILE" \
  --recipient "$COLLECT_INDEPENDENT_AGE_RECIPIENT" --apply

python -m scripts.self_hosted.recovery restore \
  --archive "$COLLECT_BACKUP_FILE" --receipt "$COLLECT_BACKUP_RECEIPT" \
  --identity "$COLLECT_INDEPENDENT_AGE_IDENTITY_FILE" \
  --destination "$COLLECT_FRESH_RESTORE_DIR" --apply
```

Backup stops every service and leaves it stopped, scans the complete release for
unsupported links/special files, then streams the whole database/Auth/Storage/
gateway/Vault/key/config/source/assets tree directly into authenticated `age`
encryption. No plaintext archive is persisted. Restore requires a separate
target without an existing deployment project, verifies ciphertext identity,
bounds every archive entry and restores into a new directory. It starts
nothing. Reconcile all financial records, objects, Auth/session/revocation
state, original operations and unknown effects before release. A receipt with
`restored_not_started` is not recovery acceptance.

The current local evidence includes actual migration/journal, restricted TLS,
runtime and domain qualification. A full Docker cold-backup/restore drill on a
populated real installation remains required. Test that drill, independent key
custody and the accepted post-write recovery strategy before production cutover.

## Evidence and release discipline

Runbooks and test receipts retain the distinction between synthetic platform
interfaces, real PostgreSQL/driver behavior, compiled client builds and live
acceptance. Failed attempts stay available with their original scope. Existing
provider, legal, design and production-approval fields are not filled in from a
source hash. The selected design authority remains
`revolut-design@jean-bosco-skills`; reference hygiene is not visual signoff.

Use the implementation report and original36-item status matrix to finish real
host/provider/device/restore/CI/cutover acceptance. Do not retire the old writer
or its encrypted recovery custody before the admitted cutover, observation and
compatibility criteria are met.
