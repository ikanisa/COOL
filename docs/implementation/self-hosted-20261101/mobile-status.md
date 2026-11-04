# Mobile, Auth and frontend implementation status — 2026-11-01

This records source implementation and local qualification. It does not grant
production, provider, device, signing, visual-design or store acceptance.
The active target is the locally hosted Supabase deployment. Existing managed
defaults remain compatible only when no explicit deployment profile is supplied.

## Implemented client contracts

The member client, native build configuration and Android transport accept the
same canonical `collect.deployment.v1` public profile and SHA256 as the server.
Explicit profiles bind the public Supabase origin, member API, Admin, public
website and Google callback origins. Origins require canonical HTTPS and a DNS
host; internal `api-gw` addresses and service credentials never become public
client configuration. Public issuer is `<supabase_origin>/auth/v1`. Native
release builds retain modern `sb_publishable_*` key validation and refuse the
qualification profile for a store build.

The Android and iOS store wrappers now delegate origin selection to that same
validated configuration helper. Their former managed-only precheck blocked a
valid explicit self-hosted profile before the compiler ran. The narrow wrapper
correction preserves the managed defaults, production-only profile rule,
CAPTCHA test-key refusal, signing checks and unsigned-QA marker refusal. All
32 configuration/wrapper regression cases pass, including both self-hosted
surfaces and hash/alias/qualification refusal. These tests substitute the
compiler and do not themselves prove a native application build.

`lib/core/supabase/collect_deployment_profile.dart`,
`collect_supabase_configuration.dart`, `scripts/qa/native_build_config.py` and
the Android build checks share this identity contract. Google navigation uses
the profile's exact Supabase authorize and callback origins. Admin popup/cookie
completion requires its callback on the Admin origin; the host generator uses
that origin when both surfaces enable Google.

SMS and WhatsApp are distinct `CollectOtpChannel` values. The chosen channel is
retained through send and verify, and one channel is never substituted for the
other. Public release flags `COLLECT_SMS_AUTH_ENABLED`,
`COLLECT_WHATSAPP_AUTH_ENABLED`, `COLLECT_ANONYMOUS_AUTH_ENABLED` and
`COLLECT_GOOGLE_AUTH_ENABLED` control the member UI. The new phone/guest methods
are not advertised merely because methods exist in the gateway. Host defaults
keep unqualified providers disabled.

The notification preference model retains five independent choices:
contribution confirmations, payment reminders, group updates, security notices
and `email_enabled`. Email is false by default. The member transport requests
the backend's version-2 preference envelope and sends each choice separately;
no choices are collapsed into `push_enabled`. The email setting uses the
existing settings components and explicitly describes verified-account email
delivery. Saving an opt-in does not prove a configured email provider or send.

## Restricted guest and verified upgrade

`POST /v1/auth/anonymous` creates only a Supabase anonymous Auth identity.
There is no Collect business principal, membership, device registration,
financial permission or Admin authority for that identity. The backend checks
trusted current GoTrue user state and native JWT anonymous parity; the client
also fences member cache, realtime, diagnostics and Android SMS uploads.
Guests may browse the existing public group flow.

`POST /v1/auth/upgrade/otp`, `/upgrade/verify` and `/upgrade/reconcile`
implement same-Auth-UUID upgrade. Email, SMS or WhatsApp verification must
resolve to the original guest. A collision with an existing identity is
rejected conservatively; there is no automatic account merge. Direct public
GoTrue identity changes for an anonymous user are routed back to this journaled
flow by the public Auth proxy.

The private `guest_upgrade_challenges` journal is introduced by the
CLI-generated migration `20261101012311_collect_guest_auth_upgrade.sql`.
Verification is admitted once at a time. The client durably records an
uncertain operation before sending verification. Network loss, cancellation,
restart or unknown provider completion does not enable another verification
attempt or silently install a member principal. Only a specific confirmed OTP
rejection makes that code retryable. The UI offers recovery and an explicit
leave-guest confirmation while uncertainty is retained.

