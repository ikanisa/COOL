# Pending source06 / configured Admin checkpoint

This plan uses the existing reviewed exporter, exact-copy helper and configured
Admin runner. No source06 capture, dependency resolution or compilation has
started. Capture waits for root's final operating-policy source boundary and
MCP's final additive audit-link source boundary, then root's review of this plan.
Flutter also waits for both agents to release their scoped test/capture jobs.
Ordinary concurrent work in the original checkout will be preserved and reported.

Fresh isolated destinations:

- Source: `/Volumes/PRO-G40/Projects/Collect-Release-Candidates/collect-local-20261001-source-06`
- Derived build: `/Volumes/PRO-G40/Projects/Collect-Release-Candidates/collect-local-20261001-admin-build-06`
- Evidence: this `checkpoint06` directory; earlier source/build/packet directories stay intact.

## Read-only prerequisites observed

On 2026-10-01 00:57:06 UTC the installed pin matched Flutter **3.44.4**, Dart
**3.12.2**, framework `ad70ec4617166f1c38e5d2bfd388af71fda14f06`, Node **v24.19.0**.
The six required locks and 21 critical pin/dependency/native input paths were
readable. There were 175 unique valid migration versions; that is a dated source
inventory, not migration-chain acceptance. The existing offline package cache
exists. Both intended destinations were absent. PRO-G40 had about 229 GiB free.
These observations are provisional; the actual export's bound inventory/pins
and pre/post checks determine this checkpoint's inputs.

The actual owner-private four-input public configuration file is
`/Users/jeanbosco/.cache/collect-release-config/admin-checkpoint04-public-defines.json`.
Its SHA256 remains
`78c61fceea0b72981fada0d50af45aeba9d2955e92159927e819b70fd31f9206`;
file mode0600, owned immediate parent mode0700, size203 bytes. The existing
validator passed exact-key/schema/project/public-key-form checks without
printing values. It supplies only `SUPABASE_URL`, `SUPABASE_ANON_KEY`,
`ENABLE_ADMIN_PANEL` and `APP_ENVIRONMENT`; no operator, service-role, Auth
session or provider credential is permitted. No remote authentication was
checked. The prior dated public-auth observation reported email disabled;
configured compilation will not attest current hosted authentication settings.

Tool bytes match the prior runner provenance:

- Exporter `scripts/qa/collect_release_candidate.py`: `2974757b1916a9cf7c2687e6568de645e339e4444a4ee8c4dd4abe48ad86d356`
- Exact-copy helper `prepare_admin_workcopy.py`: `a449e94d1703fc64af4f5d0f2347c7847746cc67266597634aefc84e5aab33e2`
- Configured runner `run_admin_checkpoint.py`: `5eb16c1aee77716db750691c0320d5725da988cf1005db3389e169b45350bb95`

Retain these actual tool bytes and hashes separately, verify them before and
after execution, and use `PYTHONDONTWRITEBYTECODE=1` so helper imports do not add
cache files inside the pristine candidate. A changed reviewed tool/pin is a
reported blocker; this task will not modify shared source to make export pass.

## Commands after the stable/reviewed plan signal

From the current checkout, use the explicit existing non-atomic checkpoint
mode. It captures each screened stable file read once, preserves modes, reads
the exact copied bytes back, and records later selected/excluded/indexed-absence
drift by path with prior/current hashes. It still refuses critical pins or
toolchain drift, invalid/duplicate migrations, symlinks and screened credentials.

```sh
PYTHONDONTWRITEBYTECODE=1 python3 scripts/qa/collect_release_candidate.py export \
  --destination /Volumes/PRO-G40/Projects/Collect-Release-Candidates/collect-local-20261001-source-06 \
  --retain-source-drift \
  --report docs/release/collect-codex-goal-2026-09-30/release-tooling/checkpoint06/source-export.json
```

