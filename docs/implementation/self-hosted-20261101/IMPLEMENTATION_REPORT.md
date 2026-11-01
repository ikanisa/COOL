# Collect self-hosted implementation and qualification

Date: 1 November 2026. Branch: `codex/self-hosted-readiness-20261101`.
Starting revision: `7908e7c71f3bab122f6c57be7066c2be772ab8a4`.

## Outcome and release decision

This change implements a substantial part of the engineering backlog for using
locally hosted Supabase as Collect's backend, database, Auth, Storage, Realtime,
Edge Functions and operational custody. It adds the deployment/operator package,
updates the mobile and Admin consumers, ports the inspected OpenSMS gateway to
PostgreSQL, and strengthens identity, notification, privacy and maintenance
controls. The original sixteen migrations and prior financial/source evidence
remain preserved. Nine additive migrations bring the reviewed inventory to 25.

**The complete production goal remains unfinished.** This branch is an
implementation and local qualification candidate. It is not a production
deployment, signed Android release, installed-PWA acceptance, complete recovery
proof or permission to activate delivery. The original 36 production criteria
retain their numbering, identifiers and acceptance conditions in
[`task-status.md`](task-status.md) and [`task-status.csv`](task-status.csv).
The underlying criteria remain in
[`REMAINING_PRODUCTION_EXECUTION_2026-10-26.md`](../../plans/supabase-return-2026-10-20/REMAINING_PRODUCTION_EXECUTION_2026-10-26.md).

The design authority remains `revolut-design@jean-bosco-skills`. Its entrypoint
and maintained local fallback were unavailable in this environment. Existing
components were retained for functional work; the authority-hygiene check is
not visual-fidelity certification. No other design system was substituted.

## What the change implements

### Configuration basis from the requested Google Drive folder

