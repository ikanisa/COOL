"""One pinned full86 type-only check under actual OS network denial."""
from pathlib import Path
import datetime as dt
import hashlib
import importlib.util
import json
import os
import signal
import subprocess
import sys
import time

E = Path(__file__).absolute().parent
ROOT = E.parents[3]
spec = importlib.util.spec_from_file_location("type_copy_helpers", E / "prepare_private_type_candidate.py")
helpers = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helpers)
observe = helpers.observe
FREEZE = json.loads((E / "private-type-source-freeze.json").read_text())
SOURCE = Path(FREEZE["candidate_source"])
CACHE = Path(FREEZE["candidate_cache"])
DENO = ROOT / ".cache/roster-deno-2.5.6-20260929/deno"
ENV = {"PATH": os.defpath, "DENO_DIR": str(CACHE), "NO_COLOR": "1",
       "DENO_NO_UPDATE_CHECK": "1", "DENO_NO_PROMPT": "1", "PYTHONDONTWRITEBYTECODE": "1"}


def tree(directory):
    assert not any(p.is_symlink() for p in directory.rglob("*"))
    return {str(p.relative_to(directory)): observe(p) for p in sorted(directory.rglob("*")) if p.is_file()}


def run(name, command, deadline):
    started = time.monotonic()
    with (E / (name + ".stdout")).open("xb") as out, (E / (name + ".stderr")).open("xb") as err:
        child = subprocess.Popen(command, cwd=SOURCE, env=ENV, stdin=subprocess.DEVNULL,
                                 stdout=out, stderr=err, start_new_session=True)
        timed_out = False
        try:
            exit_code = child.wait(timeout=deadline)
        except subprocess.TimeoutExpired:
            timed_out = True
            os.killpg(child.pid, signal.SIGKILL)
            exit_code = child.wait(timeout=2)
    return {"command": command, "deadline_seconds": deadline, "exit_code": exit_code,
            "elapsed_seconds": time.monotonic() - started, "timed_out": timed_out,
            "owned_pid": child.pid, "owned_process_reaped": True,
            "stdout_sha256": observe(E / (name + ".stdout"))["sha256"],
            "stderr_sha256": observe(E / (name + ".stderr"))["sha256"]}


def main():
    result = {"started_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(), "status": "fail",
              "scope": "full86 type-only; no application runtime, HTTP, canonical or Linux execution"}
    sources_before = {n: observe(SOURCE / n) for n in FREEZE["source140_after_copy"]}
    cache_before = tree(CACHE)
    runtime_before = observe(DENO)
    assert runtime_before["sha256"] == "a371e0605be5039a91a079a802d66b22c124a42e31573e43136c93c2b362f1c0"
    assert sources_before == FREEZE["source140_after_copy"]
    assert len(cache_before) == 356
    profile = E / "deny-network.sb"
    with profile.open("x") as f:
        f.write("(version 1)\n(allow default)\n(deny network*)\n")
    try:
        result["runtime"] = run("runtime-version", [str(DENO), "--version"], 15)
        assert result["runtime"]["exit_code"] == 0 and (E / "runtime-version.stdout").read_text().startswith("deno 2.5.6 ")
        probe = ("import socket,errno,json;\n"
                 "try:\n s=socket.socket();s.close();raise SystemExit('Socket creation was not denied')\n"
                 "except OSError as e:\n print(json.dumps({'blocked':e.errno==errno.EPERM,'errno':e.errno}));"
                 "raise SystemExit(0 if e.errno==errno.EPERM else 1)\n")
        result["network_denial_probe"] = run("network-probe", ["/usr/bin/sandbox-exec", "-f", str(profile),
               sys.executable, "-I", "-c", probe], 15)
        assert result["network_denial_probe"]["exit_code"] == 0
        assert json.loads((E / "network-probe.stdout").read_text()) == {"blocked": True, "errno": 1}
        command = ["/usr/bin/sandbox-exec", "-f", str(profile), str(DENO), *FREEZE["type_arguments"]]
        result["types"] = run("types", command, 180)
        if result["types"]["exit_code"] != 0 or result["types"]["timed_out"]:
            raise RuntimeError("Actual full type-only check failed")
        result["status"] = "pass"
    except Exception as error:
        result["error"] = str(error)
    finally:
        result["source140_before"] = sources_before
        result["source140_after"] = {n: observe(SOURCE / n) for n in sources_before}
        result["source140_unchanged"] = sources_before == result["source140_after"]
        result["candidate_cache_before"] = cache_before
        result["candidate_cache_after"] = tree(CACHE)
        result["cache_added"] = sorted(set(result["candidate_cache_after"]) - set(cache_before))
        result["cache_removed"] = sorted(set(cache_before) - set(result["candidate_cache_after"]))
        result["cache_changed"] = {n: v for n, v in result["candidate_cache_after"].items()
                                   if n in cache_before and v != cache_before[n]}
        result["runtime_before"] = runtime_before
        result["runtime_after"] = observe(DENO)
        result["runtime_unchanged"] = runtime_before == result["runtime_after"]
        original_source, original_cache = Path(FREEZE["baseline_source"]), Path(FREEZE["baseline_cache"])
        result["baseline_source140_unchanged"] = FREEZE["source140_before"] == {n: observe(original_source / n) for n in FREEZE["source140_before"]}
        result["baseline_cache356_unchanged"] = FREEZE["original_cache_before_after"] == tree(original_cache)
        result["failed181_packet_unchanged"] = FREEZE["failed181_before_after"] == helpers.helpers.packet(E.parent / "edge-ai-canonical-batch2")
        result["maintained_QA_before_hash"] = FREEZE["base_sha256"]
        result["maintained_QA_after"] = observe(ROOT / helpers.QA)
        result["maintained_QA_unchanged"] = result["maintained_QA_after"]["sha256"] == FREEZE["base_sha256"]
        result["lock_sha256"] = observe(SOURCE / "supabase/functions/deno.lock")["sha256"]
        result["type_count"] = FREEZE["types_in_full_closure"]
        result["check_cached_only_distinction"] = "Deno2.5.6 check supports frozen lock, not cached-only; the actual cached graph check runs under OS deny network* with verified copied cache."
        result["formatter_status"] = "unchanged original failure disclosed; no format edits or waiver"
        result["canonical_invocations"] = 0
        result["runtime_tests_or_application_requests"] = 0
        result["current_checkout_acceptance"] = False
        result["finished_at_utc"] = dt.datetime.now(dt.timezone.utc).isoformat()
        if not all(result.get(n) for n in ["source140_unchanged", "runtime_unchanged", "baseline_source140_unchanged",
                                          "baseline_cache356_unchanged", "failed181_packet_unchanged", "maintained_QA_unchanged"]):
            result["status"] = "fail"
            result["error"] = "Final input or original proof drift"
        with (E / "type-verification.json").open("x") as out:
            out.write(json.dumps(result, indent=2) + "\n")
    print(json.dumps({"status": result["status"], "types": result["type_count"],
          "type_exit": result.get("types", {}).get("exit_code"), "type_elapsed": result.get("types", {}).get("elapsed_seconds"),
          "cache_added": len(result["cache_added"]), "cache_changed": len(result["cache_changed"]),
          "baseline_source_cache_proof_unchanged": result["baseline_source140_unchanged"] and result["baseline_cache356_unchanged"],
          "error": result.get("error")}, indent=2))
    return 0 if result["status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
