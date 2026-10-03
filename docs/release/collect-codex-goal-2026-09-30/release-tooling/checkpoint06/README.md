# Source06 and configured Admin compilation

Local capture/readback, configured release compilation and the two requested
existing regression files passed. Source06 is an **unapproved, non-atomic
implementation checkpoint**. It is usable as an exact source/build evidence
binding; trust, review, freeze, owner approval, signing and production acceptance
remain false. Approval of the local execution plan in `PLAN.md` does not supply
any of those release approvals.

## Exact source and output

| Item | Retained result |
| --- | --- |
| Pristine source | `/Volumes/PRO-G40/Projects/Collect-Release-Candidates/collect-local-20261001-source-06` |
| Derived build workcopy | `/Volumes/PRO-G40/Projects/Collect-Release-Candidates/collect-local-20261001-admin-build-06` |
| Configured output | Workcopy `build/admin_configured` |
| Capture interval, UTC | 2026-10-01 08:42:44–08:45:21 |
| Selected files | 1,905; 154,222,431 bytes |
| Captured migration inventory | 175 unique valid versions; inventory only |
| External source-manifest SHA256 | `3dde2f704488a7a18d7d9f916f2451d76a8662bb79619b788d792706d11ba42f` |
| Selected-file-table SHA256 | `f1b1d31c9b77372f9edcfc2ebdf3a37264bfe17265e9b10683e94898c8ee5d13` |
| Configured artifacts | 155; 66,349,485 bytes |
| Artifact-map SHA256 | `109257ba0e3dcb621fba9d31d3cfb431931b8601075335cbdbcfa655a28a40ae` |

`captured-source-manifest.json` retains the exact external source manifest;
`source-export.json`, `source-readback.json` and `workcopy-prepare.json` retain
actual copy/readback receipts. All 1,905 selected bytes and modes were verified.
The source snapshot was kept pristine. Generated public build inputs, package
bindings and compiler output exist only in the separate derived workcopy.

The exporter screened tracked plus nonignored untracked source using its
declared policy. Forty upstream fork QA/auth fixtures were excluded with their
exact paths, hashes and reasons in the captured manifest. One indexed source
path was absent, `web/public/app-screens/terms-377e5eed2d41.png`, and remains
explicitly recorded as absent. This export does not close full upstream fork
tests, completeness, security or source-provenance acceptance.

The captured base HEAD observation was
`df1150ea118aa5dcc9ecb880c71873423081bffe`; selected dirty and untracked bytes
are governed by the per-file manifest, not assumed to equal that commit.
`source06-input-binding.json` binds 112 Admin, contract and new-migration paths,
the six locks and 21 critical pin/dependency/native inputs to the captured source.
No selected, excluded-fixture or indexed-absence drift was observed during the
capture comparison. The selected mode still makes no atomic coherence or
reviewed-freeze claim.

## Actual compilation and regression

The configured runner completed offline `pub get --enforce-lockfile` within its
240-second bound, then compiled `lib/main_admin.dart` as a release web target
with `--no-pub --no-wasm-dry-run` within the unchanged 600-second bound. The
compiler command ran 08:49:42–08:50:29 UTC and exited zero. No synthetic
`ADMIN_PWA_EVIDENCE_MODE` override was supplied. Raw command/completion receipts
and safe compiler logs are retained in `admin06-*` files. A later independent
readback matched every one of the 155 artifact bytes and the canonical artifact
map (`artifact-readback.json`, `artifact-manifest.json`).

The installed pin was Flutter 3.44.4 / Dart 3.12.2, framework
`ad70ec4617166f1c38e5d2bfd388af71fda14f06`. Launcher, SDK metadata and reviewed
tool bytes matched before and after. Offline dependency configuration bound
168 package roots: four workcopy roots (the app and three retained forks),
156 existing cache roots and eight pinned SDK roots. This is the actual
lockfile/root binding used for compilation; it is not a new package-signature
or advisory audit. See `admin06-dependency-binding.json` and the runner receipt.

