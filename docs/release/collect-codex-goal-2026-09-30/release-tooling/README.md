# Collect release tooling foundation

This packet records local engineering checks. Exported copies are unapproved source snapshots. No export, hash comparison, installed toolchain or offline MCP handshake establishes source trust, review, owner approval, a frozen release, signing or production acceptance.

`python3 scripts/qa/collect_release_candidate.py export --destination /absolute/isolated/directory --report /absolute/report.json` selects current tracked files and nonignored untracked files within the declared application, backend, dependency-fork, test and tooling roots. It preserves current bytes and modes, records absent indexed source, checks required locks and installed Flutter metadata, reads back every copied file, and compares every selected source path again before accepting the export. It refuses symlinks, source changes during the copy, credential patterns and a preexisting or in-checkout destination. Top-level SQL migrations must have unique valid timestamp versions before any copy. Nineteen established 12-digit minute versions from May 2026 are explicitly preserved; all other versions require 14-digit dates and times. The manifest records the exact current migration inventory; deleted indexed migrations remain absent rather than being restored. The report retains the manifest SHA256 for a subsequent externally bound check.

`python3 scripts/qa/collect_release_candidate.py verify --candidate /absolute/isolated/directory --compare-source --expected-manifest-sha256 MANIFEST_SHA256 --report /absolute/report.json` detects tampered, missing, added or changed files and source drift by path. Source exports are exact: adding generated build output inside them makes that exact-export check fail. Keep source snapshots pristine and generated dependency bindings or builds in a separately recorded work copy.

Excluded inputs are explicit in the manifest: private configurations and signing material, ignored inputs, build/native caches, dependency installation directories, logs, QA payload dump formats, release reports and other non-source roots. Upstream `third_party/*/test/**` fixtures are excluded from this **build** export because they contain authentication fixture patterns; their exact paths, reasons and source SHA256 values are recorded without contents. The runtime fork code, library package manifests, locks, licenses and provenance remain included. The fixtures remain in the checkout. Full controlled fork regression coverage and full source/test acceptance remain open. Pattern detection does not establish real credential exposure, and it is not a comprehensive secret/privacy audit.

`python3 scripts/qa/collect_release_candidate.py mcp-offline --candidate /absolute/isolated/directory --expected-manifest-sha256 MANIFEST_SHA256 --report /absolute/report.json` safely parses the local host profile, enforces exactly the five approved read tools, checks installed Node/SDK/Zod metadata, verifies current source still matches the candidate, and starts the existing configured bridge with a credential-free environment. It performs only JSON-RPC initialize, initialized notification and tools/list, validating the read schemas. It makes zero tools/call requests, backend reads, OTP requests or provider calls. It reports no config environment values or credentials. A successful result proves local installation/runtime/discovery and candidate metadata binding only; governed authentication and live backend authorization remain separate gates.

The required six lock inputs are `pubspec.lock`, `Gemfile.lock`, `android/app/gradle.lockfile`, `ios/Podfile.lock`, `supabase/functions/deno.lock` and `tools/collect-notification-mcp/pnpm-lock.yaml`. The manifest also inventories other selected locks, the Android wrapper input, local Flutter pin/installed metadata and Node/Python/Deno metadata. Restore generated dependencies with frozen locks separately before a build. Native/public provider configuration excluded from source needs its governed build flow.

Synthetic checks: `python3 -W error::ResourceWarning -m unittest scripts.tests.test_collect_release_candidate -v`. Actual output and command/exit metadata are retained in `release-tooling-tests.log` and `release-tooling-tests.result.json`. Failed export attempts are retained as separate JSON reports; they do not attest a candidate exists. No commit, push, deployment, hosted mutation, OTP or live shadow lifecycle is part of this tooling.

## Retained compilation snapshot

The current source tree changed during controlled attempts. Candidate01 was never created. Candidate02 finished copying, then failed its current-source check because a new synthetic session regression test appeared. Its 1,688 source files were retained at `/Volumes/PRO-G40/Projects/Collect-Release-Candidates/collect-local-20260930-release-tooling-02`, source timestamp `2026-09-30T21:00:18Z`, manifest SHA256 `4d49758c617893d96740bebc7ec9f34beac783c4d6019daadf754ed6e851a4fc`. Candidate03 stopped before its final rename on another QA addition. All attempt reports are retained. Snapshot02 remains explicitly unaccepted as the current original tree; it is neither a reviewed source nor a production freeze.

With the root agent's instruction to compile the retained exact snapshot while reporting drift, `prepare_admin_workcopy.py` verified and copied snapshot02 to a separate build work directory. `run_admin_build.py plain` used pinned Flutter 3.44.4, offline `pub get --enforce-lockfile`, and `build web --release --no-pub --no-wasm-dry-run --target lib/main_admin.dart`. All six locks and selected source files remained unchanged. The package config binds the app and three local runtime forks inside the work copy, with other dependencies in the existing cache or pinned SDK. The plain bundle is backend unconfigured compilation evidence at `collect-local-20260930-admin-build-02/build/web`.

