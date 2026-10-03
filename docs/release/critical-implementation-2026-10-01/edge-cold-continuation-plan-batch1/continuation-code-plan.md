# Proposed canonical acquisition correction — not executed

The present blocker is the Docker dependency acquisition operation, not a failing decoder assertion. All six exact current Linux wheels already exist and match retained authenticated publisher metadata and the current hash lock. The minimal next execution should consume a NEW private exact-six copy of those bytes and run the real maintained canonical recipe. It should not repeat the same URL download or reuse a completed decoder image as if freshly built.

Current `tools/roster-decoder/Dockerfile` always runs online pip. `verify_roster_decoder.py` directly builds that source context and has no wheelhouse argument; `run_edge_ci.py` has no corresponding forwarding argument. Shell `PIP_*` environment injection or an unreferenced build argument would not make that Docker RUN consume a host directory. A transparent source-supported correction is necessary; no source was changed in this plan.

Proposed future ownership is confined to a maintained wheelhouse preparation/validation helper and its negative tests, the decoder Dockerfile, `verify_roster_decoder.py`, the canonical caller/contract tests, and separately root-owned CI invocation if needed. No human-owned Admin file, requirement pin, decoder/parser logic, Deno permission, assertion, test inventory or command deadline should change.

The maintained preparator should accept an explicit source wheel directory, the current six-package lock, explicit authenticated release metadata/provenance inputs, and a nonexistent owned output directory. For this local continuation it needs no acquisition: the existing Linux wheel files can be re-read and physically copied into a fresh 0700 directory. It must select only the six Linux/universal production filenames, never the two Mac-native fixture wheels that share the old eight-wheel cache. Validate whole digest/size, exact package/version/ABI, regular files, no symlink ancestor/leaf, no hardlink or traversal, no duplicate/extra/missing wheel or identity, and before/copy/after hashes. Preserve publisher receipt hashes and actual copied-wheel manifest in the new cohort; do not make maintained source depend on a dated release archive. Missing bytes deny rather than fall back to an index, source distribution or old image.

Suggested helper interface:

```python
prepare_verified_wheelhouse(
    source_directory,
    requirements_lock,
    pinned_publisher_receipt,
    pinned_release_metadata,
    fresh_destination,
)
# Returns exact copied wheel/source/provenance identities and total bytes.
# No package install, engine/provider calls, global cache mutation or implicit retry.
```

The verifier should create a NEW physically private build context under its existing fresh output, copying the reviewed current `Dockerfile`, `requirements.lock`, `decoder.py` and `server.py` unchanged, plus the validated six-wheel directory. The proposed reviewed Dockerfile dependency instruction is:

```dockerfile
RUN --network=none --mount=type=bind,source=wheelhouse,target=/wheelhouse,ro \
    python -m pip install --no-cache-dir --disable-pip-version-check \
    --no-index --find-links=/wheelhouse --only-binary=:all: \
    --require-hashes -r requirements.lock
```

This source change must be real and included in the new source/build identity; do not secretly rewrite a Dockerfile in a dated stage, retain an old recipe hash, prime an opaque layer cache, or monkeypatch the maintained build command. The current pinned base digest remains the input. Local metadata confirms its ARM64 layers are available; a fresh build still has to prove actual availability and installed bytes. Keep the actual build at 300 seconds and the enclosing Linux phase at 600 seconds. Prefer an owned fresh build with application layers not reused so offline installation actually runs; do not erase a shared daemon's cache. Record actual build recipe/context/base/image identities and before/copy/after source hashes. A whole missing base or unsupported BuildKit frontend is a genuine new prerequisite failure, not permission to widen network/deadline policy.

`verify_roster_decoder.py` should gain an explicit validated wheelhouse input and report its identity; the canonical caller should pass that input. Both source inventories must explicitly include any new maintained helper/recipe/tests. The receipt/build fingerprint must include the real newly reviewed Dockerfile and all exact input bytes. Runtime source and receipt assertions continue to use that actual identity. Candidate source count is observed, not forced to the dated 135 count. The one observed drift now is root-owned `.github/workflows/ci.yml`; current source must be copied/frozen again before a new full acceptance.

On a future clean hosted ARM64 job, preparation is a separate bounded public publisher stage. The existing fixture-venv online pip step also needs the same authenticated prepared wheels before offline hash installation. Root must review that integration separately; this local plan neither changes CI nor claims hosted transport. No fresh public acquisition is needed for the proposed local continuation. If a future cache is missing bytes, retain a distinct preparation failure; do not blindly retry the identical stalled request or enlarge its deadline.

Preserve all current canonical phases: real frozen cache population, 83 observed types, all 31 unit files/563 observed tests/32 steps with zero ignored, 91 real HTTP checks, actual Linux 32 corpus/protocol cases, all 14 HTTP-to-decoder integration tests, all 157 regressions and the six focused dependency-security cases on the same newly built image. The numbers describe current unchanged observed inventories; genuinely added tests must increase the observed count, and none may be dropped to force a match. Keep all four pinned frozen/cached Deno commands and actual lock enforcement. A meaningful corrupt-lock denial should use only a fresh private copy and the exact runtime; preserve both the real lock and its prior denied evidence. No test fake, expected-count-only receipt or missing/failed/ignored summary can pass.

Networking is scoped precisely: dependency installation and security case containers run network-none; parser isolation probes retain actual socket denial; HTTP supervisor retains its existing read-only/cap-drop/resource bounds and loopback-published endpoint; Deno runtime tests retain only the established loopback permissions and synthetic credentials. Applying network-none to the HTTP supervisor would break the real 14 HTTP cases, so do not alter that architecture or replace them with mock requests. Provider/customer/hosted operations remain forbidden. Retain all original timeout logs and cleanup/reaping evidence.

Needed tests for the acquisition correction are actual filesystem/byte negatives (missing/tampered/misdirected/extra/Mac wheel, wrong lock/metadata, drift during copy) and a real network-none missing/corrupted-wheel build denial, followed by the complete canonical healthy recipe. All code mutation, wheel copying, building and tests in this section are proposals awaiting root's scoped implementation handoff; none occurred in this investigation.

The proposed local flags follow [pip's official offline/local-wheel installation options](https://pip.pypa.io/en/stable/cli/pip_install/) and [Docker's official read-only bind-mount and network-none instruction contracts](https://docs.docker.com/reference/dockerfile/). This is a dependency acquisition correction, not evidence that Docker/PyPI transport has been repaired or that deployment is approved.
