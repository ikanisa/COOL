# System QA execution — 13 September 2026

Overall status: **in progress; not approved for release**. The full objective in
`PLAN.md` remains active. This checkpoint repairs broken QA infrastructure and
establishes current automated evidence; it does not certify every journey,
platform, permission or deployed feature.

## Changes implemented and verified

- **QA-F01 resolved locally:** CI now calculates unique covered lines instead of
  adding execution counts. Missing, empty, malformed and truncated reports fail.
  Duplicate source records merge without inflating the denominator, and rounded
  display percentages cannot pass a threshold that the exact ratio misses.
  Eight regression tests pass and CI runs them in repository hygiene. The
  existing 40% threshold is unchanged.
- **QA-F02 resolved locally:** the missing `test/integration_smoke` command now
  runs current member/Admin fixture journeys. Its exact five-file command passes
  14 tests. The job is accurately named as fixture journey smoke. Native device
  integration coverage remains required separately.
- **QA-F03 resolved locally:** restored the missing MoMo contract script with
  explicit runtime/file checks. It runs current amount/number/USSD/permission,
  attestation, mobile flow and backend source contracts plus deterministic receipt
  parser tests. The exact script passes 118 Flutter tests and 31 Deno tests. It
  does not claim SQL finality, provider or native SMS capture acceptance.
- **QA-F04 resolved locally:** the Offline/Sync test now expects the recently
  added titles and Back control while retaining recovery-state assertions.
- **QA-F05 resolved locally:** the profile-country test owns a separate offline
  cache key. In the failing randomized order, a write queue from an earlier test's
  fake-async zone left its Save future pending, although the fixture profile had
  updated. The test passed alone before the fix. The same failing seed now passes
  all 86 tests in the two affected files; the full rerun also passes this case.
  Production cache serialization and profile behavior are unchanged.

These fixes are current working-tree changes, not a newly verified hosted CI run.

## Executed evidence

Starting source: `7be122328d50e9b635b7fabc0513b82b10a0ea62`, with the changes above
copied into an isolated detached worktree for reruns. The local bundle path is
recorded in `.cache/system-qa-20260913/active-path.txt`. `VERIFICATION.json` records
log hashes and source fingerprints. No production credentials were copied into
the test checkout. No production data or schema was modified.

| Check | Actual result | Evidence in local bundle |
| --- | --- | --- |
| Flutter dependency resolution | Pass, offline with enforced lockfile | `flutter-pub-get.log` |
| Flutter analysis | Pass, fatal infos enabled | `flutter-analyze.log` |
| Original full unit/widget/golden run | 763 passed, 3 failed; seed 20260913, concurrency 4 | `flutter-tests.log`, `flutter-test-events.jsonl` |
| Full rerun after fixes | 765 passed, 1 failed; same seed/concurrency; Offline golden remains | `flutter-repaired.log`, `flutter-repaired-events.jsonl` |
| Correct line-coverage gate | Pass against unchanged 40% threshold; see exact ratio in log | `coverage-gate.log` |
| Two affected Flutter suites | 86 passed with original failing random seed | `repaired-random-order.log` |
| CI fixture journey command | 14 passed | `journey-smoke.log`, `journey-smoke-events.jsonl` |
| CI MoMo contract command | 118 Flutter + 31 Deno tests passed | `momo-lane.log` |
| All edge unit tests | 54 passed, 0 failed | `deno-tests.log` |
| All edge TypeScript files | 38 checked successfully | `deno-check.log` |
| Reviewed local Ruby regression suites | 116 tests / 487 assertions passed across 21 files | `local-baseline-results.json`, individual test logs |
| Ruby/shell syntax | 170 files passed, including the restored script | `syntax-results.json` |
| Notification operator tool | 30 tests passed; TypeScript check passed; exact existing package and pnpm lock matched cached dependencies | `notification-tool-tests.log`, `notification-tool-typecheck.log` |
| Admin release web compilation | Pass; compilation only, no deployment or authenticated browser acceptance | `admin-web-build.log` |
| Migration file validation | Pass | `migration-validation.log` |
| Source design hygiene | Pass | `source-hygiene.log` |
| Secret scan | Pass using tracked-file fallback; gitleaks is unavailable | `secret-scan.log` |
| Notification route contract | Pass | `notification-contract.log` |
| Public static CI command | Blocked by stale app screenshots after 7 media tests pass | `public-static-gate.log` |

