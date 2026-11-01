# Admin and notification implementation status — 2026-11-01

## Completed locally

The Admin build, host wrapper, protected transport, CSP and human-challenge renderer now consume the exact hashed self-hosted deployment profile. Public browser/Supabase authority is distinct from the private service URL. Invalid hashes, environments, sibling origins and unprofiled internal routing fail closed. Legacy managed defaults remain only when no explicit profile is supplied. The Google popup retains its exact callback/origin boundary: use the Admin origin as the shared profile callback to enable both member and Admin flows.

The existing Owner receipt-SMS controls now support enabling an exact current policy and preparing a bounded batch of five jobs (API maximum ten) after explicit confirmation. Changed collection/policy clears confirmation. Unknown batches retain the original request ID; readback never reconstructs a mutation. History remains separate from the original command held in memory.

The shipping Admin gateway adapter is wired behind the public build flag `COLLECT_ASSISTED_SMS_ENABLED`, default false. The backend requires separate configured enablement/approval and a receipt-only gateway application credential. A fresh send-start acknowledgment supplies one short-lived grant; only its hash is retained. Final dispatch rechecks current policy/consent/source and the original recent-email proof. Timeout/unknown records are reconciled by GET, never automatic resend. The browser never holds the provider application token.

Contribution email now has explicit member opt-in, verified current recipient eligibility, immutable event/recipient hashes and a retained outbox. Concurrent drains claim one original obligation. Lost provider or commit results remain unknown without an automatic retry. The payload renders recorded contribution positions and clearly avoids describing them as current funds or provider settlement. SMTP acceptance is not represented as recipient delivery.

The separate inactive email Cron/Vault lane is implemented in `supabase/jobs/email-bootstrap.sql` and `scripts/supabase/email_jobs_operator.mjs`. It requires a reviewed current-source admission, private evidence, an original probe, exact credential version and a bounded monthly budget before activation. A durable outer dispatch journal prevents replayed HTTP requests from draining another event, including an originally empty probe. Both scheduler lanes participate in the closed fence inventory. Native qualification exposed a main-lane prefix-only body check; exact source-bound body/signature/security/owner/ACL manifests now cover both lanes, while unproven lifecycle obligations remain blockers. See `supabase/jobs/EMAIL.md` for the owner workflow and `combined-scheduler/README.md` for the later real-identity proof and its exact 24 scope.

The previously mismatched member preference contracts are now compatible: callers requesting `p_contract_version:2` receive and save five independent choices with exact revision/exists semantics. Contribution confirmations map to the existing payment-update gate; reminders and security choices have separate columns; email defaults false. Legacy v1 callers preserve the independent newer choices.

OpenSMS v0.3 is ported to a dedicated private Supabase PostgreSQL schema and Edge function. The original API/Android wire contract and immutable evidence are preserved. There is no new D1 service. See `deploy/collect-sms/README.md` for schema, credentials, disabled defaults, copy inventory and actual limitations. `external:collect_sms` explicitly blocks unsupported personal-erasure claims, and backup coverage includes the whole schema. New notification tables and preference columns have their own exact retention schema profile; uncertain obligations block disposition.

The later native gateway review proved and corrected a source/fence bypass. Additive migration 25 and the gateway adapter now require a gateway-owned Collect admission for every request and database batch. The original source/epoch, WORK/WRITE locks, capacity and stopped-work checks apply through narrow gateway-only functions; no broad application credential was granted. Maintenance and deferred callback/FCM work share that lifecycle. A finished local request does not establish physical phone or provider settlement. The immutable ownership map is an explicit blocked retention copy. See `gateway-fence/README.md` for the failed proof, correction and 14-case native result.

## Verification completed