Recovery first obtains a fresh GoTrue credential from the retained refresh
token, then binds the actual subject and native session to the original journal.
An expired original access token is never treated as current authority.
Still-anonymous or not-yet-confirmed recovery can rotate and retain only a new
protected recovery refresh token; it does not grant business access. A later
confirmed recovery completes the same principal link. Same-user sessions from
another login, foreign identities, forged anonymous claims and concurrent
duplicate verification are refused.

The projection barrier is independent of the new-guest feature flag. Turning
off anonymous registration cannot release an unresolved upgrade into normal
business access. Unknown or unverified guest journal rows are retention
tombstones while their Auth identity exists; expiry alone is not permission to
delete them. Backend retention work must keep that invariant.

## Real GoTrue phone delivery and public ingress

The current Google Drive v1.3 hook source was freshly fetched and hashed rather
than assuming the older materialized v1.1 starter was current. Exact source
provenance is retained in
`supabase/functions/send-sms-hook/source-provenance.json`.

The signed hook preserves the Standard Webhooks signature, timestamp and
bounded-body checks, deterministic event/job identity, OTP destination and
deadline contract. OpenSMS uses `POST /v1/messages` with a dedicated OTP
application token, `kind: otp`, and one deterministic idempotency key. A lost
acknowledgement is reconciled through the same job; it is never replayed as a
new job or reported delivered solely because transport timed out. The Supabase
wrapper validates explicit deployment identity and the database admission
fence before external transport. The hook token cannot be the receipt token.
No real SMS was sent during this work.

The exact hook environment is:

- `AUTH_PHONE_DELIVERY_MODE=opensms_hook` and `AUTH_SMS_ENABLED=true`;
- `AUTH_PROJECT_ID` equal to the explicit deployment profile id;
- `AUTH_SEND_SMS_SECRET` matching GoTrue's `GOTRUE_HOOK_SEND_SMS_SECRETS`;
- `OPENSMS_BASE_URL`, `OPENSMS_APPLICATION_ID`, `OPENSMS_APPLICATION_TOKEN`;
- optional `OPENSMS_SENDER_LABEL` and bounded `OPENSMS_DISPATCH_TTL_SECONDS`.

The pinned GoTrue v2.197.0 source shows that an enabled custom SMS hook handles
phone delivery before the native provider branch, and its signed SMS payload
does not carry a requested channel. Consequently the OpenSMS hook mode and
native WhatsApp delivery cannot be enabled together. WhatsApp requires the
separately configured native `twilio` or `twilio_verify` mode with the custom
hook disabled and qualified provider settings. Merely setting a WhatsApp flag
does not make Android SMS into WhatsApp delivery. The host generator enforces
these mutually exclusive modes, and the hook itself refuses native modes.

`deploy/self-hosted/auth-phone-proxy.mjs` exports
`createAuthPhoneProxy(env, {fetchImpl})`. The host routes all public
`/auth/v1/*` paths through it to the fixed private `http://api-gw:8000`
destination. It does not trust client forwarding headers. The router rejects
encoded path aliases before URL construction; the proxy bounds request bodies
and permits only exact profile browser origins. In OpenSMS mode it blocks
public phone mutation attempts through OTP, signup, verify, user changes,
resend, reauthentication and phone MFA. Implicit reauthentication/MFA routes
resolve the current native Auth factor first. Ordinary email, anonymous signup,
token and OAuth behavior continue through GoTrue's own authentication and
redirect rules. Tests use a synthetic fetch implementation, never a live
provider.

Google server configuration uses `GOOGLE_AUTH_ENABLED` and
`COLLECT_GOOGLE_CALLBACK_URL` (compatible alias
`SUPABASE_GOOGLE_CALLBACK_URL`). Explicit callback aliases must agree. Public
browser origins remain bound to the validated profile and the appropriate
member/Admin surface.

## Local validation obtained

