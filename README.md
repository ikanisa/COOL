# Collect

Collect is a Rwanda group-contribution system with a Flutter member app, Admin PWA and public website. Contributions use whole RWF through MTN MoMo or Airtel Money USSD; payment authorization remains with the network provider.

## Current release profile

The [26 October production execution addendum](docs/plans/supabase-return-2026-10-20/REMAINING_PRODUCTION_EXECUTION_2026-10-26.md) defines an update to the already-live Android app, Supabase as the sole production business writer, and Cloudflare hosting for the matching Admin frontend. This is the intended release profile; repository defaults, local tests and QA deployments do not establish that production cutover has completed.

| Component | Current source and configuration |
| --- | --- |
| Business API, Admin API and jobs | `supabase/functions/collect-api/`, `supabase/functions/admin-api/` and `supabase/functions/collect-jobs/`, sharing `supabase/functions/_shared/`. |
| PostgreSQL schema and storage | `supabase/migrations/`, generated from the curated inputs documented in `supabase/schema-src/README.md`; Supabase object storage through the current adapters. |
| Android member app | `lib/main.dart`; the native release configuration in `scripts/qa/native_build_config.py` requires the Supabase profile. |
| Cookie-authenticated Admin PWA | `lib/main_admin_cloudflare.dart`, selected by `scripts/admin_pwa_release_build.sh`; `deploy/platform-admin/` hosts the frontend and forwards its same-origin API traffic. The entrypoint's Cloudflare name does not select D1 as the business database. |
| Prior Cloudflare business backend | `deploy/platform-api/` and its D1/R2 recovery tooling are retained for legacy compatibility and the controlled transition. They are not the selected Supabase release backend. |

Use `.env.example` as the public configuration template. It selects `COLLECT_BACKEND=supabase`, project `rrlduytparvsjfmegalh`, and the intended Admin/proxy origin `https://platform-admin.collect.ikanisa.com`. Verify the final app, Admin artifact, proxy and deployed functions against one accepted source/configuration mapping before release; an origin in this template is not evidence that the corresponding production route is live.

Admin sessions use same-origin HttpOnly cookies. Sensitive operations require the applicable current grant and recent email verification; mandatory authenticator enrollment is retired. Member clients use the `/v1` protocol and their own protected session storage. Google sign-in and Realtime remain conditional. iOS/APNs/Apple distribution and optional pgvector are outside the current release goal.

Retained payment-evidence plaintext currently requires an Admin session, `payments.evidence.read`, `sms.read`, `sms.reveal`, recent email verification and an audited review reason. Known SMS derivatives are classified `raw_sms`; other existing untyped/manual text remains protected `unclassified`, since manual entry cannot establish non-SMS provenance. The reserved `ordinary` classification is not emitted by any current producer. Qualify the matching backend and Admin together before exposing this workflow.

Financial records distinguish retained receipts, recorded evidence, independent reconciliation and signed reversals. Recorded evidence is not a claim of provider settlement. Unsupported operations return an explicit unavailable response.

Keep server credentials in the corresponding server secret store, including Supabase Edge Functions; no secret belongs in Flutter defines. Real Turnstile, supported OTP delivery, native integrity policies, existing receipt/roster AI and push/email/SMS delivery require their own configuration and acceptance. The current receipt-AI adapter is in `supabase/functions/_shared/adapters.js`; its enablement, provider/model and acceptance must match the nominated deployment.

The scheduler remains inactive by default, with maintenance as its default mode. Separately admitted modes now support one receipt, one Android push, or one of each per tick. Source/model/provider configuration, approval identity and successful probe reconciliation must agree before activation. Changing `MOMO_PROCESSING_PAUSED` or a push enablement flag alone cannot activate a schedule. Read [the jobs guide](supabase/jobs/README.md) before scheduler work.

## Implemented readiness features

The current source includes these bounded features. Their code and local regression results do not establish a deployed release.

| Feature | Source and operating contract |
| --- | --- |
| Fixed-code diagnostics | [Client diagnostics](docs/CLIENT_DIAGNOSTICS.md) covers authenticated member/Admin capture, offline bounds, release/source grouping, quotas and expiry. No exception or SMS text is uploaded. |
| Android contribution push | The existing notification event feeds a durable per-device outbox and FCM HTTP v1 adapter. Unknown send outcomes remain retained and are never automatically resent. Default delivery remains disabled; real credentials and device acceptance are separate. |
| Admin oversight | [Operator workflows](tools/collect-admin-mcp/OPERATOR_WORKFLOWS.md) provides permissioned audit, queue health and diagnostic readouts through the read-only Admin MCP package. |
| Retention operations | The same guide documents a separate human-terminal workflow for existing approved-scope retention APIs, with durable previews and original-operation recovery. It cannot approve a policy or certify erasure of unsupported external copies. |
| Local contention measurement | [The bounded adapter harness](scripts/supabase/testing/batch-capacity.md) measures the actual PostgreSQL adapter and fence on an owned local fixture. It preserves the existing global correctness lock and makes no hosted-capacity claim. |

