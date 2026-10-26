# Collect

Collect is a Rwanda group-contribution system with a Flutter member app, Admin PWA and public website. The independent backend uses Cloudflare Workers, D1 and private R2. Contributions use whole RWF through MTN MoMo or Airtel Money USSD; payment authorization remains with the network provider.

The fresh API is `https://api.collect.ikanisa.com`. The new Admin workspace is `https://platform-admin.collect.ikanisa.com`. Its password and authenticator sessions use same-origin HttpOnly cookies. Member clients use the `/v1` protocol and their own protected session storage.

Canonical backend source is `deploy/platform-api/`; Admin service forwarding is `deploy/platform-admin/`. Both use the single new database `collect-platform` and private bucket `collect-platform-private`. The platform starts from its reviewed Cloudflare schema and does not import legacy data.

Financial records distinguish retained receipts, recorded evidence, independent reconciliation and signed reversals. Recorded evidence is not a claim of provider settlement. Unsupported operations return an explicit unavailable response.

Copy the public settings from `.env.example` for client builds. Keep server credentials in Worker secrets. Real Turnstile, OTP delivery, native integrity policies, AI approval and push/email delivery require their own configuration and acceptance. Current evidence and outstanding findings are in `docs/release/critical-implementation-2026-10-01/`.

Use the pinned Flutter and Wrangler versions, run affected analysis/tests and the standard full native lint/build checks. Signing, installed devices, provider behavior, approved retention/erasure and full recovery remain separate release requirements.

## Validation

The member app, Admin and public website use the sole owner-selected
[`revolut-design` skill](</Volumes/PRO-G40/Projects/ChatGPT/Revolut/skill/revolut-design/SKILL.md>).
Run `make revolut-design-authority` for reference hygiene; rendered route/state,
interaction and accessibility evidence remain required for visual acceptance.

```sh
make cloudflare-platform-test
make source-integrity
make verify
```

`make repo-wide-qa-uat` records current local checks and unresolved release gates.
Hosted authorization, financial reconciliation, delivery, backup restoration,
physical devices, signed artifacts and owner approval require their own evidence.

Hosted acceptance is supplied through `CLOUDFLARE_PLATFORM_ACCEPTANCE_JSON`.
`python3 scripts/qa/release_evidence.py source-identity` prints the current
source digest. The reviewed record must bind that digest, declare an expiry,
and include hashed evidence for authentication, authorization, financial
reconciliation, delivery and backup restoration; owner approval remains a
separate release gate.

## Offline snapshot recovery

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