| Check | Observed result | Scope |
| --- | --- | --- |
| Native PostgreSQL guest/Auth fixture | 10 groups passed; 6 synthetic verifies, 74 synthetic provider calls, 0 real provider calls | Normal restricted owner, actual SQL, same-UUID upgrade, collisions, uncertainty, expired-access recovery, concurrency, projection/retention barriers and role denial |
| Member Auth unit/widget targeted set | 28 passed | Explicit SMS/WhatsApp behavior, guest public browsing, unknown recovery UI, OTP disabled state and alternatives |
| Earlier client/Auth/realtime/preference targeted suites | Passed as recorded in run logs | Client transport, exact profile, Google navigation, diagnostics, notification preferences; not a real device |
| Corrected security and motion contracts | 56 passed | Exact vendored-placeholder exemption, product boundaries, complete reduced-motion handling |
| Signed upstream SMS hook | 28 passed | Signatures, replay/expiry, bounded body, deterministic enqueue and unknown recovery |
| Supabase SMS admission wrapper | 4 passed | Signature before admission, explicit profile, OpenSMS-only mode, dedicated credentials, fence and late deadline |
| Public Auth phone proxy | 19 passed | Explicit ingress routes, origin/config refusal, all modes, anonymous identity restrictions and fixed destination |
| Admin hosting metadata adapter | 4 passed | Shared profile validation, legacy managed compatibility, tamper/mismatch refusal and qualification labels |
| Public origin build adapter | 3 tests, 9 assertions passed | Existing managed defaults, exact self-hosted profile and mismatched identity refusal |
| Native build configuration unit tests | 3 passed | Public-only configuration and profile restrictions |
| Store-wrapper profile regression suite | 32 passed | Exact self-hosted origins, managed defaults and rejection before a substituted compiler; no native/store qualification |
| Retained two-addition history producer | Typecheck and all 10 native scenario groups passed | Exact source parity at capture; 22 requests, 15 pages, 41 actual SQL statements; original16 plus the two explicitly named migration additions. This is preserved earlier evidence, not a complete-current-chain result. |
| Earlier history packet guard tests | 5 passed | Historical-label refusal, scope, migration/request binding, source drift and output ownership in the recorded v1 capture scope |
| Retained two-addition SQL packet through Flutter | 6 passed | Exact source/packet verification, all sorts, complete half-open date range, balances, privacy and native refusals; unchanged evidence under `history/` |
| Whole-project Dart analysis | No issues found | `dart analyze lib test` after the functional and test changes |
| Complete realtime HTTP session fixture | 14 passed serially | Explicit current-scope settling; unchanged stale-response assertions and observation windows |
| Final complete current25 native workflow | All 11 required groups passed, 152 named cases | Fresh owned PostgreSQL 17, all reviewed migrations, actual SQL/admission/locks/staging, explicit synthetic Auth/provider boundaries and zero real provider calls |
| Current25 history packet through Flutter | 6 passed | Admitted v3 packet, exact current producer/SQL/Dart source, sorting/date/aggregate/privacy and refusal checks |

Toolchains are Flutter 3.44.4, Dart 3.12.2, Deno 2.9.6 and native PostgreSQL 17.
No dependency versions were silently replaced to make a check pass.

The initial unfiltered all-test run reached 1,188 passes with six reported
failures and then stalled. Its missing explicit current14 receipt defines were
an invocation error; two security assertions and one reduced-motion omission
were corrected and their 56-test set passed. The realtime fixture had a
wall-clock settling race and is being checked independently. That interrupted
mixed run is not reported as a full-suite pass. The maintained `make test`
now explicitly runs unit/widgets without the integration tag, matching CI's
unit scope and preserving the former local entrypoint's serial scheduling.
Historical current14 and current self-hosted SQL consumers have separate
required-define make targets; see
`scripts/supabase/testing/self-hosted-member-history.md`.

A subsequent parallel unit run stalled after one framework timeout in the
realtime replacement-session fixture while large SQL qualification and browser
compilation were also active. It is retained as a failed/interrupted run, not a
pass. The final canonical serial run is recorded separately. No timeout was
inflated and no stale-result assertion was removed.

The complete canonical serial run finished in **43 minutes 42 seconds with
7,133 passing cases, 17 failures and six skips**, using
`make test FLUTTER=/workspace/scratch/2d330cc6dfd0/toolchains/flutter-3.44.4/bin/flutter`.
The resolved command was `flutter test --no-pub --concurrency=1
--exclude-tags=integration`; `make` exited 2 after Flutter's failure. The
unaltered full log and its SHA256, exact failure list and skip reasons are in
`mobile-validation/flutter-unit-serial-result.json`. The tree changed during
the run as the generator and narrow fixtures were corrected, so this record is
not rebound to a later source inventory or reported as a final full-suite pass.

