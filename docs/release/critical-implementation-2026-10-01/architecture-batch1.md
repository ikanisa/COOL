# Delivery contract implementation — first batch

This is a scoped local implementation checkpoint for the critical review. It does not close hosted, provider, device, store, financial-policy or release-authorization requirements.

## Changes

- **ARC01:** Make resolves Flutter and Dart from `PATH` by default and exports explicit overrides. The offline test executes fake tools through Make and verifies an explicit Dart override, including compatibility with the host's Make version.
- **ARC03 / BE03:** `contracts/edge-functions.json` is the shared twelve-endpoint inventory for deploy, readiness and auth-contract UAT. It records the caller, auth mode, JWT setting, rollout constraint, required configuration names and seven retired endpoints. Both deployment and readiness consume its arrays. All seven endpoints with custom authorization receive `--no-verify-jwt`; all five user JWT endpoints retain platform JWT verification. Source/configuration drift fails before deployment operations.
- **ARC08, partial:** Supabase CLI selection checks the exact `.supabase-cli-version` release before a project command. Unversioned automatic downloads are removed. The previously interrupted edit's malformed command substitution is corrected. PostgreSQL client version/provenance pinning remains open.
- **BE04, integration:** Readiness checks all nine originating-session `_v2` RPC signatures and effective service-role EXECUTE, forbids member EXECUTE and rejects effective client/service access to the nine sessionless legacy RPC signatures. This extends the separately owned `20261001233000_assisted_sms_originating_session_fence.sql` implementation without modifying its migration or Edge adapters.
- **BE10, partial:** Auth UAT consumes the current inventory and follows factored handlers instead of assuming authorization lives only in `index.ts`. The signed OTP hook probe carries no secret or OTP and expects `invalid_hook_signature` with HTTP 401. Readiness probes all twelve endpoints; device/supervisor empty-envelope rejection and the scheduler's missing-secret rejection are checked separately. These negative probes establish endpoint rejection/presence, not valid signed-command behavior.
- **ARC05, partial:** The governed database-connectivity fallback retains strict platform readiness. Immutable candidate authorization before the first deployment mutation is still required and remains open.

## Verification

`architecture-batch1.json` records commands, captured outputs, log hashes and 93 source input hashes before and after verification. Those inputs were unchanged during this run.

- Inventory/schema/auth-wiring mutation tests: **6 passed, 18 assertions**.
- Executable offline deploy/CLI pin/portable tool/readiness contract tests: **6 passed**. This includes twelve deployments with the correct JWT flags, refusal before project operations when the CLI pin/source differs, strictness through the connectivity fallback, twelve unsigned endpoint probes and failure for a missing custom-auth endpoint.
- Existing secret transport suite with the exact-pin fixture: **5 passed**. Its existing Auth policy assertions were preserved.
- Auth contract UAT, shell parsing, Ruby syntax and scoped whitespace checks: **passed**.

The two new suites are wired into `make qa-tooling-test`. The entire aggregate was not run or claimed by this checkpoint. No Supabase/provider operation or deployment was performed; all executable delivery tests used local fixtures.

## Remaining integration

1. Converge the older local Edge audit consumer and CI entrypoints on the canonical inventory and frozen Deno lock/permission contracts.
2. Add the immutable candidate and scoped deployment authorization preflight before database/function mutations.
3. Execute the new readiness SQL against the reviewed full migration candidate, including clean and populated replay and negative grant states. The offline suite proves script behavior; it does not execute PostgreSQL.
4. Verify hosted endpoint inventory/auth settings/configuration names and all nine v2 grants and legacy revocations against the intended linked project.
5. Complete PostgreSQL client version/provenance governance and the remaining dependency/CI findings.

The existing `product-payment-focused.log` and `product-payment-focused-current.log` were inspected separately. They record earlier compilation failure and a later amount-field semantics assertion failure followed by interrupted tests. They do not supply a reusable payment batch pass; those files and the payment implementation were not changed here.
