"""Actual pinned Deno checksum rejection in a private copy of existing tests."""
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import time

ROOT = Path(__file__).resolve().parents[4]
OUT = Path(__file__).resolve().parent
BINARY = ROOT / ".cache/roster-deno-2.5.6-20260929/deno"
STAGE = ROOT / ".cache/edge-clean-cache-batch1/lock-probe"
LOCK = "supabase/functions/deno.lock"
SOURCES = [LOCK, ".dvmrc", "supabase/functions/_shared/apns_test.ts",
           "supabase/functions/_shared/apns.ts",
           "supabase/functions/_shared/notification_retry.ts",
           "supabase/functions/_shared/production_contract.ts"]
URL = "https://deno.land/std@0.224.0/assert/mod.ts"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    if STAGE.exists():
        raise SystemExit("Fresh private staging is required; do not overwrite evidence")
    STAGE.mkdir(parents=True, mode=0o700)
    cache = STAGE / "dependency-cache"
    cache.mkdir(mode=0o700)
    before = {name: sha(ROOT / name) for name in SOURCES}
    binary_before = sha(BINARY)
    report = {"status": "fail", "started_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
              "runtime_binary": str(BINARY), "runtime_sha256": binary_before,
              "real_source_before": before, "initial_dependency_cache_file_count": 0,
              "dependency_cache": str(cache), "network_execution_permission": False,
              "public_dependency_import_hosts": ["deno.land"], "provider_calls": 0,
              "steps": []}
    env = {"PATH": os.defpath, "DENO_DIR": str(cache), "DENO_NO_UPDATE_CHECK": "1",
           "DENO_NO_PROMPT": "1", "NO_COLOR": "1", "PYTHONDONTWRITEBYTECODE": "1"}

    def command(name, graph, arguments):
        argv = [str(BINARY), *arguments]
        start = time.monotonic()
        result = subprocess.run(argv, cwd=graph, env=env, capture_output=True,
                                text=True, timeout=120)
        (OUT / (name + ".stdout")).write_text(result.stdout)
        (OUT / (name + ".stderr")).write_text(result.stderr)
        step = {"name": name, "command": argv, "cwd": str(graph),
                "exit_code": result.returncode, "elapsed_seconds": round(time.monotonic() - start, 3),
                "stdout_sha256": sha(OUT / (name + ".stdout")),
                "stderr_sha256": sha(OUT / (name + ".stderr"))}
        report["steps"].append(step)
        return result

    try:
        info = subprocess.run([str(BINARY), "info", "--json"], env=env,
                              capture_output=True, text=True, check=True, timeout=10)
        runtime = json.loads(info.stdout)
        assert runtime["denoVersion"] == (ROOT / ".dvmrc").read_text().strip() == "2.5.6"
        assert Path(runtime["denoDir"]).resolve() == cache.resolve()
        assert not any(path.is_file() for path in cache.rglob("*"))
        report["runtime_version"] = runtime["denoVersion"]
        for group in ("valid", "corrupted"):
            for name in SOURCES:
                target = STAGE / group / name
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT / name, target)
                assert sha(target) == before[name]
        corrupted = STAGE / "corrupted" / LOCK
        value = json.loads(corrupted.read_text())
        expected = value["remote"][URL]
        value["remote"][URL] = "0" * 64
        corrupted.write_text(json.dumps(value, indent=2) + "\n")
        report["corruption"] = {"private_lock": str(corrupted), "url": URL,
                                "original_integrity": expected, "corrupted_integrity": "0" * 64,
                                "private_corrupted_lock_sha256": sha(corrupted)}
        flags = ["--no-config", "--frozen", "--lock=" + LOCK]
        test = "supabase/functions/_shared/apns_test.ts"
        cached = command("valid_public_dependency_fetch", STAGE / "valid",
                         ["cache", *flags, "--allow-import=deno.land:443", test])
        assert cached.returncode == 0, "Valid frozen public graph resolution failed"
        valid = command("valid_actual_tests", STAGE / "valid",
                        ["test", *flags, "--cached-only", "--no-prompt", test])
        assert valid.returncode == 0 and "3 passed | 0 failed" in valid.stdout
        failed = command("corrupted_actual_tests", STAGE / "corrupted",
                         ["test", *flags, "--cached-only", "--no-prompt", test])
        diagnostic = failed.stderr.lower()
        assert failed.returncode != 0 and (
            "integrity check failed" in diagnostic or "lockfile checksum" in diagnostic)
        assert "running 3 tests" not in failed.stdout
        report.update(status="pass", valid_actual_tests_passed=3,
                      corrupted_lock_rejected_before_test_execution=True)
    except Exception as error:
        report["error"] = str(error)
    finally:
        after = {name: sha(ROOT / name) for name in SOURCES}
        report.update(real_source_after=after, real_source_unchanged=before == after,
                      runtime_binary_unchanged=sha(BINARY) == binary_before,
                      finished_at_utc=dt.datetime.now(dt.timezone.utc).isoformat())
        if not report["real_source_unchanged"] or not report["runtime_binary_unchanged"]:
            report["status"] = "fail"
        (OUT / "lock-probe.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({k: report.get(k) for k in ("status", "error", "valid_actual_tests_passed",
        "corrupted_lock_rejected_before_test_execution", "real_source_unchanged", "runtime_binary_unchanged")}))
    return 0 if report["status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