Four non-visual failures were resolved and rerun together, separately: the
maintained public capability generator now matches the current registry;
two notification fixtures identify **Contribution updates** by its semantic
label instead of choosing the first switch; and the Admin verification fixture
uses its injected clock for its proof timestamp. That four-file invocation
passed **64 cases in 30 seconds**, with no skips or failures. Its exact command,
source hashes and original log are recorded in
`mobile-validation/flutter-four-corrections-result.json`. This number overlaps
the full suite and must not be added to 7,133 as additional coverage. An earlier
attempt ran zero cases because the default sandbox blocked Flutter's local test
server; that log is retained separately from the successful authorized rerun.

The remaining **13 golden mismatches are open**. The run reported differences
between 1.63% and 5.14% across all eleven member surfaces, the public desktop and
legacy Admin desktop. All 52 original master/test/difference PNGs and the exact
measurements are preserved under `mobile-validation/golden-failures/`.
Neither the baselines nor comparison tolerance changed. A sample Home pair
retains the visible layout while text/icon rasterization differs, but the cause
has not been established. These failures are not declared pre-existing,
platform-only, or acceptable without evidence and the selected design review.

A 1 November read-only follow-up verified the hashes of all 52 retained PNGs
and confirmed the 13 masters match the current baseline files. Visible content,
wrapping and major layout appear similar; many differences follow text and icon
edges, with small additional image-region differences. This suggests a shared
rendering difference but does not establish its cause. The original run's source
tree changed during execution and its captured inputs cannot be rebound to
current main. The installed owner-selected Revolut skill is available on this
host; its iOS reference images and these synthetic widget images do not by
themselves establish matching native or authenticated Admin states. A new
source-bound focused comparison and appropriate direct comparators remain needed.

The six skips are existing explicit SQL-receipt dependencies in
`admin_roster_sql_receipts_test.dart`, `admin_roster_reload_test.dart`,
`admin_roster_fresh_auth_sql_receipts_test.dart`,
`actual_member_history_sql_receipts_test.dart`, `admin_roster_import_test.dart`
and `admin_read_contracts_test.dart`. No missing historical packet was fabricated
or counted as current database qualification. The separately required current
v3 native history producer/consumer covers its own stated scope.

## Maintained current and historical CI

The automatic Supabase workflow now has distinct current source-contract,
complete-current native and current history Dart-consumer jobs. The source job
retains the existing exhaustive shared Node discovery, transport, configuration,
operator, data-stage/promote and security contracts, and adds the self-hosted
profile/deployment checks. The frozen Deno task checks all six shipping Edge
function entrypoints. Its one new locked npm entry is the exact Hono 4.13.13
dependency used by the imported SMS gateway; existing lock entries are unchanged.

The current native orchestrator requires one explicitly synthetic, fresh local
PostgreSQL 17 cluster with the reviewed 60/3/0 connection limits. Each substantive
harness gets a separate original16 clone and installs the entire reviewed
additive migration inventory once. The required groups cover installation,
control concurrency, runtime diagnostics and delivery, backend history, guest
Auth, retention, notification channels, the complete gateway protocol suite,
combined scheduler behavior, and the separate gateway source/epoch fence and
drain proof. Private descriptors remain outside uploaded evidence; unknown
effects, rejected invocations and failed child runs remain failures with their
original logs. No existing schema is reset to make a run pass.

The current history packet uses format
`collect.selfhost.actual-member-history-sql.v3` and profile
`reviewed_current_chain_member_history_v3`. It binds all current migrations and
the exact producer/runtime/Dart source. A separate admission command verifies
the complete packet before rebasing its three relative path defines. Existing
current14/current16 producers and original packets retain their historical
names and formats; historical workflow execution requires an explicit reviewed
commit SHA. The earlier eighteen-migration evidence under `history/` remains
unchanged and is not relabeled as the new profile.

