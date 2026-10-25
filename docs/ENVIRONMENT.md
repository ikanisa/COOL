# Collect environment and production transition

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

## Public client configuration

The selected toolchain is Flutter `3.44.4` with its bundled Dart `3.12.2`;
`.fvmrc` pins Flutter. Generated machine settings must use the qualified SDK.
The guarded native production configuration nominates:

| Setting | Intended value or source |
| --- | --- |
| `COLLECT_BACKEND` | `supabase` |
| `SUPABASE_URL` | `https://rrlduytparvsjfmegalh.supabase.co` |
| `SUPABASE_API_URL`, `SUPABASE_ADMIN_API_URL` | `https://platform-admin.collect.ikanisa.com` |
| `APP_PUBLIC_URL` | `https://collect.ikanisa.com` |
| `ADMIN_APP_URL` | `https://platform-admin.collect.ikanisa.com` |
| `SUPABASE_PUBLISHABLE_KEY` | Separately verified public client configuration |
| `AUTH_CAPTCHA_ENABLED`, `AUTH_CAPTCHA_PROVIDER` | `true`, `turnstile` |
| `AUTH_CAPTCHA_SITE_KEY` | Separately verified public site configuration |
| `GOOGLE_AUTH_ENABLED` | Disabled unless separately configured and accepted |

`COLLECT_API_URL`, when supplied as a compatibility alias, must match the
reviewed Supabase API origin. Nominating these production origins does not prove
their current proxy routing, Auth destinations or production cutover. Keep the
distinct QA profile and its origin explicit.

Client files contain public configuration only. Database credentials, service
credentials, signing material and encryption keys remain outside source exports,
Flutter defines and web assets. Public Firebase configuration and the actual
Play Integrity project binding must be verified for the nominated Android
package; a Firebase project number alone does not prove the Play binding.

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
AAB does not establish permission approval or real MTN/Airtel behavior. The
public permission contract has no `READ_SMS`, `SEND_SMS` or Call Log permission.
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