The final maintained current native run 4 has passed all eleven groups on
the complete 25-migration chain, recorded in
`mobile-validation/current-native-final-4/RESULT.json`. Its 152 named scenarios
comprise installation 7, control 8, runtime 16, backend 10, Auth 10, retention 15,
notifications 9, gateway 34, data staging 5, combined scheduler 24 and gateway fence 14. The
qualification-source SHA-256 is
`fcf1ead40a86061a9454f25f1fa80900d7c3bd025b5483b7765bae92a98cff9a`.
This is a local execution of the maintained orchestrator with actual PostgreSQL
and explicit Auth/provider/native-extension doubles. No actual provider or
GitHub Actions execution is claimed. Earlier failed runs and the distinct
147-case run 2 remain preserved. The canonical `make supabase-source-test` also
passes after explicitly separating pure-source cases from required native cases.

The five native staging cases do not close first-import implementation. The
retained promoter expects the historical 97-table managed target and correctly
refuses the current 102-table application schema, preserving all 137 app/private
relations. Positive self-hosted/current-schema promotion, reviewed custody/table
dispositions and a populated import/recovery rehearsal remain open.

| Check | Local result |
| --- | --- |
| Admin protected transport Node suite | 49 passed |
| Admin self-hosted profile/host tests | 5 passed |
| Admin backend-selection/provenance tests | 17 passed |
| Admin build config Python suite | 16 passed |
| Package 5 canonical Admin/public web builds | Passed with exact source/client parity before and after: 443 Admin files (199,378,576 bytes) and 53 public files (17,181,820 bytes), 496 files total. Admin diagnostics, PWA manifest and hosting gates passed. Qualification/test CAPTCHA only; see `mobile-validation/current-frontends-package5/OBSERVATION.json`. |
| Admin management/operator API tests, including four new batch cases | 68 passed |
| Admin management/operator page suites | 61 passed |
| Native PostgreSQL notification channel qualification | 9 cases passed: opt-out, v2 CAS, concurrency, unknown preservation, permissions, actual SMS digest, outer dispatch replay/empty-probe retention and lost-claim acknowledgment |
| Original one-use SMS dispatch boundary tests | 3 passed: concurrent original grant, final-authority refusal, lost POST and GET-only reconciliation |
| Native PostgreSQL gateway API/trigger suite | 34 passed again in the complete current 25-chain orchestrator under real gateway admission; earlier protocol evidence remains preserved. |
| Gateway ingress/profile binding tests | 5 passed: both deployed prefixes, closed HTTP reconstruction, origin/token admission, disabled defaults and actual-database proof refusal |
| Email owner operator tests | 5 passed: profile/render, exact evidence, private file, owner/database binding and retained operation identity |
| Native PostgreSQL email scheduler qualification | 11 cases passed, with explicit Cron/Vault/pg_net/profile-assertion doubles, including dual-lane coverage/body/ACL refusal and retained unknown lifecycle proofs |
| Later combined scheduler native qualification | 24 passed on the exact 24 chain with the actual immutable profile assertion and normal owner; Cron/Vault/pg_net remain explicit doubles. Main/email body, metadata, ACL, source and unknown-lifecycle refusals passed. |
| Final current-chain combined scheduler qualification | All 24 scenarios passed again on the complete 25 chain through the maintained orchestrator, retaining real identity and explicit Cron/Vault/pg_net doubles. |
| Gateway application-fence native correction | 14 passed on exact 25 with a separate restricted runtime login, actual source/epoch transitions, held-work drain, direct-DML refusal and retained callback/FCM/registration uncertainty. Provider HTTP is synthetic. |
| Final current-chain gateway fence qualification | All 14 scenarios passed again in the final current orchestrator; no physical/provider settlement or production acceptance is inferred. |
| Email handler integration contract | 4 passed with explicit database/fence/provider doubles |
| Gateway and email-job Edge source Deno typechecks | Passed |
| Targeted Admin analysis | No errors or warnings; final whole-project analyzer braces information was corrected |
| Final whole-project Dart analysis | No issues found across 1,002 exactly hashed Dart inputs; see `mobile-validation/dart-analysis-current-final-result.json`. |
| Current actual SQL history through Flutter | Six v3 consumers passed on complete 25; producer source `946c980d46a5c51797c3d6534fc7bfb0419e93483fe959c9f663599fb4d65da8` is distinct from the broader native qualification source. |
| Final run 4 SQL history through Flutter | Six consumers passed using the actual run 4 packet; see `mobile-validation/current-history-final-4-flutter-result.json`. Earlier packet receipts remain unchanged. |
| Member HTTP session lifecycle fixture, isolated serial run | 14 passed after waiting for the current replacement scope's second poll and complete profile before observing old-scope effects; production code and stale-response assertions are unchanged |
| Actual Android SMS policy target, attempt 3 | Application Kotlin compilation completed and all 14 `MemberSmsUploadPolicyTest` cases passed in 267.999 seconds, with zero failures/errors/skips and source/lock parity. No APK, signing, provider or device acceptance; see `mobile-validation/android-member-sms-kotlin-attempt-3.json`. |
| Current public interface previews | Seven actual Flutter browser routes captured and directly inspected; source/served bytes verified, previous media preserved, no external service calls. Limited media review only; design/native/release acceptance remain false. See `public-media/README.md`. |