`make supabase-test` requires source contracts, the current native runner and
Admin consumers in that order. Missing native fixture inputs fail. Source-only
checks are separately available as `make supabase-source-test`; the retained
historical schema target is explicitly named. The full current native run and
its new Dart packet consumer were executed after the final reviewed 25-migration
inventory froze. The implementation and this local execution are not a passing
GitHub Actions run; the same workflow must still run in the actual repository CI.

The first full-current attempt is retained as **FAIL** under
`mobile-validation/current-native-final-1/`. The control fixture correctly
refused a role grant from its normal owner, and two otherwise completed native
runners could not write their receipts because their sandbox lacked read access
to the owned output parent. Their stdout was not promoted into successful
receipt evidence. The correction provisions the single restricted control
login through the owned bootstrap role, checks its exact SET-only membership,
and permits read access only to the already owned output directory. No
application permission or production role was widened.

A new cluster/data directory and fresh databases were used for run 2. All ten
required groups passed: installation 7, control concurrency 8, runtime 16,
backend/history 10, Auth 10, retention 15, notification channels 9, gateway
protocol 34, combined scheduler 24 and gateway fence 14. The broad qualification
source digest is
`301258e05ef75756602f5e4d3ca148c15d54b12b00d7b5674bdf7f5d2a5c0849`.
Exact safe results and logs are under
`mobile-validation/current-native-final-2/`; credential-bearing private
descriptors are excluded. The actual fixture inventory is 102 app tables,
35 private tables and 125 guarded relations; catalog class counts are a
different measure. Real Auth/provider/native-extension/hosted acceptance is
not inferred from this synthetic local boundary.

The newly produced v3 history packet passed its independent admission check
and all six Flutter consumer cases. Its narrower source digest is
`946c980d46a5c51797c3d6534fc7bfb0419e93483fe959c9f663599fb4d65da8`;
`mobile-validation/current-history-final-flutter-result.json` binds the exact
packet, inputs, SQL and original test log. This digest, the broad native
qualification digest and the deployment package's backend digest cover
different inventories and must not be substituted for one another.

Final `dart analyze lib test` also completed with **No issues found** after
the four narrow fixture corrections. Its log and complete Dart input hashes
are retained in `mobile-validation/dart-analysis-current-final-result.json`.
Static analysis does not close the thirteen visual failures.

Executing the exact maintained source command then exposed a CI wiring defect:
the old `data_stage.test.mjs` / `data_promote.test.mjs` files include mandatory
PostgreSQL cases and cannot run in a source job without PostgreSQL. Their five pure
assertions are now copied unchanged into `data-contracts.test.mjs`; the original
files and implementation bytes are preserved for their explicit historical
scope. A separate current native harness performs actual staging against the
complete reviewed chain. It retains exact typed values, role denial, uncertain
COMMIT readback, duplicate prevention and tamper rejection. Its current import
test proves refusal without changing any of the 137 app/private relations.
**It does not qualify positive first-import promotion.** The existing importer
still requires the original 97-table target and managed-project CLI identity;
adapting that operator tool to the current self-hosted schema and reviewed
data dispositions remains implementation work.

The first exhaustive shared Node discovery also found seven stale retention
fixture failures (640 passed, seven failed, no skips). The fixtures had applied
legacy placeholder columns and class counts to the current SMS admission map.
Only the two test fixtures changed: current exact catalog signatures and
dependencies are represented, historical SQL11/14 profiles remain explicit,
and all blocking/context assertions remain. Targeted retention checks pass
ten cases, including additional invalid-map/dependency refusals. The corrected
canonical `make supabase-source-test` now passes with all six frozen Edge
entrypoints; its exact result is
`mobile-validation/current-source-gate-final-2-result.json`. Earlier failed
logs remain alongside it. This local result is not hosted GitHub execution.

Run 3 added the mandatory current staging harness. Its first attempt correctly
failed because the normal owner cannot `SET ROLE anon`; that was a fixture
assumption, not a reason to grant more permissions. The correction asserts
that owner restriction, retains actual PostgreSQL object-privilege checks for
all five client/service roles and exercises the runtime's table denial. All
five staging cases then passed on a fresh clone. The failed run and its data
remain preserved under `mobile-validation/current-native-final-3/`.

