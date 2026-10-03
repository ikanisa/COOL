#!/usr/bin/env python3
"""Read back the exact private source, old assertions and bounded proof outputs."""
import ast
import datetime as dt
import difflib
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import sys

sys.dont_write_bytecode = True

PACKET = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("prepared_source", PACKET / "prepare_source.py")
prepared = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prepared)
ROOT = prepared.ROOT

def sha(raw):
    return hashlib.sha256(raw).hexdigest()

def dump(name, value):
    prepared.dump(PACKET / name, value)

def py_cases(source):
    return {node.name: ast.get_source_segment(source, node)
            for node in ast.walk(ast.parse(source))
            if isinstance(node, ast.FunctionDef) and node.name.startswith("test_")}

def ruby_cases(source):
    return {match.group(1): match.group(0)
            for match in re.finditer(r"^  def (test_[^\n]+)\n.*?^  end", source, re.M | re.S)}

def main():
    baseline, candidate = PACKET / "baseline/source", PACKET / "candidate/source"
    inputs = json.loads((PACKET / "source-before.json").read_text())
    current, staged, baseline_after, drift = {}, {}, {}, {}
    for name, before in inputs.items():
        raw, facts = prepared.read(baseline / name)
        assert all(facts[k] == before[k] for k in ("sha256", "bytes", "mode")), name
        baseline_after[name] = facts
        _, staged[name] = prepared.read(candidate / name)
        _, current[name] = prepared.read(ROOT / name)
        if current[name] != before:
            drift[name] = {"before": before, "after": current[name]}
    changes = {name: {"before": inputs[name], "candidate": staged[name]}
               for name in inputs if inputs[name]["sha256"] != staged[name]["sha256"]}
    expected_changes = {
        "contracts/edge-functions.json", "scripts/edge_function_inventory.rb",
        "scripts/tests/edge_function_inventory_test.rb",
        "scripts/supabase_production_readiness.sh",
        "scripts/tests/supabase_delivery_contract_test.py",
    }
    assert set(changes) == expected_changes, set(changes)
    assert not (set(drift) & expected_changes), "consumer source drift requires new review"
    forbidden = "scripts/qa/edge_http_runtime_uat.ts"
    assert (baseline / forbidden).read_bytes() == (candidate / forbidden).read_bytes()
    # Do not conflate an old copied closure with the latest maintained cohort.
    dump("source-after-tests.json", current)
    dump("baseline-after-tests.json", baseline_after)
    dump("candidate-source.json", staged)
    dump("maintained-source-drift.json", {"drift": drift, "stable_consumers": sorted(expected_changes),
                                           "whole_copied_closure_stable": not drift})
    patch = ""
    for name in sorted(changes):
        old, new = (baseline / name).read_text(), (candidate / name).read_text()
        patch += f"diff --git a/{name} b/{name}\n"
        patch += "".join(difflib.unified_diff(old.splitlines(keepends=True), new.splitlines(keepends=True),
                                            fromfile="a/" + name, tofile="b/" + name))
    (PACKET / "full-candidate.patch").write_text(patch)
    manifest_old = json.loads((baseline / "contracts/edge-functions.json").read_text())
    manifest_new = json.loads((candidate / "contracts/edge-functions.json").read_text())
    successor = "collect-receipt-successor-gateway"
    assert manifest_old["functions"] == [entry for entry in manifest_new["functions"] if entry["name"] != successor]
    assert manifest_old["retired"] == manifest_new["retired"]
    assert manifest_old["schema_version"] == manifest_new["schema_version"]
    assert manifest_new["functions"] and len(manifest_new["functions"]) == 13

    name = "scripts/tests/supabase_delivery_contract_test.py"
    old, new = (baseline / name).read_text(), (candidate / name).read_text()
    py_old, py_new = py_cases(old), py_cases(new)
    renamed = {
        "test_all_twelve_deploy_with_manifest_auth_modes_and_strict_readiness": "test_all_thirteen_deploy_with_manifest_auth_modes_and_strict_readiness",
        "test_unsigned_probes_cover_twelve_endpoints_and_use_no_hook_secret": "test_unsigned_probes_cover_thirteen_endpoints_and_use_no_hook_secret",
    }
    py_proof = {}
    for before, body in py_old.items():
        after = renamed.get(before, before)
        actual = py_new[after]
        restored = actual
        if before in renamed:
            restored = restored.replace(after, before)
            if before.startswith("test_all_twelve"):
                restored = restored.replace("self.assertEqual(len(deployments), 13)", "self.assertEqual(len(deployments), 12)")
                inserted = '\n'.join([
                    '        successor = "collect-receipt-successor-gateway"',
                    '        self.assertFalse(modes[successor])',
                    '        self.assertFalse(self.receipt()["readback"]["functions"]["observed_auth_modes"][successor])',
                ]) + '\n'
            else:
                restored = restored.replace("self.assertEqual(len(calls), 13)", "self.assertEqual(len(calls), 12)")
                inserted = '\n'.join([
                    '        expected = {entry["name"] for entry in json.loads((self.root / "contracts/edge-functions.json").read_text())["functions"]}',
                    '        observed = [next(arg.rsplit("/", 1)[-1] for arg in call if "/functions/v1/" in arg) for call in calls]',
                    '        self.assertEqual(set(observed), expected)',
                    '        self.assertEqual(len(set(observed)), len(observed))',
                ]) + '\n'
            assert inserted in restored, before
            restored = restored.replace(inserted, "", 1)
        assert restored == body, before
        py_proof[before] = {"current_name": after, "old_assertions_preserved": True,
                            "only_reviewed_count_update_and_additional_assertions": before in renamed,
                            "old_case_sha256": sha(body.encode()), "new_case_sha256": sha(actual.encode())}
    assert len(py_old) == 30 and len(py_new) == 34
    old_curl = ast.literal_eval(next(node.value for node in ast.parse(old).body if isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id == "MOCK_CURL" for t in node.targets)))
    new_curl = ast.literal_eval(next(node.value for node in ast.parse(new).body if isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id == "MOCK_CURL" for t in node.targets)))
    assert new_curl.replace('    "collect-receipt-successor-gateway": (400, "GATEWAY_REQUEST_INVALID"),\n', '', 1) == old_curl
    name = "scripts/tests/edge_function_inventory_test.rb"
    old_cases = ruby_cases((baseline / name).read_text())
    new_cases = ruby_cases((candidate / name).read_text())
    ruby_proof = {}
    for before, body in old_cases.items():
        after = before.replace('all_twelve_and_seven', 'all_thirteen_and_eight')
        actual = new_cases[after]
        restored = actual.replace(after, before)
        if before != after:
            restored = restored.replace("assert_equal 13,", "assert_equal 12,").replace("assert_equal 8, custom.length", "assert_equal 7, custom.length")
            inserted = '\n'.join([
                "    actual = Dir[File.join(@root, 'supabase/functions/*/index.ts')].map { |path| File.basename(File.dirname(path)) }.sort",
                "    assert_equal actual, @manifest.fetch('functions').map { |entry| entry.fetch('name') }.sort",
            ]) + '\n'
            assert inserted in restored
            restored = restored.replace(inserted, '', 1)
        assert restored == body, before
        ruby_proof[before] = {"current_name": after, "old_assertions_preserved": True,
                              "only_reviewed_count_update_and_additional_assertions": before != after,
                              "old_case_sha256": sha(body.encode()), "new_case_sha256": sha(actual.encode())}
    assert len(old_cases) == 6 and len(new_cases) == 17
    dump("original-case-preservation.json", {
        "python_original_cases": py_proof, "ruby_original_cases": ruby_proof,
        "old_mock_curl_other_endpoint_bytes_preserved": True,
        "old_twelve_manifest_entries_and_retired_list_preserved": True,
        "HTTP_loader_unchanged": True,
        "new_python_cases": sorted(set(py_new) - set(renamed.values()) - set(py_old)),
        "new_ruby_cases": sorted(set(new_cases) - {v["current_name"] for v in ruby_proof.values()}),
    })

    candidate_results = json.loads((PACKET / "candidate-checks/results.json").read_text())
    assert all(item["exit_code"] == 0 and not item["timed_out"] for item in candidate_results["results"].values())
    corrected = json.loads((PACKET / "candidate-corrected-ruby-check/results.json").read_text())
    assert corrected["result"]["exit_code"] == 0 and not corrected["result"]["timed_out"]
    pstdout = (PACKET / "candidate-checks/python-delivery-tests.stderr").read_text()
    assert re.search(r"Ran 34 tests in [0-9.]+s\s+OK\s*\Z", pstdout)
    assert len(re.findall(r"^test_.* \.\.\. ok$", pstdout, re.M)) == 34
    rstdout = (PACKET / "candidate-corrected-ruby-check/ruby-inventory-tests.stdout").read_text()
    assert '17 runs, 173 assertions, 0 failures, 0 errors, 0 skips' in rstdout
    dump("verification.json", {
        "verified_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "private_candidate_only": True, "changed_files": changes,
        "maintained_source_inputs": len(inputs), "source_closure_drift": drift,
        "consumer_base_guard_stable": True, "candidate_patch_sha256": sha(patch.encode()),
        "actual_private_ruby_cases": 17, "actual_private_ruby_assertions": 173,
        "actual_private_python_delivery_cases": 34,
        "old_python_cases_preserved": 30, "old_ruby_cases_preserved": 6,
        "private_manifest_functions": len(manifest_new["functions"]),
        "private_manifest_custom_auth_functions": sum(not row["verify_jwt"] for row in manifest_new["functions"]),
        "physical_candidate_index_entries": len(list((candidate / "supabase/functions").glob("*/index.ts"))),
        "OS_network_denial_probe_passed": True,
        "actual_handler_tests_executed": False, "SQL_executed": False,
        "canonical_combined_gate_executed": False, "shared_source_promotion": False,
        "hosted_or_provider_operations": False,
        "maintained_HTTP_loader_changed": False,
    })
    print(json.dumps({"private_files": len(changes), "private_ruby": 17, "private_delivery": 34,
                      "maintained_source_drift": len(drift)}))

if __name__ == "__main__":
    main()