`run_admin_build.py evidence` separately compiled the same source with `ADMIN_PWA_EVIDENCE_MODE=true`, directing output to `collect-local-20260930-admin-build-02/build/admin_evidence`. It supplies synthetic auth/repository fixtures for local route/state captures. It is not an authentication-connected or deployable production bundle. Both bundles contain 155 files, have actual command logs, source/artifact hash maps and readback receipts, and keep all approvals false. `candidate02-artifact-bindings.json` ties the source, included shadow/Overview/transaction lifecycle inputs, reports and explicit later drift together. The original snapshot stayed pristine and passes post-build exact readback without making a later current-tree claim.

The candidate-linked offline MCP report compares all 42 bridge source/package inputs directly with snapshot02, then performs the real current-host initialize/tools-list sequence. It retains five enabled reads, 16 registered tools and zero tool calls, backend reads or OTP requests. Because unrelated QA work resumed, the report explicitly does not claim whole-current-tree comparison. Later runtime/migration differences are captured separately in `candidate02-later-current-drift.json`. The owner-selected sender direction is the Android gateway; this packet performs no provider or gateway sends.

## Next Admin checkpoint runner

`run_admin_checkpoint.py` retains the previous compilation runner's pinned/offline
source and package checks while accepting explicit `--candidate`, `--workspace`,
`--manifest-sha256`, `--packet` and `--label` inputs. Use `prepare_admin_workcopy.py`
to create the work copy from an independently bound pristine candidate first.
The checkpoint runner refuses symlink/overlapping/in-checkout workspaces, checks
all selected source bytes/modes before and after compilation, and reads the
pristine candidate back afterward. Each command has a fixed deadline; a timed-out
command keeps its actual partial log and exit-124 receipt. Source/code-pattern
redaction rejects unsafe output before it is written or printed.

The `plain` mode supplies no production backend configuration and first resolves
from the existing cache with `pub get --offline --enforce-lockfile`. The separate
`evidence` mode explicitly enables synthetic fixtures. Neither mode claims live
email authentication, enrollment, provider access, deployment or source approval.
Seven focused synthetic failure checks pass in `admin-checkpoint-tests.log`;
they execute no Flutter or network command. The initial macOS temporary-directory
alias expectation is retained as `admin-checkpoint-tests-attempt01.*` and is not
counted as passing evidence. Actual checkpoint exports/builds use separate numbered
packets and preserve all prior candidate/build evidence.

## Governed public configuration

The checkpoint runner supports a third, distinct `configured` mode. It requires
`--defines-file` and the root-provided exact `--defines-sha256`. The JSON contains
exactly `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `ENABLE_ADMIN_PANEL` and
`APP_ENVIRONMENT`; the URL must match the fixed Collect project, the key must be
public publishable form or an unexpired public-anon JWT with matching project
claims, the Admin panel must be true and environment must be production. It
rejects user/service/secret credentials, unknown/CAPTCHA/dev/SMS overrides,
duplicate keys, malformed JSON, wrong hashes, symlinks and unsafe file modes.
The external file must be owned by the current user with mode0600 and an owned
mode0700 immediate parent, outside the source/candidate/work copy.

The exact public bytes are staged under a separate private generated-input folder
in the work copy with hash readback; Flutter reads that file through
`--dart-define-from-file`. Input hashes are checked again after compilation.
Configured output goes to `build/admin_configured`; unconfigured output goes to
`build/web`; synthetic output goes to `build/admin_evidence`. Logs redact the
supplied public key before writing/printing, retaining raw-output SHA256 and
redaction counts. Reports contain public input metadata/hash, never key values.
Sixteen final synthetic runner/configuration/failure tests pass; prior seven-case
runs are retained and are not added to the final count.

Local public-key syntax/claims checks do not cryptographically establish issuer
or prove live authentication. Root's separate dated configuration provenance and
settings readback are linked by SHA256 in each checkpoint packet. In checkpoint04,
that recorded settings response reports email authentication disabled. Successful
configured compilation cannot close hosted email enablement, SMTP, OTP, authority,
UI journey, deployment or production release gates.

## Explicit retained implementation checkpoints

Default `export` remains strict. Only explicit `--retain-source-drift` streams
screened, individually stable file reads immediately into an isolated snapshot,
hashes/readbacks those same bytes, and records later changed/added/removed source
paths with prior/current hash, byte and mode metadata plus the capture interval.
It never substitutes later bytes into the captured file table. It also records
excluded-fork-fixture and indexed-absence changes. This snapshot is classified
`unapproved_non_atomic_implementation_checkpoint`, even when its end comparison
observes no drift: simultaneous original-tree coherence cannot be inferred.

Required/additional locks, SDK pins, dependency declarations and native wrapper
inputs must match before capture, within the captured table and afterward.
Installed toolchain metadata must match before/after. Changed pin inputs still
refuse preservation. Secret-pattern, ancestor/source symlink, migration validity,
per-file integrity and final exact candidate readback checks remain mandatory.
Every approval and `source_current_tree_accepted` stays false. The snapshot can
support local compiler/regression evidence with dated drift; it establishes no
reviewed release, current original-tree freeze or production acceptance.

The full updated exporter regression log has 38passing synthetic cases in
`checkpoint04/exporter-opt-in-tests.log`. Its retained initial failure came from
an unchanged cold malformed-stdio fixture missing its 0.7-second startup budget;
malformed/oversized cases now have 5 seconds while the actual hang deadline remains
0.7 seconds. No production deadline was broadened. Snapshot04's actual strict
source-change failure remains recorded; new source05/build05 are separate.
