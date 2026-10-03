# Proposed CI integration — pending root review/application

This is a proposal for the existing `deno-check` job on `ubuntu-24.04-arm`, Python 3.12.14 and its retained 20-minute job deadline. The current CI installs fixture dependencies online and supplies none of the four new mandatory flags. It therefore needs the following explicit integration before the changed canonical caller can run there. No CI file was edited by this agent and no hosted run occurred.

After the existing pinned Python setup, perform the separate reviewed official acquisition in a physically fresh job-owned path. The lock hash comes from the trusted reviewed checkout, and the producer separately rechecks that lock and the authenticated TLS metadata/whole wheel bytes. It performs at most twelve requests: exact package/version PyPI JSON on `pypi.org` and the matching digest-selected wheel on `files.pythonhosted.org`. It follows no redirect and uses no proxy, cookie, authorization header or automatic retry. Actual outer process deadline is 300 seconds; per request metadata45/wheel60 and socket10 seconds. Partial files and fixed failure receipts remain available. All six wheels must pass before a publisher-input receipt is published. Fresh origin metadata can differ from dated observations; its full byte hash is frozen in the new receipt. This establishes captured publisher origin/byte identity, not advisory freedom or transport reliability.

```sh
set -euo pipefail
wheel_inputs="$GITHUB_WORKSPACE/.cache/edge-ci-publisher"
lock_pin="$(sha256sum tools/roster-decoder/requirements.lock | cut -d ' ' -f 1)"
python3 -B scripts/qa/roster_wheelhouse.py --acquire \
  --lock-file tools/roster-decoder/requirements.lock --lock-sha256 "$lock_pin" \
  --destination "$wheel_inputs"
python3 -m venv .cache/edge-ci-python
.cache/edge-ci-python/bin/python -m pip install --disable-pip-version-check \
  --no-index --find-links="$wheel_inputs/wheels" --only-binary=:all: \
  --require-hashes -r tools/roster-decoder/requirements.lock
```

The venv installs only from these verified wheels. It remains a synthetic fixture generator; it does not substitute for installing and testing the newly built Linux image. The producer's `publisher-inputs.json` must be passed with its whole-file hash from this successful trusted producer stage, alongside its exact metadata and wheel directories. The same checkout lock remains authoritative; no dated local receipt or developer path appears in maintained CI.

```sh
set -euo pipefail
wheel_inputs="$GITHUB_WORKSPACE/.cache/edge-ci-publisher"
publisher_pin="$(sha256sum "$wheel_inputs/publisher-inputs.json" | cut -d ' ' -f 1)"
python3 -B scripts/qa/run_edge_ci.py --deno "$(command -v deno)" \
  --decoder-python .cache/edge-ci-python/bin/python \
  --wheel-source "$wheel_inputs/wheels" \
  --publisher-receipt "$wheel_inputs/publisher-inputs.json" \
  --publisher-sha256 "$publisher_pin" \
  --metadata-directory "$wheel_inputs/primary" \
  --cache-dependencies --output .cache/edge-ci
```

Extend the existing `if: always()` artifact paths to include `.cache/edge-ci-publisher`, `.cache/edge-ci-publisher-supervision` and `.cache/edge-ci`, retaining the existing artifact action and retention. Do not upload the installed venv. A producer error terminates the job before fixture installation/canonical acceptance; a stale/copied publisher pin, missing wheel, incompatible ABI or changed copied source causes the maintained copier to reject before build.

The current canonical phase still runs the original five required phases, every discovered type/unit input, actual HTTP, all32 Linux decoder cases, all14 real synthetic HTTP integration cases, all157 regressions and all6 dependency-security cases. Missing, failed or ignored completions remain denied. The real Dockerfile mounts the exact private copied wheelhouse read-only and runs offline pip inside `RUN --network=none`; the actual Docker build requests `--network=none --no-cache`, using the retained pinned base and unchanged300-second deadline. The supervisor's localhost synthetic HTTP networking remains necessary; it is not replaced with a network-none runtime that would skip HTTP integration. Security runtime retains network-none and its existing limits.

No job/build/test deadline is expanded. The new acquisition step consumes the existing20-minute job budget, so elapsed transport/build behavior still needs actual hosted proof. A transport stall is recorded and stops the job; do not blindly retry an unchanged failed request. Root must reconcile/apply this proposal and freeze the current source graph before authorizing a fresh full canonical run. This packet proves code/contract/copier preparation only.
