# Collect notification bridge and Git packaging checkpoint

15 September 2026 (Africa/Kigali). The full P0–P8 QA goal remains active.
The notification stdio preflight now rejects malformed queue health before
reading pending jobs. A missing dependency lockfile and six missing photo
inventory entries are corrected for the requested Git push. These changes
do not establish production, provider, native or owner acceptance.

## FQA-044: malformed health could pass the stdio preflight

The original actual stdio preflight accepted `{enabled:false}` without any
queue counts and printed `PASS_AUTHENTICATED_STDIO_MCP`. A real child-process
and loopback HTTP regression reproduced that false pass: two of three tests
passed and the malformed-health test failed before the fix.

Both preflight paths now share validation requiring a boolean enabled flag
and six nonnegative safe integer counts. The stdio path validates health
before calling the bounded pending list. Its output remains aggregate-only.
Missing, string and negative counts are rejected without a list request;
oversized pages and authorization failures remain blocked without exposing
the synthetic private response fields or credentials. FQA-044 is fixed locally.

The final suite passes **37 Node tests**, with zero failures, skips or
cancellations, and TypeScript checking passes. The previous 30-test baseline
is preserved. New tests exercise all nine actual stdio tool mappings over
real loopback HTTP, exact action/fence/confirmation fields, the default page
bound, rejected invalid inputs, HTTP 401/403/409/503 failures, invalid JSON,
redirect refusal and the actual 15-second timeout on a synthetic mutating
command. Only one HTTP attempt occurs in the timeout case. The redirect
target receives no request.

These tests use isolated synthetic credentials and responses. They do not
read Keychain, send an OTP or message, mutate a production queue, verify SQL
persistence, grant an operator permission or prove provider delivery. The
existing helper/session renewal tests remain part of the passing suite;
real Auth, operator role and physical Messages outcomes remain separate.

## FQA-045: committed photo packaging was incomplete

Current branch commit `2650b3b9` already contained the earlier QA and photo
delivery work. Its public CI workflow called `npm ci`, but the repository-wide
`package-lock.json` ignore rule excluded the new photo package lockfile from
that commit. The source-hygiene gate also failed because the six reviewed
WebP encodings were absent from the visual asset hash inventory.

The ignore rule now has a narrow exception for the photo lockfile. Exact
staged Git blobs for the package and lock were extracted into an isolated
directory; `npm ci --ignore-scripts` and the actual encoder check both pass
using those installed dependencies. The owned dependency copy was then
removed. The six encoded hashes were added to the existing inventory without
altering any prior entry or image bytes. They match the earlier visual review
and encoding records. Inventory registration is not owner or native acceptance.

The original source-hygiene failure is preserved. The corrected source-hygiene
gate passes with zero failures. The redacted fallback secret scan passes;
Gitleaks was unavailable. Twelve photo tests with 57 assertions, deterministic
encoding and `git diff --check` also pass. FQA-045 is fixed locally; hosted CI
is not inferred from these local checks.

## Continuity and requested publication

Thirty-three current inputs are bound by the
[source checkpoint](../../../.cache/fullstack-qa/20260914T151002Z/notification-bridge/source-checkpoint.json).
All 552 inputs from the previous 168-Ruby/768-assertion and nine-Python
checkpoint still match. The photo and notification checks above are current;
the full Ruby/Python and Flutter suites were not repeated for this narrow fix.
The earlier full Flutter result remains 867 passes and 74.65% measured coverage,
with 609/615 inputs matching. The asset inventory is the one additional changed
input. All product Dart, platform source and original photo bytes are unchanged
in this continuation. Of the synthetic Admin build inputs, 412/413 match; only
that same inventory differs, and all 154 built artifacts remain unchanged.

The user's settings and zero-case native acceptance file are preserved. Both
native gates remain blocked with 966 required cases per platform. FQA-042
mobile performance, stale native website media, broken privacy destinations,
the PWA online-state indicator and other open findings remain unresolved.

The user explicitly requested a commit and push to `main`. The remote main
readback was `7be12232`; the current branch was four commits ahead with no
remote-only commits before this new fix. Git publication is being performed
separately from deployments, database migrations, store releases or acceptance.
This checkpoint records the pre-push source and tests; the final Git command
and remote SHA readback provide publication evidence after the commit exists.

The [verification](../../../.cache/fullstack-qa/20260914T151002Z/notification-bridge/checkpoint-verification.json)
retains the reproduced failures, final checks and current document/source hashes.