The notification and gateway migrations were applied only to explicitly owned isolated PostgreSQL 17 fixtures. SMTP/OpenSMS/FCM HTTP boundaries were synthetic. No real provider message, device send, live job activation or deployment occurred. The maintained current-chain runner has now reexecuted all 34 gateway cases under real admission; its current result is separate from the earlier protocol result. The one-use SMS boundary tests explicitly double the conditional database result; they do not replace an integrated Admin→gateway→real-phone acceptance run. Earlier 24 and later 25 receipts retain their exact source scope rather than being relabeled as one current full-system pass.

The full serial Flutter run remains **7,133 passed, 17 failed and 6 skipped**.
A separate 64-case rerun passed the four corrected nonvisual fixture files,
including the Admin email-verification fixture clock. Thirteen actual golden
differences remain across member/public/legacy Admin; no baseline was rewritten
and no design acceptance was granted. Package 5 Admin/public builds and actual
Android application Kotlin compilation with the 14 SMS policy cases now have
separate passing receipts. Package 6 frontend confirmation, Android APK/signing
and installed-device acceptance remain open. The fresh
Ruby gate remains blocked by the absent canonical runtime/locked dependencies,
as recorded in `ruby-frozen-current-result.json`.

The first Android cold build remains a 900-second timeout with zero policy cases.
The second, offline attempt remains a 98.549-second missing-dependency failure
with zero cases, including uncached `transport-api:3.0.0` and
`play-services-basement:18.8.0` under limited available storage. The third
attempt's actual pass does not relabel either earlier failure. All three receipts
and logs are preserved, and no APK or registered-key signing pass is claimed.

Package 5 frontend build evidence has SHA-256
`00d2ba6aeb0e2635e69671cf4d1de74c7be981fb844351e52eb550cba69fba6b`
and belongs to prepared backend source
`30be121bf2515f5b0934e9b3af8f0819c4a04aa00a3545365c5623591aff8418`.
Its root `main.dart.js` is 4,229,266 bytes with SHA-256
`439ef34aae0ce766c6bae001bdd2d5fe77ede278818bb90dee18184a6263fa71`.
The native 152-case receipt retains its earlier captured source scope. Later
package 6 Compose preparation corrected explicit environment defaults and
missing-variable refusal; its frontend build evidence must be recorded separately
when available. No earlier receipt is rebound to that package.

## Production evidence still required

The host operator must provision the actual TLS/DNS deployment, apply the prepared migrations under the verified source/profile, create distinct gateway application/device credentials, qualify the email and sender providers, install reviewed client assets and complete a restore rehearsal. SMS remains paused and all new channels remain disabled until their real configured approvals exist. A test pass is not a delivery or release approval.

The selected `revolut-design@jean-bosco-skills` entrypoint was absent from installed/discoverable skills, and its maintained local fallback was unavailable in this workspace. No alternative design system was substituted. Existing components were reused for functional wiring; visual fidelity and full physical-device/browser interaction acceptance are not certified.

The full Admin route/admission and mutation map is in `admin-route-permissions.md`. Deployment packaging, operator bootstrap and restore orchestration have separate source-bound evidence; full hosted stack and populated recovery acceptance remain open. Findings discovered during independent review were relayed before changes to those shared files.
