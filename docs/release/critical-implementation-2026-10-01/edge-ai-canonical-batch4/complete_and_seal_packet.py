"""Seal only this completed private execution and its immutable observations."""
from pathlib import Path
import datetime as dt
import importlib.util
import json
import shlex
import tomllib

E = Path(__file__).absolute().parent
ROOT = E.parents[3]
spec = importlib.util.spec_from_file_location("final_packet_helpers", E / "seal_completed_evidence.py")
helpers = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helpers)
observe, copy, save = helpers.observe, helpers.copy, helpers.save


def main():
    result = json.loads((E / "execution-result.json").read_text())
    freeze = json.loads((E / "private-source-freeze.json").read_text())
    phases = json.loads((E / "phase-summary.json").read_text())
    final = json.loads((E / "final-source-input-readback.json").read_text())
    copy_rows = json.loads((E / "canonical-output-copy.json").read_text())
    cleanup = json.loads((E / "owned-cleanup-readback.json").read_text())
    admission = ROOT / "docs/release/critical-implementation-2026-10-01/root-current-integration-batch4/edge-inputs4-admission.json"
    assert observe(admission)["sha256"] == "8aafe8c62eef3ac0318c1c1451bb134fd0a8f787de69c8a2a4d36eca1306a498"
    assert result["status"] == phases["status"] == "pass" and result["exit_code"] == 0
    assert result["private_source_unchanged"] and cleanup["scoped_cleanup_pass"]
    assert "Ran 77 tests" in (E / "canonical/runner_contract.stderr").read_text()
    candidate = Path(freeze["private_candidate"])
    assert helpers.inventory(candidate) == final["accepted_private_manifest"]
    assert helpers.inventory(ROOT) == final["current_after"]
    dated_manifest = Path(freeze["auxiliary_dated12_manifest"]["copy"])
    current_manifest = ROOT / "contracts/edge-functions.json"
    manifests = [copy(dated_manifest, E / "endpoint-inventory/datetime-bound12-edge-functions.json"),
                 copy(current_manifest, E / "endpoint-inventory/current13-edge-functions.json")]
    private_cfg = tomllib.loads((candidate / "supabase/config.toml").read_text())
    current_cfg = tomllib.loads((ROOT / "supabase/config.toml").read_text())
    assert len(private_cfg["functions"]) == 12 and len(current_cfg["functions"]) == 13
    assert len(json.loads(dated_manifest.read_text())["functions"]) == 12
    assert len(json.loads(current_manifest.read_text())["functions"]) == 13
    save("endpoint-inventory-observation.json", {"observed_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
         "physical_manifest_copies": manifests, "private_source_count": 140,
         "private_config_sha256": observe(candidate / "supabase/config.toml")["sha256"],
         "private_dated_endpoints": sorted(private_cfg["functions"]), "private_runtime_loader_count": 12,
         "current_source_count": 144, "current_config_sha256": observe(ROOT / "supabase/config.toml")["sha256"],
         "current_intended_endpoints": sorted(current_cfg["functions"]), "current_typed_manifest_count": 13,
         "current_added_source_paths": sorted(final["current_added"]),
         "current_changed_source_paths": sorted(final["current_changed"]),
         "current_intended_gateway_execution_claimed": False, "hosted_active_endpoint_inventory_verified": False,
         "current_checkout_whole_acceptance": False})
    scope = json.loads((E / "permissions-and-local-scope.json").read_text())
    provenance = json.loads((E / "fixture-provenance.json").read_text())
    command_text = shlex.join(result["command"])
    readme = f"""# Full private AI canonical acceptance — 2026-10-02

The sole authorized full invocation **passed** in **{result['elapsed_seconds']:.12f} seconds**, from `{result['started_at_utc']}` to `{result['finished_at_utc']}`. Actual completed coverage was **77 maintained contracts, all86 types,32 unit files /643 tests /32 steps,103 actual loopback HTTP checks,32 Linux decoder cases,14 signed Linux HTTP tests,212 decoder regressions and6 same-image security tests**. No unit, step, signed integration or regression was failed or ignored; no security case was failed or skipped. The actual212 regression count supersedes the preparation estimate159. `phase-summary.json` and copied original phase logs/results bind these observations.

This is acceptance of the exact **frozen140 source cohort** composed from the previously reviewed137 plus the seven approved AI source changes and corrected synthetic HTTP fixture SHA `27fcd434f5a4c5c30d298c1df2e1e059c22e206e82ec42e6a84523f9c12293c9`. The private inventory equals its frozen before/copy/after whole SHA, size, mode and distinct physical-copy identities. All original91 HTTP labels/order and12 appended approval denials passed; there were14 closed owned listeners and three blocked Meta host attempts. Provider credentials remain absent and the synthetic approval tuple is distinct from the actual Linux build identity. No provider delivery or production policy tuple is claimed.

The changed-input preparation4 genuinely copied **all13 offline CLI input files**: six Linux/aarch64/Python3.12 wheels totaling9,936,126 bytes, six complete primary metadata bodies, and the separately bound4004-byte publisher receipt SHA `58ba030a43beab73906753486051c6a3499a00a70bfa1c9e018a0fb4554cfa74`. All are regular, readonly0444, single-link physical copies, with exact whole-byte/hash/identity bindings. Root independently admitted the entire actual argument/input matrix before this invocation (receiptSHA `8aafe8c62eef3ac0318c1c1451bb134fd0a8f787de69c8a2a4d36eca1306a498`). Sealed preparation4 was not modified; the complete earlier failed181/400/402 and original passed519 packets remain unchanged. Earlier AI publisher-copy overstatements and the actual missing-path failure remain truthfully recorded in failed batch3; this new input set does not repair or relabel that historical failure.

The run started with **zero Deno cache files** and ended **{final['cache_final_count']} files /{final['cache_final_bytes']:,} bytes**. Deno2.5.6 executable SHA is `a371e0605be5039a91a079a802d66b22c124a42e31573e43136c93c2b362f1c0`. Type/cache commands use the frozen graph and do not execute application runtime; Deno2.5.6 check has no cached-only option. Test/run commands use cached-only/no-prompt and exact loopback-scoped permissions. The original1200-second whole,300-second build and600-second Linux deadlines were preserved. No canonical retry, assertion omission, broader permission or maintained source write occurred.

The actual verifier prepared a **fresh physical17-input context/publisher closure** and performed the maintained `docker build --network=none --no-cache` recipe, with Dockerfile RUN network-none and pip no-index/require-hashes/only-binary. `canonical/linux-decoder/build.log` records a real new offline six-package installation and new image `{phases['fresh_image_id']}` tagged `{phases['fresh_image_tag']}`. The immutable base digest was already locally available, and Docker reports the neutral WORKDIR step cached; there is no claim that the base was freshly acquired. No earlier decoder image or installation result substitutes for this new build. Actual same-image runtime reports Linuxaarch64/Python3.12.14 and Pillow12.3.0, pypdf6.19.0, pypdfium2 5.2.0, openpyxl3.1.5, defusedxml0.7.1 and et-xmlfile2.0.0. Actual decoder build fingerprint is `{phases['decoder_build_sha256']}`.

Security tests used a network-none, readonly, capability-dropped resource-bounded container. Signed HTTP used an isolated Docker bridge with a listener published only on127.0.0.1 and a synthetic random secret; this supervisor was not network-none. Permission/source/assertion records and blocked provider attempts support the scoped network evidence, with no packet capture or independent observation of every packet. The12-file immutable worker manifest SHA `{provenance['immutable_worker_manifest_sha256']}` validates the actual earlier origin helper/runner/migration binding and terminal receipt. Actual generated35 Linux synthetic fixture files and manifest SHA `{provenance['generated_linux_manifest_sha256']}` are bound to the current copied generator and version metadata. Current SQL was not executed.

All **{copy_rows['count']} canonical output files /{copy_rows['bytes']:,} bytes** were physically copied with full before/copy/after hashes, sizes, modes and distinct identities. Independent Docker diagnostics identify both exact task containers as absent, a successful new-image ancestor query returns zero containers, and a birth-matched process readback finds no live owned process. The new local image and private cache remain available for evidence; no global daemon cleanup is claimed. Two evidence-only sealer failures are retained: a dictionary-schema comparison mismatch, followed by a classifier that expected No such object while Docker returned the exact No such container diagnostic. Corrected read-only checks reuse the identical completed outputs; **the full gate was invoked once**.

The current shared dynamic graph is **144**, with four gateway source additions and a separate config delta. Current repository source/config/typed manifest represent13 intended endpoints; this accepted private source/config/literal loader and auxiliary manifest remain the dated12-endpoint graph. `endpoint-inventory-observation.json` binds both manifests and keeps hosted-active inventory unverified. No maintained old12 inventory was restored. Current13 whole-source, current SQL, hosted Auth/RLS, provider delivery, deployment, device/store or whole-production acceptance is not implied. The existing default QA formatter failure remains disclosed and unwaived; this packet claims no formatter pass. Original successful519 and all dated failures remain immutable.

The exact outer command below was run once with the private source as working directory and the fresh owned DENO_DIR recorded in `private-source-freeze.json`. This is command provenance, not an instruction to rerun:

```text
{command_text}
```

The unchanged full execution driver is `run_private_canonical.py` (SHA011e3d8ff57d96b519075343723bdb524f46cbc2e09d76f5965fb0a26e4a8e2e). `execution-result.json` retains exact argv, tool identities, process deadlines and terminal outcomes. `batch.json` binds every artifact except itself and the outer checksum; `SHA256SUMS` covers every physical packet file except itself, including nested checksum files.
"""
    with (E / "README.md").open("x") as f:
        f.write(readme)
    assert not any(p.is_symlink() for p in E.rglob("*"))
    leaves = {str(p.relative_to(E)): observe(p) for p in sorted(E.rglob("*")) if p.is_file()}
    save("batch.json", {"sealed_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(), "status": "pass",
         "scope": "Frozen private140/datetime-bound12 endpoint; current144/13 and hosted/SQL production gates separate.",
         "canonical_invocations": 1, "maintained_source_mutations": 0, "elapsed_seconds": result["elapsed_seconds"],
         "actual_counts": {"contracts": 77, "types": 86, "unit_files": 32, "unit_tests": 643, "unit_steps": 32,
         "HTTP": 103, "Linux_cases": 32, "signed_Linux_HTTP": 14, "regressions": 212, "security": 6},
         "current_SQL_executed": False, "current_checkout_acceptance": False, "whole_production_acceptance": False,
         "owned_cleanup_pass": True, "original_failures_preserved": True, "artifact_count": len(leaves),
         "artifacts": leaves, "artifact_bytes": sum(v["bytes"] for v in leaves.values()),
         "outer_checksum_excludes_only_itself": True, "checksum_includes_nested_checksum_files": True})
    covered = sorted(p for p in E.rglob("*") if p.is_file())
    with (E / "SHA256SUMS").open("x") as f:
        for p in covered:
            f.write(observe(p)["sha256"] + "  " + str(p.relative_to(E)) + "\n")
    rows = [(sha, E / name) for sha, name in (line.split("  ", 1) for line in (E / "SHA256SUMS").read_text().splitlines())]
    assert len(rows) == len(covered) and {p for _, p in rows} == set(covered)
    assert all(observe(p)["sha256"] == sha for sha, p in rows)
    print(json.dumps({"status": "sealed", "artifact_leaves": len(leaves), "checksum_rows": len(rows),
          "actual_canonical_files": copy_rows["count"], "actual_canonical_bytes": copy_rows["bytes"],
          "batch_sha256": observe(E / "batch.json")["sha256"], "README_sha256": observe(E / "README.md")["sha256"],
          "checksum_sha256": observe(E / "SHA256SUMS")["sha256"]}, indent=2))


if __name__ == "__main__":
    main()
