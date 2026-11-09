# Release evidence and packaging safeguards r4

**9 November 2026 · toolkit 4.0.0 · source-only engineering delivery**

r4 adds mandatory, externally pinned Ed25519 producer statements to application build and promotion gates. It retains r2/r3 source/evidence binding, exact packaging, credential scanning and legacy product requirements. A source-only tooling package is not an application release or independently authenticated qualification. No result from this toolkit grants production authority.

## Reproduce this delivery

Requirements: Python 3.11+, a POSIX environment, OpenSSL 3+ with Ed25519 support, and Git for optional patch verification. No third-party Python package installation is needed. OpenSSL is a real external runtime dependency, not a Python package. Missing prerequisites must leave the gate blocked.

From this `source/` directory, use new output paths outside the source:

```sh
python3 -B run_checks.py --output ../fresh-r4-evidence \
  --archive ../Release_Safeguards_r4_Reproduced.zip
```

The command captures the exact scoped source inventory, executes the toolkit tests, records logs/counts/exit codes, checks that source was unchanged, and creates a source-only archive only after those checks pass. It never fabricates real product qualifications. The outer delivery's `evidence/` holds the fresh run that produced it; historical material under `docs/history/` is retained for audit and does not satisfy current gates.

Inspect an archive without executing any contained source, using a separately trusted copy of this validator:

```sh
python3 -B src/release_guard.py verify-package ../Release_Safeguards_r4_Reproduced.zip \
  --product release-safeguards --version 4.0.0 --sha256 EXPECTED_ARCHIVE_SHA256
```

Obtain the expected hash through your protected delivery channel. Integrity/freshness validation does not authenticate the channel that supplied the hash. After 24 hours, fresh-evidence verification deliberately rejects the historical archive; `audit-package` can still check immutable byte integrity and reference closure. Do not edit old timestamps to renew evidence.

## Delivered implementation

| File | Responsibility |
|---|---|
| `src/release_guard.py` | Actual source inventory; manifests/results/logs/artifacts/dependencies; freshness; strict fields; packaging; public release gate |
| `src/release_provenance.py` | Pinned external trust policy, Ed25519 signatures, scoped roles, distinct-producer thresholds, key revocation and validity |
| `src/provenance_exchange.py` | Unsigned payload export and validated intake of externally generated signatures; never signs or opens a gate |
| `src/release_guard_adapter.py` | Product identity and legacy artifact binding; protected trust configuration supplied to the public gate |
| `src/triage_credentials.py` | Read-only, value-free finding locations; never an exception/allowlist mechanism |
| `integration/` | Complete overlays, preimage-checked installer, original/r2/r3 patches and reproducible baseline/upgrade verification tools |
| `tools/runtime_inventory.py` | Observed Python/OpenSSL executable hashes and versions; not a complete system SBOM |
| `tests/` | 307 tests in the delivered run, including 93 new r4 tests; synthetic qualifications and temporary signing identities only |

## Install against the tested inputs

Pinned full application input archives remain separate on Drive. Their names, hashes and original IDs are in `integration/merge-ledger.json`. The current delivery contains every new or changed safeguard source file, not a full-app archive. Full-app packaging remains blocked by 33 unresolved credential-like files.

```sh
python3 -B integration/apply_overlay.py --product M-Money \
  --source /work/original-mm --output /work/mm-with-r4
python3 -B integration/apply_overlay.py --product BuriMunsi \
  --source /work/original-bm --output /work/bm-with-r4
```

For a checkout already carrying r2 or r3, add `--baseline r2` or `--baseline r3` and use a new output checkout. The installer checks all changed-path preimages before writing; conflicts require a deliberate merge, not overwriting or disabling checks. Do not apply original-baseline patches to upgraded checkouts. Each product has `changes.patch`, `upgrade-from-r2.patch` and `upgrade-from-r3.patch`.

```sh
python3 -B integration/verify_baselines.py --mmoney /work/original-mm \
  --burimunsi /work/original-bm --output /work/new-baseline-evidence
python3 -B integration/verify_upgrades.py --mmoney /work/original-mm \
  --burimunsi /work/original-bm --r2-toolkit /work/r2/source \
  --r3-toolkit /work/r3/source --output /work/new-upgrade-evidence
```

Use independently hash-verified prior deliveries for the last command, which executes their installers in separate processes. It performs six patch checks and four equivalent-upgrade checks. These check exact archive baselines, not parallel A03/A04 consolidated candidates.

## Application provenance setup

Follow `docs/PROVENANCE_SETUP.md`. Protected CI supplies `RELEASE_TRUST_POLICY` (an absolute policy path outside the source and evidence trees) and `RELEASE_TRUST_SHA256` (an independently approved exact byte hash). Phase evidence contains `provenance.json` beside its release manifest. Neither setting is taken from candidate evidence. No working trust roots, private keys or real signatures are included here.

Build/promotion cannot pass with unsigned evidence, even when all consistency fields match. The internal `validate_consistency` function is a diagnostic for tests and signing preparation, **not a release authorization API**. Use the public validator and the combined product release CLI, which also retain original requirements. Source packaging deliberately remains non-authenticating, and always reports no production authorization.

## Verification and open requirements

The delivered run has 307 passing toolkit tests and 56 passing retained product tests: 363 total. Six missing-evidence command contracts correctly blocked. Ten upgrade/patch checks passed. Results and exact application source inventories are under `docs/verification/`; the outer fresh toolkit evidence binds these files too.

No native compilation, installed-device/carrier test, real PostgreSQL/ledger acceptance, live hosted workflow, production signing or independent security assessment was executed. No deployment, protected environment, real signer onboarding or online revocation service was configured. The current product inventories cover M-Money 0.2.10 Build Security r1 and BuriMunsi 0.19.0-canonical.1 plus this overlay, not the final A03/A04 merged candidates. See `docs/action-register.json` for separate source/local/external status.

M-Money's r3 packaging layout change remains: `source/`, `evidence/`, `PACKAGE-MANIFEST.json`. Older external archive consumers still require migration. Unsupported legacy `--staging`/`--date` options fail rather than silently changing package contents.

This is not independent security certification, legal/regulatory acceptance, or production authorization. The workstation-only efficient-codex path was not mounted and was not used.
