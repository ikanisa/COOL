# Canonical Edge CI repair

The Deno job now requires the same local acceptance entrypoint as development: a pinned `.dvmrc` binary, the frozen dependency lock, all Edge types, all unit files, actual Deno HTTP handlers, and the actual Linux decoder supervisor/sandbox. The fixture integrity tests also run in that entrypoint. The Linux decoder integration file is allocated to the configured Linux phase; ignored tests cannot satisfy either phase.

Run from the repository root with the exact Deno binary and a Python 3.12 venv containing the hash-locked decoder packages:

```sh
python3 scripts/qa/run_edge_ci.py --deno /absolute/path/to/deno \
  --decoder-python /absolute/path/to/venv/bin/python \
  --cache-dependencies --output .cache/NEW_EDGE_ACCEPTANCE
```

The output must be fresh. Docker must use a local Unix endpoint with a native Linux ARM64 daemon, and Ruby must be available for the existing concurrency harness syntax check. Execution receives synthetic inputs and a sanitized environment. Unit and HTTP network permissions allow only loopback. The Linux phase uses the selected Deno binary through an enforcing wrapper; all four existing Linux Deno commands use the same frozen lock. Deno 2.5.6 `check` and `cache` do not accept `--cached-only` or `--no-prompt`; type and dependency resolution use supported frozen-lock flags, while `test`/`run` add cached-only/no-prompt. No provider API is used during test execution.

CI uses `ubuntu-24.04-arm` because the decoder wheel hashes bind Linux ARM64 artifacts. It pins Deno via `.dvmrc`, Python 3.12.14, and the setup actions by commit. GitHub documents the native ARM64 label and exact-patch Python installation; the upstream version manifest was checked for the 3.12.14 Linux24.04 ARM64 artifact. [GitHub runner documentation](https://docs.github.com/en/actions/reference/runners/github-hosted-runners), [Python setup documentation](https://github.com/actions/setup-python/blob/main/docs/advanced-usage.md), [verified Python release](https://github.com/actions/python-versions/releases/tag/3.12.14-31661455385).

`worker-fixture-v1` is an immutable decoder contract copied from the completed October1 synthetic worker SQL packet. Its manifest fixes the three observed outputs, original result, generator sources and four additive migration snapshots. The runner pins that manifest SHA-256 and validates every file plus the original generator/migration bindings. The complete database prerequisites are represented by their original hashes, not retained in this small contract; the archived SQL scripts are provenance and are never executed by CI. The contract does not attest to current migration execution. A regenerated contract requires a new reviewed version and digest.

The recorded local run completed with stable hashes for 131 inputs: 80 TypeScript entrypoints checked; 29 unit files/554 tests/zero ignored; 90 actual Deno HTTP checks; 32 Linux decoder cases, 14 actual Edge-to-Linux integration tests and 155 roster regression tests. Ten fixture integrity/completion tests and 12 CI policy tests passed. `acceptance/validation.json` and the nested phase reports retain exact commands, hashes, outputs and source snapshots. `batch.json` states the precise scope.

GitHub execution of the exact workflow, current SQL acceptance, and hosted/provider/device/store/deployment evidence remain separate. This packet is local acceptance, not production release authorization.