The implementation uses the reviewed [Supabase source folder](https://drive.google.com/drive/folders/1PJHsgJ0ozM0LSCLGDXZBXyVPp72-FS7p),
its [expanded starter](https://drive.google.com/drive/folders/14SA4PsnzuIuzfC1LfXiIHOK3U47JKu3x),
and the supplied [local configuration](https://drive.google.com/file/d/1Kb5ABTecmcE72A0Geqbo-xWIXKTHTG_S/view).
The originally downloaded starter archive has SHA-256
`2ddc1d035fe8980999ffeb23364083f14f77e83c3df1548d58a3550945a4316f`;
its `config.toml` has SHA-256
`89e6fc9fc3fdcf7e3f73c23c6fdefd13edfc30302f942f54994eda9c925375be`.
The starter's private CLI development configuration informed the service and
Auth requirements. The production package below supplies the separate pinned
Docker deployment, public TLS boundary and Collect-specific controls needed
for the self-hosted target.

The implementation also fetched the newer v1.3 signed SMS hook from Drive.
Its exact three source-file identities and narrowly documented adaptations are
retained in [`source-provenance.json`](../../../supabase/functions/send-sms-hook/source-provenance.json).
The earlier starter archive and that later hook are separate source snapshots;
neither is presented as evidence that a production server or provider was
activated.

### A reproducible local Supabase installation

The deployment is based on the reviewed Supabase self-hosted v0.8.3 source at
`bc27d2661edd09a5d0b8d76ce33da6d4071a756e`. The vendor inventory stays byte-identical
and every service image is digest-pinned. Thirteen services are composed behind
one public TLS proxy; database, Studio, gateway and internal services publish no
host ports. A Node host can serve the existing Admin and static public website;
the existing Cloudflare frontend transport also supports the explicit profile.
Neither frontend becomes an alternative business database.

An exact nine-field deployment profile binds the public HTTPS origins. Separate
hashes identify the profile, backend source, frontend inputs, client settings
and output artifacts. Fresh keys are generated into private files, with an
independent database CA and hostname verification. The gateway login can select
only `collect_sms_runtime`; the application login can select only
`collect_runtime`. Neither is a database owner or an RLS-bypassing login.

The operator separates preparation, configuration, private-service startup,
foundation installation, observed platform metadata, reviewed SQL10 binding,
completion, initialization and public startup. Each migration and its immutable
installation receipt commit in the same transaction. Exact retries read back
the original step; a conflicting UUID or digest fails. The original SQL10
source is preserved; only its two reviewed platform-catalog hash literals may
change in an independently bound execution rendering.

This is a **fresh installer**. Existing encrypted data, retained signing keys,
Auth/session mappings and unresolved obligations require the original governed
cutover/recovery process. Creating fresh keys does not migrate old ciphertext.

The complete operational instructions and configuration contract are in
[`deploy/self-hosted/README.md`](../../../deploy/self-hosted/README.md).

### Mobile, native build configuration and Admin consumers

The mobile and Admin configurations consume the same canonical profile rather
than guessing a managed Supabase host. Internal service addresses never enter
client builds. Invalid hashes, environments, origins and unprofiled internal
routing are refused. Production builds reject all documented Turnstile test
site keys; the deployment also rejects the test secret keys. Qualification
fixtures remain explicitly labeled.

Anonymous browsing is separated from a business principal. Guest upgrade keeps
the same native Auth UUID and journals the original challenge/outcome. A lost
or uncertain response does not create another upgrade. A fresh session must
match the original identity and refresh proof before projection can proceed;
turning off the feature does not remove that denial barrier. The public Auth
proxy applies the journaled phone/guest boundary across the native Auth route
surface. Real native GoTrue compatibility and delivery still need deployment
qualification.

Member preference contract v2 supports five independent choices with revision
checks. Email opt-in defaults to false; older clients preserve the newer
choices. The Admin now exposes the existing policy-controlled receipt-SMS
batch materialization and one-use assisted send path. It retains original
operation IDs through uncertain responses and uses readback for reconciliation.
Provider tokens remain server-side. The detailed Admin route/permission map is
[`admin-route-permissions.md`](admin-route-permissions.md).

### Gateway, notification and scheduler custody

The inspected OpenSMS v0.3 protocol is ported into a private PostgreSQL schema
and Supabase Edge function. It retains the original Android/API contract,
message/part evidence, application/device credentials and uncertain outcomes;
there is no D1 dependency. OTP and receipt delivery have different application
credentials. Gateway wake FCM has its own service identity and cannot inherit
the member-notification account. Member push uses `app.cool.mobile`, with `.dev`
admitted only for qualification.

A native test reproduced a gateway write during application quiescence. The
new migration25 and gateway adapter bring gateway requests, maintenance,
database batches, callbacks, FCM and pending work into the same source/epoch
admission and drain protocol. The immutable gateway ownership map and narrow
SQL wrappers preserve privilege separation. Original uncertain external
effects remain retained. Pending local work blocks lease drain; completed local
work can release its lease while callback/FCM outcome uncertainty remains in
custody. Local drain is not physical settlement or cutover approval. Worker
restart does not authorize a phone resend. The reproduced failing attempt is preserved beside
the correction evidence.

Contribution email has a durable event outbox, current verified recipient
eligibility and explicit consent. An outer dispatch journal prevents a repeated
HTTP job invocation from draining a different obligation, including when its
original result was an empty probe. SMTP acceptance is not described as
recipient delivery or financial settlement.

Main and email schedulers are installed inactive. Owner operations bind exact
source, configuration, actual Vault token version, original probe/lifecycle
identity, current review and budget. A second native proof found that a
main-job body could change after its admission prefix without invalidating
combined coverage. Exact body, metadata, owner and ACL attestation now covers
the main/email routines and optional cleanup helper. The earlier failing
receipt remains in [`combined-scheduler`](combined-scheduler).

The pinned native Auth custom SMS hook has no reliable WhatsApp channel
discriminator. `opensms_hook` therefore refuses WhatsApp. The separately
configured native Twilio/Twilio Verify modes require their own real-channel
qualification. This preserves truthful supported behavior.

### Backend capacity, history and governed retention

Settled admission history is logically archived with an immutable hash receipt
of each unchanged original row. A derived working index supplies the bounded
capacity calculation, so safe lifetime history no longer exhausts the ordinary
100,000-entry working budget. Unknown/unresolved work is never erased to regain
capacity. Separate control-history and proof-history limits remain monitored
and require a reviewed long-term protocol before exhaustion.

Member history uses SQL keyset pagination, at most `limit + 1` rows with a
maximum page size of50, instead of loading/hashing the entire event history in
Edge. Date range, search, group, session and revision bind the cursor. Exact
full-scope totals remain decimal strings at the SQL boundary, with safe-integer
validation. Relevant changes invalidate old cursors. Balances use one
multi-group aggregate query. Exact totals still need realistic workload and
query-plan qualification on the selected host.

Retention v2 adds an immutable complete metadata manifest with bounded pages,
source/schema/policy identity and currentness checks. It refuses overflow
rather than returning a truncated inventory as complete. The separate row
executor handles only four explicitly approved own-row classes, in chunks of40,
after quarantine and projected-access revocation. Holds, current reviewer
email proof, policy, source, claim, preimage and postimage remain checked.

**This does not complete universal personal-data erasure.** Native Auth
users/sessions, physical Storage objects, gateway/provider/shared custody,
backups and unverified external copies remain retained or blocked. Existing
financial and immutable review records are preserved. Those domains require
their own approved adapters and real outcome/restore evidence. See
[`retention-status.md`](retention-status.md) for the precise scope.

### Recovery, monitoring, website and CI

Cold recovery tooling requires an accepted fenced/drained state, stops the
owned service set and keeps it stopped, and encrypts the whole release stream
with `age`. It includes database, Auth, Storage, gateway, configuration, source,
artifacts and keys. Restore requires a fresh destination, verifies the original
receipt/ciphertext and rejects path traversal, links, special files and
privileged modes. It does not auto-start restored services. Actual encryption,
corruption refusal and extraction boundaries have local tests; a complete
populated Docker-host restore has not been executed.

Health evaluation checks real controller fields, expected services, source
identity, unresolved effects, working/control capacity, disk and certificate
runway. Actual alerts, support ownership, workload, SLO, RPO and RTO still need
the accountable deployment inputs and measured acceptance.

Seven public screenshots were replaced by actual current Flutter browser
captures. Their source, served bytes, capture and review commitments pass the
unchanged publisher/freshness controls. Prior media and provenance remain
preserved. These are current interface previews; they do not establish native
design acceptance or permission to reuse the images as store screenshots.

CI now calls a same-revision reusable Supabase qualification workflow. Current
source contracts, the complete current native migration suite and actual SQL
history packets consumed by Dart are mandatory. Historical profiles require
explicit manual selection and an exact reviewed40-character source SHA. The
policy and negative tests prevent replacing native evidence with a source-only
pass, masking commands or uploading private runtime descriptors. This local
wiring proof does not establish actual GitHub execution eligibility or required
independent approvals.

## Evidence and its limits

Each receipt identifies its actual source/transitive inputs, toolchain and
scope. Earlier18/24-migration receipts remain historical and are not relabeled
as25-migration results. Focused selections overlap and must not be summed into
a project-wide passing total. Failed attempts and their corrections remain
separate from final passing runs.

The final complete-current native run4 passed **152 named scenarios across11
required groups** on the25-migration schema. Those groups cover installation7,
control8, runtime16, backend/history10, Auth10, retention15, notifications9,
gateway34, data staging5, schedulers24 and gateway fence14. Its newly generated
history packet separately passed all six actual Dart consumer cases. The broad
native source SHA is
`fcf1ead40a86061a9454f25f1fa80900d7c3bd025b5483b7765bae92a98cff9a`;
the narrower history-producer SHA is
`946c980d46a5c51797c3d6534fc7bfb0419e93483fe959c9f663599fb4d65da8`.
Neither is the full deployment-package digest. The database was stopped with
all fixture data retained. Auth/provider/Cron/Vault/pg_net doubles remain
explicit; the local counts do not imply actual delivery or service acceptance.

The maintained current source gate passes, including all647 shared Node cases
and all six frozen Edge entrypoints. Final Dart analysis found no issues in
1,002 hashed Dart inputs. The complete serial Flutter run nevertheless remains
**7,133 passed,17 failed,6 skipped**. A later64-pass focused run corrected four
nonvisual fixture failures; it does not convert that original full run into a
pass. Thirteen actual golden pixel differences remain. Their52 comparison
images are preserved without baseline or tolerance changes.

The final installer separately passed six scenarios on25 migrations, the exact
native Edge runtime passed11 checks, and native PostgreSQL TLS passed eight.
The operations suite passed14 Python and33 Node cases. The current CI/Make
policy passed46 negative tests after its staging/source boundary was corrected.
The Ruby3.3/Bundler2.7.2/Fastlane frozen graph is unavailable locally, so the
fresh Ruby gate is blocked. Android's first two actual Gradle attempts stopped
on a deadline and missing offline dependencies. After verified toolchain
bootstrap and archive cleanup, attempt3 compiled the actual application/test
Kotlin and passed all14 SMS policy cases in267.999 seconds, with no failures,
errors or skips. That is package5 unit qualification, not a signed release,
device test or APK acceptance. Earlier failures remain preserved.

Final static Compose validation subsequently found two missing upstream
environment values, `REGION` and `IMGPROXY_AUTO_WEBP`. Preparation now supplies
the reviewed `stub`/`true` defaults and refuses any missing interpolation
variable. The operations14 tests passed again; the regenerated13-service
configuration has no warnings. One Admin email test fixture was formatted by
the pinned Dart formatter, and the maintained format gate then passed all1,051
files with zero changes. These later packaging/format corrections do not
retroactively change the152-case native receipt's source identity. Application
SQL and runtime handlers were unchanged; successor frontend artifacts use a
fresh complete source/client inventory.

Current typed data staging is qualified, including lost-COMMIT reconciliation,
duplicate prevention, exact ACL denial and tamper refusal. **Positive first
import is not implemented for the current self-hosted target.** The retained
historical promoter requires its original97-table target and managed-project
identity. The current test proves refusal without changing any of137 app/private
relations; that refusal is not a successful migration. Historical native
producer tests remain unchanged and are confined to explicit historical source
selection. The five unchanged pure assertions are also exercised in the
current source gate, with substantive current database staging required in the
separate native group.

Use the following entrypoints to inspect the exact evidence:

| Area | Evidence |
| --- | --- |
| Full original task accounting | [task-status.md](task-status.md), [task-status.csv](task-status.csv) |
| Mobile/Auth/build and complete-suite result | [mobile-status.md](mobile-status.md) |
| Admin, notifications and gateway | [admin-status.md](admin-status.md), [gateway-fence](gateway-fence) |
| Real SQL history/capacity | [backend-status.md](backend-status.md), [history](history) |
| Retention scope and native scenarios | [retention-status.md](retention-status.md) |
| Maintained installer and transaction journal | [database-installer-status.md](database-installer-status.md) |
| Restricted PostgreSQL TLS | [database-tls-status.md](database-tls-status.md) |
| Actual pinned native Edge binary | [native-edge-status.md](native-edge-status.md) |
| Scheduler correction and real identity | [combined-scheduler](combined-scheduler) |
| Independent deployment review | [deployment-independent-review.md](deployment-independent-review.md) |
| Current public media | [public-media/README.md](public-media/README.md) |
| Native roster decoder investigation | [roster-status.md](roster-status.md) |
| Final current native suite and failures | [mobile-validation/current-native-final-4](mobile-validation/current-native-final-4) |
| Final operations and CI policy | [operations-status.md](operations-status.md), [ci-policy-final-result.json](ci-policy-final-result.json) |

## Engineering and release work that remains open

1. **Roster PDF/image/XLSX decoder.** Native Supabase worker isolation and PDF
   structure/rendering probes are viable, but the current image alternatives
   do not yet preserve complete APNG validation. A truthful separate v2 bridge,
   signed outcome contract, bounded complete codec pipeline and PostgreSQL
   replay journal are still needed. The old Python/SQLite decoder is not
   silently treated as Supabase-native. This required existing capability
   remains disabled and original criterion29 remains open.
2. **Complete privacy execution and custody.** The new manifest and SQL-row
   engine do not erase native/provider/object/backup domains. Those domains
   need reviewed policy/authority, guarded adapters and actual receipts.
   **Current positive first-import promotion also remains implementation work:**
   adapt its exact target/source identity and transactional custody to the
   current self-hosted schema, qualify genuine positive imports and all refusal/
   unknown-outcome cases, and then rehearse the populated production transition.
3. **Actual local host qualification.** Select the real Linux host and origins,
   apply the pinned full stack, verify DNS/TLS/firewall and actual
   GoTrue/Storage/Realtime/Cron/Vault behavior, then admit the platform binding.
   Native PostgreSQL fixtures explicitly double those service interfaces.
4. **Android and installed PWA.** Registered signing custody, current Play
   identity, a source-bound signed candidate, physical-device/SIM/upgrade
   journeys, actual installed-PWA two-version/rollback evidence and required
   design/accessibility acceptance are outstanding.
5. **Providers and accountable policies.** Real approved email, SMS/WhatsApp,
   FCM and existing AI delivery/evaluation; financial finality policy; rights
   and store declarations; workload/SLO/budget and RPO/RTO criteria remain
   external acceptance inputs. Configuration hashes do not manufacture them.
6. **Populated system acceptance and release.** Run the existing role and
   authorization matrix, real financial/evidence workflows, complete recovery,
   independent CI/approvals and cutover rehearsal. Reconcile original unresolved
   obligations, admit the actual switch, publish and read back identified
   artifacts, observe for the approved period and retire previous writers only
   after compatibility acceptance. No production writer or legacy custody was
   removed by this implementation.

No percentage-complete or production-ready label is assigned: code,
qualification, delivery and release acceptance are different states, and the
remaining required criteria are material.