Only the requested existing `test/admin_automations_test.dart` and
`test/admin_pwa_test.dart` were executed in the source06-derived workcopy.
**39/39 passed**: exit code zero and the explicit `All tests passed!` completion
marker were both required. The scoped harness retained its own and the
exporter's exact bytes before execution and verified them afterward. All
selected source files, six locks, package configuration and pinned SDK inputs
remained unchanged; final pristine source readback passed. This was one actual
two-file run, not an aggregate of earlier suites. See
`admin06-scoped-regression.result.json` and `admin06-scoped-regression.log`.

An unrelated build used the shared pinned SDK in parallel. Read-only startup
checks found no held Flutter startup lock or SDK mutation before this governed
web invocation, and subsequent metadata/launcher proof remained stable. No
other process was stopped and no deadline was enlarged.

## Configuration privacy and later checkout drift

The existing owner-private public-defines file was validated using the reviewed
runner without printing or retaining its values in this packet. It supplied only
the fixed project's four permitted public build inputs. File mode 0600, parent
mode 0700, size 203 bytes and SHA256
`78c61fceea0b72981fada0d50af45aeba9d2955e92159927e819b70fd31f9206`
matched before/after staging and compilation. No user, service-role, Auth or
provider credential is permitted by this input contract. The derived compiled
application necessarily includes its public client configuration.

No fresh remote Auth setting or sign-in was checked. The earlier dated public
Auth readback reported email disabled; that historical observation is not a
verified current setting. Configured compilation proves neither email login
availability nor hosted deployment.

After build/regression, a dated original-checkout comparison returned blocked
because one selected source path had been added:
`scripts/tests/collect_synthetic_backup_restore_uat.py`, 34,801 bytes, SHA256
`890e1d7f477cd05c8867bda4862636dc2a66e42eb2e9f2b981168eebdac788d6`.
It was absent from source06. All 21 critical inputs still matched at that later
hash observation. The raw exit/comparison report and enriched prior/current
hashes are retained in `later-current-source-*`. This does not invalidate the
exact captured compilation, and the later script was not substituted into the
candidate. Original-tree stability or current-tree acceptance is not attested.

## Separate evidence and remaining acceptance

The sealed `mcp-evidence-association` leaf compares existing historical journal
and discovery evidence inputs to source06: 58/58 and 42/42, respectively, with
60 distinct input paths in their union. It does **not** rerun the historical
139 Node tests/TSC, 16-tool registration or exact five-read host discovery.
The configured read-only host allowlist and current Node version were observed;
the historical Node executable hash was not recorded. Those historical results
are not added to the 39 tests executed here.

The independently sealed `source-access-preflight` leaf records seven bounded
read-only GitHub metadata GETs using the normal configured CLI. The reported
remote main SHA matches the captured base HEAD, while the local modified and
untracked file bytes remain separately governed. GitHub reported main
unprotected; protection/ruleset reads were unavailable because of a plan
restriction, and code-scanning setup required Advanced Security. Dependabot
settings were observed without reviewing alerts or attesting remediation.
No security setting changed and C33 source/security acceptance remains open.
This dated metadata leaf supplies no source-trust or production approval.

Root's operating-policy 65-case packet and MCP's joined-audit/canonical-link
packets retain their own exact input scopes and logs. Their counts are not a
combined source06 test suite. Earlier source05, cancellation, gateway,
exceptions and native-device packets remain historical, separate evidence.

This packet performs no deployment, Auth/OTP request, account provisioning,
Keychain access, personal-profile access, business RPC, provider send, signing
or publication. Hosted migrations/configuration, authenticated browser routes
and state/permission testing, governed visual comparators, real Android/device
and carrier observations, recovery/operating procedures, source/release review
and owner acceptance remain separate gates. The sole Revolut authority is
unchanged; compilation and these scoped tests do not certify visual fidelity or
whole Admin/Collect readiness. `completion.json` and the packet manifest keep
all release approval and production acceptance flags false.
