"""Prepare sole typed-map correction and independent prior140/cache copies."""
from pathlib import Path
import datetime as dt
import difflib
import importlib.util
import json
import os
import subprocess
import sys

E = Path(__file__).absolute().parent
ROOT = E.parents[3]
FAILED = E.parent / "edge-ai-canonical-batch2"
spec = importlib.util.spec_from_file_location("prior_copy_helpers", FAILED / "prepare_private_cohort.py")
helpers = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helpers)
observe, copy = helpers.observe, helpers.copy
COHORT = Path("/Volumes/PRO-G40/Development/Codex-Candidates/COOL-EDGE-AI-HTTP-TYPE-PREPARATION2")
QA = "scripts/qa/edge_http_runtime_uat.ts"


def save(name, data):
    with (E / name).open("x") as f:
        f.write(json.dumps(data, indent=2) + "\n")


def main():
    failed_before = helpers.packet(FAILED)
    assert failed_before["seals"]["batch.json"]["sha256"] == "98fc0cb31a6f9509ecd026560b5842bb0371c9d3107aca222cb518f3ddc7f4b7"
    freeze = json.loads((FAILED / "private-source-freeze.json").read_text())
    baseline = Path(freeze["private_candidate"])
    cache = Path(freeze["deno_cache"])
    sources_before = {r["path"]: observe(baseline / r["path"]) for r in freeze["source_manifest"]}
    assert len(sources_before) == 140 and all(sources_before[r["path"]]["sha256"] == r["sha256"]
            and sources_before[r["path"]]["mode"] == r["copy_mode"] for r in freeze["source_manifest"])
    cache_before = {str(p.relative_to(cache)): observe(p) for p in sorted(cache.rglob("*")) if p.is_file()}
    assert not any(p.is_symlink() for p in cache.rglob("*")) and len(cache_before) == 356
    assert observe(ROOT / QA)["sha256"] == sources_before[QA]["sha256"] == "1896e5b1fe1d21a9f0a883ad2222a7fdf5d0594b90bb0edd3c064c7fc32921c7"
    COHORT.mkdir(mode=0o700)
    source, copied_cache = COHORT / "source", COHORT / "deno-cache"
    source.mkdir(mode=0o700); copied_cache.mkdir(mode=0o700)
    source_copies = [copy(baseline / n, source / n) for n in sorted(sources_before)]
    cache_copies = [copy(cache / n, copied_cache / n) for n in sorted(cache_before)]
    original = (baseline / QA).read_text()
    before = '    const negativeEnvironment = {\n'
    after = '    const negativeEnvironment: Record<string, string | undefined> = {\n'
    assert original.count(before) == 1
    candidate = original.replace(before, after)
    before = '      ...environmentPatch,\n    };\n    const before = providerAttempts.length;\n'
    after = ('    };\n'
             '    for (const [key, value] of Object.entries(environmentPatch)) {\n'
             '      negativeEnvironment[key] = value;\n'
             '    }\n'
             '    const before = providerAttempts.length;\n')
    assert candidate.count(before) == 1
    candidate = candidate.replace(before, after)
    (source / QA).write_text(candidate)  # Only a newly owned private copy.
    candidate_observation = observe(source / QA)
    target = E / "candidate" / QA
    copy(source / QA, target)
    copy(baseline / QA, E / "inputs" / QA)
    patch = ''.join(difflib.unified_diff(original.splitlines(True), candidate.splitlines(True),
                                        fromfile="a/" + QA, tofile="b/" + QA))
    with (E / "candidate.patch").open("x") as f:
        f.write(patch)
    legacy = (E.parent / "edge-ai-http-fixture-preparation1/inputs" / QA).read_text()
    begin = legacy.index('const report: Record<string, unknown>')
    tail = '  report.status = checks.every((r) => r.status === "pass") ? "pass" : "fail";\n'
    end = legacy.index(tail)
    assert legacy[begin:end] in candidate and legacy[end:] == candidate[candidate.index(tail):]
    categories_start = original.index('  // Appended after every original HTTP assertion')
    categories_end = original.index('    const negativeEnvironment = {')
    assert original[categories_start:categories_end] in candidate
    restoration_start = original.index('    const before = providerAttempts.length;\n', categories_end)
    assert original[restoration_start:] == candidate[candidate.index('    const before = providerAttempts.length;\n', categories_end):]
    actual_sources = {n: observe(source / n) for n in sources_before}
    assert all(all(actual_sources[n][k] == row[k] for k in ["sha256", "bytes", "mode"])
               for n, row in sources_before.items() if n != QA)
    command = json.loads((FAILED / "canonical/validation.json").read_text())["phases"]["types"]["command"]
    type_arguments = command[1:]
    assert len([a for a in type_arguments if a.endswith('.ts')]) == 86
    assert type_arguments[:3] == ['check', '--no-config', '--frozen']
    assert '--lock=supabase/functions/deno.lock' in type_arguments and '--cached-only' not in type_arguments
    assert sources_before == {n: observe(baseline / n) for n in sources_before}
    assert cache_before == {n: observe(cache / n) for n in cache_before}
    assert failed_before == helpers.packet(FAILED)
    save("private-type-source-freeze.json", {"prepared_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
         "status": "prepared_unexecuted", "candidate_source": str(source), "candidate_cache": str(copied_cache),
         "baseline_source": str(baseline), "baseline_cache": str(cache), "failed181_before_after": failed_before,
         "source140_before": sources_before, "source140_after_copy": actual_sources,
         "source140_copies": source_copies, "original_cache_before_after": cache_before, "cache356_copies": cache_copies,
         "initial_copied_cache_count": 356, "type_arguments": type_arguments, "types_in_full_closure": 86,
         "sole_changed_source": QA, "base_sha256": sources_before[QA]["sha256"],
         "candidate_sha256": candidate_observation["sha256"], "original91_assertions_order_tail_identical": True,
         "negative12_categories_values_assertions_restoration_identical": True,
         "maintained_source_mutations": 0, "canonical_invocations": 0, "runtime_tests_executed": False,
         "private_cache_is_verified_copied_prior_cache_not_cold_acceptance": True,
         "unchanged_default_format_failure_disclosed": True})
    print(json.dumps({"status": "private_type_candidate_prepared", "source_count": 140,
                      "copied_cache_count": 356, "types": 86, "candidate_sha256": candidate_observation["sha256"]}, indent=2))


if __name__ == "__main__":
    main()
