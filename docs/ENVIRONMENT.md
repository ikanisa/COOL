# Collect environment and production transition

Collect uses one Supabase Cloud project, `rrlduytparvsjfmegalh`. Its project
origin is `https://rrlduytparvsjfmegalh.supabase.co`. Managed qualification
and production profiles share this project and use their configured
application origins.

Status at the 24 October 2026 checkpoint: production cutover remains open. The
current release work covers Collect Android, the Admin PWA and Supabase. A
configured target, local build or QA deployment does not establish production
acceptance.

## Verified hosted checkpoint

The nominated Supabase project is `rrlduytparvsjfmegalh` at
`https://rrlduytparvsjfmegalh.supabase.co`. The accepted bounded hosted checkpoint
uses source
`02271fa60bd8630182f9824b35405fdb4dcb7fa9ac682bfe2c95c55e59e3a616`,
14 migrations and function versions `collect-api` 28, `admin-api` 29 and
`collect-jobs` 26. These identities describe that checkpoint; later source,
configuration and deployments require their own reconciliation.

The matching Admin QA build is hosted on Cloudflare at
`https://admin-supabase-qa.collect.ikanisa.com`, using worker
`collect-platform-admin-supabase-qa`. The accepted evidence covers its deployed
version and bounded static-body pairing. The production-profile build remains a
candidate: this QA publication does not establish a production Admin deployment,
authenticated actor acceptance or installed PWA behavior.

The older complete client export and its later backend pairing have separate
provenance. Do not describe an unchanged client export as containing subsequent
backend, legal, notice or recovery-source changes.

## Full-product source and toolchains

Version 2 of the source exporter includes the Collect member app, React Admin,
BuriMunsi Staff and Admin Sync, their pinned receiver inputs and the Supabase
backend. The manifest binds the source files that select the toolchains. Version
1 exports can be checked against their recorded scope. [Source exporter](../scripts/qa/collect_release_candidate.py)

| Product boundary | Version used by the checkout | Source |
| --- | --- | --- |
| Collect member | Flutter 3.44.4 with Dart 3.12.2 | [Flutter pin](../.fvmrc) |
| React Admin and backend JavaScript tests | Node 24.19.0 | [CI workflow](../.github/workflows/ci.yml) |
| Supabase Edge and CLI | Deno 2.9.6 and Supabase CLI 2.121.0 | [Deno pin](../.dvmrc) · [CLI pin](../.supabase-cli-version) |
| Collect Android | Java 17, Kotlin 2.4.20, Gradle 9.6.0, Android Gradle Plugin 9.5.1 and compile SDK 37 | [Android plugins](../android/settings.gradle.kts) · [Gradle distribution](../android/gradle/wrapper/gradle-wrapper.properties) |
| BuriMunsi Staff and Admin Sync | Java 17, Kotlin 2.4.21, Android Gradle Plugin 9.0.1, Gradle 9.1.0 and Android SDK 36 | [Native plugins](../native/burimunsi/build.gradle.kts) · [App target](../native/burimunsi/app/build.gradle.kts) · [Gradle distribution](../native/burimunsi/gradle/wrapper/gradle-wrapper.properties) |

Run `python3 scripts/qa/collect_ci_policy.py` to inspect the checked-in toolchain
inventory. The command compares active runner settings with the repository
declarations and checks the Supabase npm lock. Dart ships with the pinned
Flutter SDK. The inventory reports the app and dependency lock constraints
for Dart. [Source inventory](../scripts/qa/collect_ci_policy.py)

`make supabase-writer-journal-postgres-test` exercises the four managed
writer and retention revisions in a disposable PostgreSQL instance. On the
Mac it uses the existing hash-pinned 17.11 toolchain. CI runs the same
fixture in the digest-pinned 17.10 container using an isolated Unix socket.
[CI definition](../.github/workflows/supabase.yml)

## Public client configuration

The selected toolchain is Flutter `3.44.4` with its bundled Dart `3.12.2`;
`.fvmrc` pins Flutter. Local and CI commands must use the qualified installation
of that SDK and its bundled Dart. Generated machine settings must use that SDK.
The guarded native production configuration nominates:

