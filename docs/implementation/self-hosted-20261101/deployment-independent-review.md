# Independent deployment and scheduler review — 2026-11-01

This bounded static review covered `scripts/self_hosted/scheduler.py`, the prepared release/configuration/operator/database/health helpers, the source-bound main and email scheduler operators, and the public Auth/Edge environment routing. It was performed independently of their implementation. It did not mutate shared runtime or deployment source while the final source-bound mobile/history packet and integration run were being prepared.

## Findings delivered to the deployment owner

These describe the initially inspected revision. A subsequent independent source readback confirmed that the deployment owner corrected all five, as detailed below. Native Vault/provider/Docker acceptance remains separate.

| Finding | Observed behavior | Required correction |
|---|---|---|
| Existing Vault-token custody check is incomplete | `native_custody()` accepts the existing name and SHA commitment in its description without comparing the actual decrypted value. A changed value with an old description can be reported configured. Later authenticated probes would reject a bad token; no authorization bypass was established. | Compare the actual token hash inside SQL with the generated expected hash. Return no plaintext. Preserve the existing secret and refuse discrepancies. |
| Main scheduler custody omits the new SMS role | The preparation revocations and main operator preflight omit `collect_sms_runtime`; the email SQL artifact includes it. No automatic grant or current data exposure was observed, but a direct grant to that role would escape the main preflight. | Include the installed SMS runtime in Vault/net denial checks and revocations. Retain historical compatibility when the role is absent. |
| Existing email installation is not matched to the requested artifact | `install_email()` returns status when `collect_ops.email_config` already exists, without checking its rendered config/template identity or requiring an inactive lane. | Verify exact profile, endpoint, config and template hashes and both disabled indicators on retry. Refuse drift or an active lane; do not overwrite retained configuration/history. |
| Health can miss a crossed open source | Health reports the prepared release source but only checks controller mode, not its observed source hash. An open controller bound to a different source would deny runtime admission but could be reported healthy. | Compare the observed controller source to the release source and emit a stable mismatch alarm. |
| Stopped-lifecycle proof runway is omitted | Finite-capacity monitoring reads three resource-limit counters, but `stoppedLifecycleProofs` lives at the top level and has its own 10,000 ceiling. Unknown-obligation alarms still report retained stopped work. | Add an explicit 80% runway alarm for the stopped-lifecycle proof count. Preserve the immutable proof and its unresolved obligations. |

### Correction readback

- `scheduler.py` now compares the actual decrypted Vault value's SHA-256 inside SQL as well as the name/description commitment. Mismatches refuse reconciliation without rotating the secret or returning plaintext.
- The preparation revocations and `jobs_operator.mjs` preflight now include `collect_sms_runtime`. The preflight selects existing roles, preserving absence compatibility with historical fixtures.
- Existing email installation retries now compare the freshly rendered template/config hashes, exact profile/endpoint and both `enabled: false` and `cron_active: false`, refusing any discrepancy without replacement.
- `health.py` now compares the observed controller source with the expected release source and emits `source_mismatch`. It also reports missing expected services.
- `health.py` now alarms on `stoppedLifecycleProofs >= 8,000` against its 10,000 limit. Independent direct execution of the actual evaluator confirmed no stopped-proof alarm at 7,999, the precise alarm at 8,000, and a source mismatch alarm for an otherwise healthy open controller.

These corrections were verified from the maintained `release_operator.py` module path; no duplicate `operator.py` was created. Their closure is a source/health-behavior review, not a claim that actual Vault, Cron or Docker activation was exercised here. Actual database TLS and restricted driver behavior were separately qualified in `database-tls-native-result.json` and documented in `database-tls-status.md`.

## Controls confirmed in the inspected source

- Prepared releases verify an exact source inventory, public profile digest, image digests and sealed configuration. Unrecognized extra source files are refused.
- Only the TLS proxy publishes host ports. Private API/database/service dependencies remain on the deployment network; owner credentials are restricted to explicit operator work.
- Edge logins use separate application and SMS roles, NOINHERIT/NOBYPASSRLS and exact role-membership verification. Publication checks actual credential authentication over CA- and hostname-verified database TLS.
- The public Auth proxy checks exact origins, canonical paths, body limits, case-insensitive GoTrue field aliases and the real Auth user/factor for routes whose phone or guest effects are implicit. Internal Collect calls use the fixed private gateway.
- SMS hook/gateway/scheduler credentials are restricted to their function environments. No owner database or JWT signing key is passed to user functions.
- Main/email probes retain the caller's original dispatch UUID. The wrapper does not retry uncertain provider work under a fresh identity. SQL outcome reconciliation and activation remain explicit.
- The migration installer preserves the original sixteen files. Each migration and its installation receipt commit in the same transaction. SQL10 changes only two separately reviewed metadata literals; observing a catalog hash does not approve it.
- Roster AI production activation is refused because the current Python/native-codec helper and SQLite replay state do not satisfy the Supabase-native parser requirement.

## Acceptance boundary

This review does not certify a running Docker deployment, actual SMTP/SMS/push/AI delivery, certificate lifecycle, real Auth/Storage/Realtime compatibility, whole-host restore or mobile devices. Those checks belong to the owner's exact combined-chain/native-runtime and later production evidence. No additional confirmed runtime authority defect was found in this bounded pass.