Read `manifest_sha256` from the actual export receipt and keep it as an external
binding, represented below as `$COLLECT06_MANIFEST`. Verify exact source
readback without substituting current original-tree bytes:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 scripts/qa/collect_release_candidate.py verify \
  --candidate /Volumes/PRO-G40/Projects/Collect-Release-Candidates/collect-local-20261001-source-06 \
  --expected-manifest-sha256 "$COLLECT06_MANIFEST" \
  --report docs/release/collect-codex-goal-2026-09-30/release-tooling/checkpoint06/source-readback.json

PYTHONDONTWRITEBYTECODE=1 python3 docs/release/collect-codex-goal-2026-09-30/release-tooling/prepare_admin_workcopy.py \
  --root /Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL \
  --candidate /Volumes/PRO-G40/Projects/Collect-Release-Candidates/collect-local-20261001-source-06 \
  --workspace /Volumes/PRO-G40/Projects/Collect-Release-Candidates/collect-local-20261001-admin-build-06 \
  --manifest-sha256 "$COLLECT06_MANIFEST" \
  --report docs/release/collect-codex-goal-2026-09-30/release-tooling/checkpoint06/workcopy-prepare.json
```

After Flutter is released, compile only from that derived work copy using the
governed configured mode. The runner performs `pub get --offline
--enforce-lockfile` with a240-second deadline, binds the app/three local forks
inside the derived copy and all other package roots to the existing cache or
pinned SDK, then performs a600-second bounded `build web --release --no-pub
--no-wasm-dry-run --target lib/main_admin.dart` with the verified staged public
define file. No synthetic evidence-mode define is supplied.

```sh
PYTHONDONTWRITEBYTECODE=1 python3 docs/release/collect-codex-goal-2026-09-30/release-tooling/run_admin_checkpoint.py configured \
  --candidate /Volumes/PRO-G40/Projects/Collect-Release-Candidates/collect-local-20261001-source-06 \
  --workspace /Volumes/PRO-G40/Projects/Collect-Release-Candidates/collect-local-20261001-admin-build-06 \
  --manifest-sha256 "$COLLECT06_MANIFEST" \
  --packet docs/release/collect-codex-goal-2026-09-30/release-tooling/checkpoint06 \
  --label admin06 \
  --cache /Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL/.cache/pub-cache-hygiene-20260930 \
  --defines-file /Users/jeanbosco/.cache/collect-release-config/admin-checkpoint04-public-defines.json \
  --defines-sha256 78c61fceea0b72981fada0d50af45aeba9d2955e92159927e819b70fd31f9206
```

The runner records actual exit/time/log/runner/exporter hashes, source/lock and
public-file readback, dependency-root binding, all artifact hashes, the artifact
manifest hash and final pristine source readback. Public-key occurrences are
redacted before writing or printing compiler logs. Retain failures/timeouts as
separate evidence; do not broaden deadlines or change product source to obtain
a pass. A usable exact checkpoint with ordinary source drift may be compiled
while reporting its dated differences; a partial or pin-invalid export is not
promoted into a valid checkpoint.

## Binding and limits

After capture, bind actual included Admin entrypoint/router/shell, email and
approval, receipt Overview/lifecycle/investigation, gateway/recovery, exceptions
v2, cancellation, joined audit/additive links, shadow history and operating-policy
files to their exact source-table entries. Report actual migration inventory and
all capture/later source drift; intended features are not inferred from filenames
or prior source05 results. Perform a later original-tree comparison as a dated
delta only. Keep source snapshot pristine; no generated config/cache/build file
is added there.

All trust/review/frozen/owner/signed/release approvals and current-tree acceptance
remain **false**, even if readback and compilation pass. Prior source05 and its
155-artifact configured bundle remain historical. This checkpoint will not run
MCP host discovery, access personal profiles or Keychain, request OTP/Auth,
provision accounts, execute backend business actions, send SMS, deploy, sign,
publish or claim hosted/browser/device/delivery/production acceptance.
