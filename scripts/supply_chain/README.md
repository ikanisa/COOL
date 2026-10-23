# Dependency evidence

The observed Gradle exporter has an optional cached publisher-metadata mode.
Pass all of `--license-witnesses`, `--license-coordinate-join` and
`--artifact-graph-binding`, each with its corresponding `-sha256` argument,
alongside `--graph-evidence-root` and the exact `--license-declarations-root`.
The pinned join must cover every observed Maven coordinate exactly once and
bind the frozen baseline SBOM and raw witness file. Current artifact, graph and
declaration bytes must match their recorded hashes. Broader declaration-only
coordinates are not added to the observed graph.

Use fresh, separately named output and inventory paths. Without these optional
arguments, existing exporter bytes and behavior are unchanged. `--check` can
reproduce the additive outputs. The original graph-only SBOM and native build
receipt remain evidence in their own right.

Exact direct-POM witnesses change `collect:license-evidence` to
`cached_pom_license_metadata`; absent direct declarations remain `unknown` with
an explicit witness status. Publisher words and POM hashes are retained in
custom properties. These are cached metadata observations, with no SPDX
inference, new permission requirement, redistribution approval, actual artifact
notice verification, final R8 membership or advisory clearance. Dart text and
SDK/fork provenance retain their separate evidence scopes.
The consumer verifies the frozen witness file and emits its recorded POM hashes;
it does not recollect POM files or refresh the publisher metadata snapshot.

The source inventory, observed Gradle graph, archive reader, local licence
witnesses and advisory readback each cover a different part of release review.
Keep their exact inputs and exclusions with the result.

`osv_package_readback.py` queries public Maven identities from an observed
CycloneDX SBOM, public pub.dev lock entries and public npm tooling lock entries.
Pass explicit `--android-sbom`, `--pub-lock`, `--npm-lock` and a new
`--output-directory`, plus `--query-public-packages`. Only package names and
versions are transmitted to the [OSV batch API](https://google.github.io/osv.dev/post-v1-querybatch/).
It retains bounded request/response pages and checks input hashes afterward.

Local projects, forks, SDK packages and private package hosts stay explicit
exclusions. A completed query with no matches does not establish package safety,
runtime exploitability, licence approval, complete toolchain coverage or signed
artifact acceptance. Preserve the observation date and refresh when its inputs
or the release decision change. Run the deterministic transport/inventory
regressions with `python3 -m unittest discover -s scripts/tests -p osv_package_readback_test.py`.