The final combined **run 4 passed all eleven required groups and 152 named
cases**, adding staging 5 to the prior 147-case scope. Its exact broad source
digest is
`fcf1ead40a86061a9454f25f1fa80900d7c3bd025b5483b7765bae92a98cff9a`.
All original16 bytes and the full reviewed25 inventory were checked, with no
source drift or real provider calls. Safe original artifacts are in
`mobile-validation/current-native-final-4/`; every private descriptor is
excluded. The owned server was stopped after completion, while all four
cluster data directories and failed attempts remain preserved. The final
packet independently passed admission and **six Flutter consumer cases**, as
recorded in `mobile-validation/current-history-final-4-flutter-result.json`.
The earlier run2 and earlier history results retain their original source
identities and are not counted again as additional coverage.

## Android compilation qualification

The current Android source was exported without private provider or signing
inputs into an isolated 1,792-file build tree. Its complete source inventory
is retained in `mobile-validation/android-current-source-export.json`; neither
the repository nor the exported declared source changed during the first
build. JDK 17, the pinned Gradle 9.1.0 runtime and the required Android SDK/NDK
were provisioned through verified official inputs. The bootstrap receipt
records the independently checked initial 19,971 SDK payload files. The later
API 34 revision 3 and API 35 revision 2 additions are recorded separately as
metadata verified, with incomplete independent payload qualification.

The first actual `:app:testDevDebugUnitTest` invocation, filtered to the fourteen
`MemberSmsUploadPolicyTest` cases, reached real plugin Java/Kotlin compilation
but exceeded its 900-second deadline before the app test task. It executed
**zero policy test cases** and produced no APK. The exact failed attempt,
compiler log, Gradle/toolchain identity and unchanged-source checks are retained
in `mobile-validation/android-member-sms-kotlin-attempt-1.json`. This attempt
used the public package4 qualification profile only; it is not bound to a final
prepared release. No signing, store, device or provider operation ran.

Cold dependency materialization reduced free workspace storage below one GiB.
Only independently verified, reproducible download copies were reclaimed;
installed tools, dependency caches, unique failures, source and database
evidence were preserved. The cleanup receipts record the exact removed bytes.
The first timeout remains a failed attempt. A separate warmed, offline retry
completed in 98.549 seconds with exit 1 at
`:firebase_messaging:compileDebugJavaWithJavac`. Its cache lacked
`com.google.android.datatransport:transport-api:3.0.0` and
`com.google.android.gms:play-services-basement:18.8.0`; Gradle reported nineteen
further failures of the same missing-cache kind. It also executed **zero of the
fourteen policy cases**, with no application Kotlin compilation or APK pass.
The exact command, public define/source hashes, log and unchanged-source checks
are retained in `mobile-validation/android-member-sms-kotlin-attempt-2.json`.
The owned Gradle daemon registry was stopped/checked after both attempts.
Only 338,726,912 bytes were free after the offline retry. Completing the actual
locked dependency graph, native policy tests and unsigned qualification APK
therefore remains a concrete dependency/storage and build gate; the earlier
compiler-double wrapper tests do not close it.

## Frontend compilation and acceptance boundaries

The actual Admin target is `lib/main_admin_cloudflare.dart`, built through
`scripts/admin_pwa_release_build.sh --qualification`. The first compilation
produced a 4,229,266-byte `main.dart.js`; diagnostic identity and PWA manifest
checks passed. The retained managed-only hosting gate was corrected to use the
shared explicit profile validator, and the resulting artifact passes that gate
too. This first artifact used a qualification package, public key and the
documented non-production Turnstile test site key. It is not a final release
artifact or proof that CAPTCHA works with a production account.

The canonical public website pipeline is the Ruby static builder through
`scripts/public_landing_prepare_build.sh`, not a substitute Flutter public
entrypoint. Its canonical/delete-account URLs now use the explicit profile.
After reviewing five changed source diffs, only their engineering capability
input hashes were refreshed; all owner, legal, provider and publication
approval flags remain false. The real build then refused stale application
screenshots. A fresh actual seven-route capture and exact-byte limited media
review have now been completed through the existing publisher, with no browser
errors or unexpected external requests. The current packet is retained under
`public-media/`; old media/provenance is preserved separately. Design, native
and release acceptance remain false. No old visual receipt was rebound.