Test counts overlap between full and focused suites; do not add them into a count
of distinct tested features. Unit/parser checks are not live provider or database
transaction tests. The five database/recovery Ruby targets excluded from this
local baseline are explicitly listed in `local-baseline-results.json` and remain
unverified, along with the SQL/UAT scripts outside that unit-test set.

## Findings still requiring work

**QA-F06 — Offline visual mismatch.** The new title shifts the recovery content
as intended, but the golden test image also omits the bottom navigation. Both
previous and candidate PNGs were opened. The test still finds navigation at
`Rect(16,772,374,832)`, and the existing browser review visibly renders it. That
does not explain or clear the golden discrepancy, nor prove native behavior.
The baseline and original tolerance remain unchanged. Reproduce the
paint/capture issue, check the current native candidate, and review the
resulting image before any baseline update.

**QA-F07 — Public app imagery is stale.** `public_static_site_build.rb` rejects
the app screenshot runtime fingerprint. Fresh current-source captures and visual
review are required. Do not replace the fingerprint alone or disable the check.

**Mobile acceptance remains blocked.** The gate reports missing/changed original
references IMG_2739–2742 and IMG_2747–2752, absent/stale acceptance hashes/version,
open findings, missing/mismatched Android APK/AAB and missing Android build
provenance. Current-source native state/interaction/accessibility evidence and
actual approval remain required. Contract validity is not design acceptance.

**Native and isolated database execution remains open on this host.** Xcode.app,
Docker.app and the default Android SDK are absent; Apple command-line tools are
selected. This is a verified local limitation, not proof that all possible
connected targets are unavailable. Continue discovery or provision an explicitly
isolated runtime before mutation, financial concurrency, migration replay or
device-permission tests. Keep productive code/browser/read-only review moving.

## Deployed Supabase read-only checkpoint

The linked `COOL` project `lhbowpbcpwoiparwnwgt` returned `ACTIVE_HEALTHY` with
PostgreSQL 17.6.1.021. Its 124 migration versions match the local version set,
with no missing or remote-only versions. Versions 202605230012–014 have differing
names. This confirms version inventory only; definition, grant, policy and data
equivalence are not established. See `migration-comparison.json` and the raw
metadata in `.cache/system-qa-20260913/deployed-migrations.json`.

The security advisor returned categories requiring contextual review: 46 tables
with RLS and no policy, 19 anonymous and 32 authenticated GraphQL-visible objects,
6 anonymously executable and 134 authenticated security-definer functions, and
disabled leaked-password protection. These are diagnostic observations, not 238
proven vulnerabilities. Collect intentionally uses restricted RPCs and private
tables; verify role grants, policies, caller checks and exposed schemas against
the product contract before changing them. The password diagnostic must be
assessed against the actual OTP-only authentication configuration.

Relevant advisor guidance: [RLS without policies](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy),
[anonymous GraphQL visibility](https://supabase.com/docs/guides/database/database-linter?lint=0026_pg_graphql_anon_table_exposed),
[authenticated GraphQL visibility](https://supabase.com/docs/guides/database/database-linter?lint=0027_pg_graphql_authenticated_table_exposed),
[anonymous definer functions](https://supabase.com/docs/guides/database/database-linter?lint=0028_anon_security_definer_function_executable),
[authenticated definer functions](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable),
and [password protection](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).
Raw advisor metadata is retained locally in
`.cache/system-qa-20260913/security-advisors.json`.

## Next execution checkpoint

Resolve QA-F06 and QA-F07; inventory every
registered route, edge endpoint and callable RPC with its role/state coverage;
then run the database/API authorization and rendered Admin/member/public journey
lanes. Continue all QA-01–18 requirements in `PLAN.md`, including native devices,
provider handoffs, accessibility, recovery, performance and human acceptance.