The two new additive migrations are `20261029120000_collect_client_diagnostics.sql` and `20261029130000_collect_notification_delivery.sql`. Their source counterparts are checked by `generate_baseline.py --check`. The original fourteen migration bodies remain immutable. Deploy the exact schema and matching API/Admin/client source as a coordinated candidate, with the existing writer fence and independently approved cutover controls. New schema/source hashes require new applicable retention and scheduler admission; previous approvals are not silently reused.

Use the pinned Flutter (`.fvmrc`), Deno (`.dvmrc`) and consumer-specific toolchains. Run affected analysis/tests and the required native lint/build checks. Signing, installed devices, hosted authorization, provider delivery, approved retention/erasure, full recovery and independent release approval remain separate requirements.

## Validation

The member app, Admin and public website use the sole owner-selected
[`revolut-design` skill](</Volumes/PRO-G40/Projects/ChatGPT/Revolut/skill/revolut-design/SKILL.md>).
Run `make revolut-design-authority` for reference hygiene; rendered route/state,
interaction and accessibility evidence remain required for visual acceptance.

```sh
make supabase-test
make source-integrity
make verify
```

`make supabase-test` checks the curated schema, current API runtime and current Admin/CLI consumers. Node owns every `_shared/tests/**/*.test.mjs` suite; pinned Deno 2.9.6 owns the TypeScript suites with the frozen lock. The discovery gate fails on empty or unassigned Node test selections. Read `.github/workflows/supabase.yml` and the Supabase job in `.github/workflows/ci.yml` for the pinned dependencies and isolated PostgreSQL test environment, including the diagnostics and delivery databases. A missing database, skipped SQL packet or unavailable SDK is an unresolved check, not a pass. `make verify` runs Flutter formatting, analysis and tests.

`make repo-wide-qa-uat` records local checks and unresolved release gates. Preserve the original 36 goal numbers and SB/BE/ARC/PD identifiers in the execution addendum. Its referenced canonical trackers and external receipts must be reconciled with the authorized workspace; do not manufacture acceptance records when those files are unavailable.

`make cloudflare-platform-test`, `CLOUDFLARE_PLATFORM_ACCEPTANCE_JSON` and the retained Cloudflare source-identity/recovery commands apply to that legacy backend's evidence. They do not certify the current Supabase deployment. The final current release must independently bind its source, signed Android artifact, Admin artifact, backend deployment and configuration to hosted authorization, financial reconciliation, delivery, recovery and owner approval evidence.

## Retained Cloudflare offline snapshot recovery

The following commands concern the prior D1/R2 backend and retained recovery custody. They do not restore or qualify the current Supabase database, Auth or object storage. Preserve this tooling and its historical evidence until the accepted transition and disposition plan permits retirement.

Complete exported SQL snapshots require all referenced table schemas before their
rows, with foreign keys enabled in one deferred-constraint transaction. The
statement-level migration installer keeps its existing API; it is not a complete
snapshot importer.

For the snapshot-importer successor, select `--support-profile auth17-snapshot-v2`
when running the approved toolchain guard. That profile pins both recovery tools
and `scripts/cloudflare/sql_snapshot_import.mjs`. The default and
`auth17-candidate-v1` profiles retain their historical hashes and do not authorize
the successor tools. A source/profile check does not approve deployment or restore.

Offline `platform_backup.mjs` actions that consume a database snapshot need a
qualified Wrangler 4.151.0 directory. `verify-local` requires its existing
`--wrangler /absolute/path/to/node_modules/wrangler` option. The other six actions,
`prepare-quarantine`, `verify-readback`, `verify-quarantine-readback`, `seal-r2`,
`restore-r2` and `verify-r2-readback`, accept that option or the
`COLLECT_WRANGLER_MODULE` environment variable pointing to the directory.
The parser option is rejected for `seal`. Verify the complete approved runtime
before use; the parser loader's own two-file check does not replace it.
Atomic preparation passes its already verified runtime parser directly.

Recovery or native-MCP operator wrappers that call these offline actions must
carry that parser location and the exact successor source/profile pins. No new
MCP capability, credential, remote-restore command or Google/OTP authority is
created by this change. Existing authenticated archive formats, exact migration
profiles, approved key roles and sealed archive bytes remain unchanged. Preserve
prior tool/source versions for historical receipts and prepare fresh atomic
packages after a tool-input change.

`node scripts/qa/recovery17_ci.mjs` runs synthetic recovery regression only and
removes inherited private `ACTUAL13_SQL` inputs. Full provider restores, key
custody, R2 version/lifecycle history, revocation/configuration parity and accepted
RPO/RTO require separate evidence.

The standard toolchain test command also runs the portable snapshot-profile
contracts. On the reviewed macOS arm64/Node/runtime host, set
`COLLECT_SNAPSHOT_PROFILE_ACCEPTANCE=1` to run the explicit profile admission,
sealed-bundle and source-tamper controls in
`scripts/tests/approved_toolchain_snapshot_test.mjs`, with the approved dependency
root and runtime manifest. Optional `COLLECT_SNAPSHOT_TEST_BUNDLE` and
`COLLECT_SNAPSHOT_TEST_CONFIG` select the exact existing local artifact pair for
check-only validation; the test never deploys or supplies publisher approval.