Final artifact provenance must bind a separate complete frontend source
inventory, the final prepared backend release, the exact public client file,
toolchain, commands and output hashes. The backend digest alone does not bind
Flutter source, assets, static website content or screenshot provenance.

That final qualification build has now completed successfully using the exact
public client from `collect-selfhost-package-5`. The maintained Ruby public
pipeline produced **53 files / 17,181,820 bytes**. The maintained Admin Flutter
pipeline produced **443 files / 199,378,576 bytes**, including the local renderer
assets and versioned copies; its 4,229,266-byte JavaScript bundle has SHA256
`439ef34aae0ce766c6bae001bdd2d5fe77ede278818bb90dee18184a6263fa71`.
Diagnostic identity, PWA manifest and Admin hosting gates passed. Exact source
and client parity passed before, between and after the builds. Original logs
and the complete output inventory are retained in
`mobile-validation/current-frontends-package5/`; compiled files remain in the
same-named task validation output for the deployment asset importer.

The receipt binds backend source
`30be121bf2515f5b0934e9b3af8f0819c4a04aa00a3545365c5623591aff8418`,
complete frontend source
`4af8d40f9037301a280c4e76ffeef856cb7f09d583008cdaa6a488eea26e4061`,
profile
`504c5ba22577bdbf90975d13fbcaba44ff2371a4388c4d2eb7c5c74fa609c148`,
and exact public client
`22c969c37c4ab3f3c3204830bb0b614ad4e8fed7d8c0d06f6033757b54d5a358`.
`BUILD-EVIDENCE.json` itself has SHA256
`00d2ba6aeb0e2635e69671cf4d1de74c7be981fb844351e52eb550cba69fba6b`.
This is a compiled qualification package using the explicitly enabled
non-production Turnstile test configuration. Hosted behavior, live CAPTCHA,
design, device and production release acceptance remain unclaimed.

The fresh frozen Ruby/fastlane gate is blocked locally: CI specifies Ruby 3.3
and Bundler 2.7.2, while this environment has Ruby 3.2.3 and Bundler 2.4.19.
The locked Fastlane 2.240.1, Rubyzip 3.4.0 and their dependency graph are absent.
`bundle3.2 check` and the ZIP test command exited before any test cases, and
Fastlane lane discovery did not execute. Eight lane declarations were found in
source; they are not a successful discovery run. Exact current source pins and
command outputs are in `ruby-frozen-current-result.json`. No lane or provider
operation ran, and an earlier PR's frozen-gate success is not relabeled as a
current result. This is separate from the dependency-free Ruby public-site
builder.

The sole design authority required by `AGENTS.md` is
`revolut-design@jean-bosco-skills`. It was not available through current
discovery or its prescribed local fallback. Existing visual components were
retained; no substitute design authority, redesign, golden acceptance or
visual fidelity signoff was invented. The prescribed repository authority
adapter was hydrated unchanged from HEAD, and `make revolut-design-authority`
now passes its hygiene checks. That check does not certify design fidelity.
Design acceptance remains explicit work, alongside real provider configuration,
hosted TLS/OAuth/cookie/device
qualification, signing, Android permission/USSD/SMS lifecycle UAT, production
backup/restore/cutover and owner release approval. Source and local tests do
not satisfy those gates by themselves.

## Focused Home regression continuation

The separate [current-main macOS Home check](home-golden-macos-20261101/RESULT.json) passed on the Android test-platform variant, and the captured candidate was byte-identical to the existing baseline. Source, fixture, SDK and dependency inventories were unchanged; the full inventory and original image remain in the named T7 evidence directory. This does not rerun the other twelve comparisons, explain the earlier Linux result, or establish a direct design, device or hosted acceptance.

## Thirteen-surface macOS regression continuation

The separate [13-surface macOS continuation](golden13-macos-20261101/README.md)
passed all 13 current comparisons plus the historical manifest test. Each
captured candidate is byte-identical to its existing current baseline; no
baseline or comparator was changed. Source, fixture, SDK and dependency checks
matched. This does not establish the cause of the earlier Linux mismatches,
the shipping cookie-Admin rendering, device behavior or design acceptance.