| Setting | Intended value or source |
| --- | --- |
| `COLLECT_BACKEND` | `supabase` |
| `SUPABASE_URL` | `https://rrlduytparvsjfmegalh.supabase.co` |
| `SUPABASE_API_URL`, `SUPABASE_ADMIN_API_URL` | Blank until their direct Supabase Cloud routes are qualified |
| `APP_PUBLIC_URL` | `https://collect.ikanisa.com` |
| `ADMIN_APP_URL` | Blank until the Supabase Cloud Admin hosting route is qualified |
| `SUPABASE_PUBLISHABLE_KEY` | Separately verified public client configuration |
| `AUTH_CAPTCHA_ENABLED`, `AUTH_CAPTCHA_PROVIDER` | `true`, `turnstile` |
| `AUTH_CAPTCHA_SITE_KEY` | Separately verified public site configuration |
| `GOOGLE_AUTH_ENABLED` | Disabled unless separately configured and accepted |

`COLLECT_API_URL`, when supplied as a compatibility alias, must match the
reviewed Supabase API origin. Nominating these production origins does not prove
their current proxy routing, Auth destinations or production cutover. Keep the
distinct QA profile and its origin explicit.

The public `.env.example` names the selected Supabase project and leaves
`COLLECT_API_URL`, the API and Admin routes, the public key and Play project
fields blank until the production configuration is qualified. Do not use the
template as an executable production configuration.

Client files contain public configuration only. Database credentials, service
credentials, signing material and encryption keys remain outside source exports,
Flutter defines and web assets. Public Firebase configuration and the actual
Play Integrity project binding must be verified for the nominated Android
package; a Firebase project number alone does not prove the Play binding.

Server-only credential names include `FCM_SERVICE_ACCOUNT_JSON`,
`PLAY_INTEGRITY_SERVICE_ACCOUNT_JSON`, `AUTH_JWT_SECRET`,
`AUTH_TOKEN_HASH_SECRET` and `DATA_ENCRYPTION_KEY` where their corresponding
services or retained legacy backend use them. Keep their values in the relevant
server secret store, never in `.env.example`, Flutter defines or web assets.
The retained iOS name `APNS_PRIVATE_KEY_BASE64` has the same server-only boundary;
iOS/APNs distribution is outside this Android release. These names do not
activate a provider or establish key custody or production approval. The public
`PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER` is separate from its private service
credential and must identify the project actually linked to this Android app.

## Authentication and controlled activation

Email proof is the current Admin authentication path. Mandatory authenticator
enrollment is retired; do not reinstate it as a sign-in or release prerequisite.
Actual email delivery, roles, invitations, recovery and complete Owner/operator
journeys retain their separate acceptance requirements.

The hosted checkpoint retains registration disabled and MoMo execution paused.
Google authentication and Realtime remain conditional and disabled at this
checkpoint; the tested polling path remains the current client path. CAPTCHA
remains enabled. Configuration or a provider response must not be relabelled as
completed member, provider or production acceptance.

Android receipt access requires the eligible authenticated member, explicit
consent and the actual permission/provider admission controls. The guarded
production wrapper sets the Android SMS switches; a source setting or unsigned
AAB does not establish permission approval or real MTN/Airtel behavior.
Android production builds set both SMS switches to `true` through the guarded
configuration. This does not grant consent or Google Play permission approval;
the public example keeps SMS access disabled until that controlled build path.
The public permission contract has no `READ_SMS`, `SEND_SMS` or Call Log permission.
`RECEIVE_SMS` and `CALL_PHONE` still require the applicable declaration, device
and release checks. Collect never receives a member's MoMo PIN or provider OTP.

## Hosting, recovery and release boundaries

Cloudflare continues to host frontend surfaces. The legacy Cloudflare business
backend, D1 and private R2 authority must not be described as retired until the
qualified one-writer Supabase cutover, observation and old-client transition are
complete. Retained legacy source and archives support recovery and compatibility;
their presence does not nominate them as the target production architecture.

Application/database, managed Auth, Storage objects, configuration and key
custody are separate recovery scopes. Accepted bounded captures or inert restores
do not establish complete operational recovery, independent custody or measured
whole-system RPO/RTO. Keep unresolved obligations and retained recovery evidence
under their existing controls.

Final-version CI and genuine approvals, Android signing, installed device and
provider journeys, Admin actor/financial/PWA acceptance, matching production
deployment, operational recovery and Google Play production availability remain
release gates. Neither the Supabase checkpoint nor the Cloudflare QA publication
completes those gates. Consult the current production goal and execution trackers
before activation or retirement; preserve historical results when qualifying a
successor.

The full-checkout gate runs the retained member-history SQL decoder on the Dart VM and in Chrome. `make test-history-retained` verifies the original synthetic inputs and exact reconstructed defines from `test/fixtures/retained-member-history/`. A source export can use the same fixture directory or select a separately verified copy with `python3 scripts/qa/retained_member_history.py --archive /path/to/retained-member-history`. [SQL decoder validation](../test/fixtures/retained-member-history/validation.json)
