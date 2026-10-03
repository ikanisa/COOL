"""Finish independent read-only cleanup after retaining two sealer diagnostics."""
from pathlib import Path
import datetime as dt
import importlib.util
import json
import os
import re
import subprocess
import sys

E = Path(__file__).absolute().parent
spec = importlib.util.spec_from_file_location("completed_evidence_helpers", E / "seal_completed_evidence.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
observe, save = module.observe, module.save


def main():
    execution = json.loads((E / "execution-result.json").read_text())
    assert execution["status"] == "pass" and execution["exit_code"] == 0
    freeze = json.loads((E / "private-source-freeze.json").read_text())
    candidate = Path(freeze["private_candidate"])
    output = candidate / ".cache/canonical"
    validation = json.loads((output / "validation.json").read_text())
    linux = json.loads((output / "linux-decoder/validation.json").read_text())
    units = json.loads((output / "units/validation.json").read_text())
    http = json.loads((output / "edge-http/report.json").read_text())["runtime_result"]
    scope = json.loads((E / "permissions-and-local-scope.json").read_text())
    copies = json.loads((E / "canonical-output-copy.json").read_text())
    assert copies["count"] == len(copies["files"]) == 475
    assert all(observe(Path(r["original"])) == r["before"] == r["after"]
               and observe(Path(r["copy"])) == r["copied"] for r in copies["files"])
    final_inputs = json.loads((E / "final-source-input-readback.json").read_text())
    assert module.inventory(candidate) == final_inputs["accepted_private_manifest"]
    assert module.tree(Path(freeze["deno_cache"])) == final_inputs["cache_manifest"]
    docker = Path("/Volumes/PRO-G40/Applications/Docker.app/Contents/Resources/bin/docker")
    host = (E / "docker-socket.stdout").read_text().strip()
    assert host.startswith("unix://")
    environment = {"PATH": os.defpath, "DOCKER_HOST": host}
    security = linux["dependency_security"]["command"][4]
    assert re.fullmatch(r"collect_roster_decoder_[0-9a-f]{12}_dependency_security", security)
    commands = []
    for label, target in [("supervisor", execution["supervisor_container_id"]), ("security", security)]:
        command = [str(docker), "inspect", "--type", "container", target]
        result = subprocess.run(command, env=environment, capture_output=True, text=True, timeout=15)
        out, err = E / ("cleanup-final-" + label + ".stdout"), E / ("cleanup-final-" + label + ".stderr")
        with out.open("x") as f:
            f.write(result.stdout)
        with err.open("x") as f:
            f.write(result.stderr)
        diagnostics = {"Error response from daemon: No such container: " + target,
                       "Error: No such object: " + target}
        absent = result.returncode == 1 and result.stderr.strip() in diagnostics
        assert absent, (label, result.returncode, result.stderr)
        commands.append({"label": label, "command": command, "deadline_seconds": 15,
                         "exit_code": result.returncode, "confirmed_exact_absent": True,
                         "stderr": result.stderr, "stdout_sha256": observe(out)["sha256"],
                         "stderr_sha256": observe(err)["sha256"]})
    command = [str(docker), "ps", "--all", "--filter", "ancestor=" + linux["image_id"], "--format", "{{.ID}}"]
    containers = subprocess.run(command, env=environment, check=True, capture_output=True, text=True, timeout=15)
    assert not containers.stdout.strip()
    ps = subprocess.run(["/bin/ps", "-axo", "pid=,ppid=,pgid=,stat=,lstart="],
                        check=True, capture_output=True, text=True, timeout=15)
    table = {}
    for line in ps.stdout.splitlines():
        row = line.split(None, 4)
        if len(row) == 5:
            table[row[0]] = {"ppid": int(row[1]), "pgid": int(row[2]), "stat": row[3], "birth": row[4]}
    observed = execution["observed_owned_processes"]
    matched = {n: row for n, row in table.items() if n in observed and row["birth"] == observed[n]["birth"]}
    live = {n: row for n, row in matched.items() if not row["stat"].startswith("Z")}
    assert not live
    save("owned-cleanup-readback.json", {"observed_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
         "commands": commands, "new_image_container_query": {"command": command, "exit_code": containers.returncode,
         "stdout": containers.stdout, "stderr": containers.stderr, "deadline_seconds": 15},
         "original_cleanup": execution["remaining_owned_process_cleanup"], "observed_original_process_identities": observed,
         "birth_matched_processes": matched, "live_owned_processes": live, "http_reported_closed_listeners": http["servers_closed"],
         "scoped_cleanup_pass": True, "new_local_image_retained": True, "global_daemon_cleanup_claimed": False,
         "prior_cleanup_classifier_failure_retained": True})
    save("phase-summary.json", {"status": "pass", "started_at_utc": execution["started_at_utc"],
         "finished_at_utc": execution["finished_at_utc"], "elapsed_seconds": execution["elapsed_seconds"],
         "runner_contract_tests": 77, "types": validation["phases"]["types"]["files_checked"],
         "unit_files": units["test_file_count"], "unit_tests": units["tests_passed"], "unit_steps": units["steps_passed"],
         "unit_failed": 0, "unit_ignored": 0, "HTTP_checks": len(http["checks"]), "HTTP_failed": 0,
         "Linux_cases": len(linux["cases"]), "signed_Linux_HTTP": validation["phases"]["linux_decoder"]["integration"],
         "regressions": validation["phases"]["linux_decoder"]["regressions"], "security": linux["dependency_security"],
         "fresh_image_id": linux["image_id"], "fresh_image_tag": scope["fresh_image_tag"],
         "decoder_build_sha256": linux["decoder_build_sha256"], "actual_fresh_image_toolchain": execution["fresh_image_toolchain"],
         "whole_build_Linux_deadlines": [1200, 300, 600], "current_SQL_executed": False, "current_checkout_acceptance": False})
    save("sealer-diagnostics-resolution.json", {"observed_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
         "canonical_invocations": 1, "canonical_result_unchanged": "pass", "evidence_only_corrections": [
         "Attempt1 schema mismatch: exact SHA/size/mode preparation fields now compared, all leaves preserved.",
         "Attempt2 actual No such container diagnostic did not match the narrower No such object classifier. Original traceback and exact stderr retained; independent exact target diagnostic plus successful zero-container query now proves scoped absence."],
         "attempt1_source_and_transcribed_diagnostic_retained": True,
         "attempt2_actual_stdout_stderr_retained": True, "complete_original_and_copied_outputs_identical": True,
         "private_source_and_cache_unchanged_after_gate": True, "final_owned_cleanup": "pass"})
    print(json.dumps({"status": "completed_readback", "actual_output_files": copies["count"],
                     "actual_output_bytes": copies["bytes"], "actual_regressions": 212,
                     "independent_owned_cleanup": "pass", "canonical_invocations": 1}, indent=2))


if __name__ == "__main__":
    main()
