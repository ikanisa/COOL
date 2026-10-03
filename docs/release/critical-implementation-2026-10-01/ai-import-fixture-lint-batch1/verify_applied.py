from pathlib import Path
import hashlib, json, subprocess, os, re, datetime, time
ROOT = Path(__file__).resolve().parents[4]
OUT = Path(__file__).resolve().parent
DENO = ROOT / ".cache/roster-deno-2.5.6-20260929/deno"
CACHE = ROOT / ".cache/edge-current-integration-batch1/attempt2/deno-dir"
STAGE = ROOT / ".cache/ai-import-fixture-lint-batch1/proposal/source"
APP = json.loads((OUT / "application.json").read_text())
EXPECTED = APP["current_after"]
ENTRIES = ["supabase/functions/_shared/openai_roster_test.ts", "supabase/functions/_shared/roster_response_policy_test.ts", "supabase/functions/prepare-roster-import/handler_test.ts", "scripts/tests/roster_extraction_evaluation_test.ts"]
OWNED = ["supabase/functions/_shared/openai_roster.ts", "supabase/functions/_shared/openai_roster_test.ts", "supabase/functions/prepare-roster-import/handler_test.ts"]
def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()
def cohort(base):
    return {p: sha(base / p) for p in EXPECTED}
def remotes():
    return {str(p): sha(p) for p in sorted((CACHE / "remote").rglob("*")) if p.is_file()}
report = {"status": "fail", "scope": "current applied one-testfile fixture cleanup; four actual affected test entries", "source_current_before": cohort(ROOT), "reviewed_private_before": cohort(STAGE), "runtime_before": sha(DENO), "remote_cache_before": remotes(), "runner_before": sha(Path(__file__)), "started_at": datetime.datetime.now(datetime.timezone.utc).isoformat(), "phases": [], "live_provider_calls": 0, "database_calls": 0, "runtime_network_permission": False, "cached_only": True, "lock_frozen": True, "lint_exclusions": [], "suppressed_exceptions": 0}
env = {"PATH": os.defpath, "DENO_DIR": str(CACHE), "DENO_NO_UPDATE_CHECK": "1", "NO_COLOR": "1"}
flags = ["--no-config", "--cached-only", "--no-prompt", "--frozen", "--lock=supabase/functions/deno.lock"]
try:
    assert report["source_current_before"] == EXPECTED == report["reviewed_private_before"], "current/reviewed source mismatch"
    assert report["runtime_before"] == "a371e0605be5039a91a079a802d66b22c124a42e31573e43136c93c2b362f1c0", "runtime mismatch"
    version = subprocess.check_output([str(DENO), "--version"], env=env, text=True, timeout=10)
    assert version.splitlines()[0].split()[1] == (ROOT / ".dvmrc").read_text().strip() == "2.5.6"
    (OUT / "applied-runtime.txt").write_text(version)
    commands = [("applied-types", ["test", "--no-run", *flags, *ENTRIES]), ("applied-tests", ["test", *flags, *ENTRIES]), ("applied-lint", ["lint", "--no-config", *OWNED]), ("applied-format-check", ["fmt", "--check", *OWNED])]
    for label, args in commands:
        command = [str(DENO), *args]
        start = time.monotonic()
        with (OUT / (label + ".stdout")).open("xb") as out, (OUT / (label + ".stderr")).open("xb") as err:
            run = subprocess.run(command, cwd=ROOT, env=env, stdout=out, stderr=err, timeout=60)
        report["phases"].append({"label": label, "command": command, "cwd": str(ROOT), "exit_code": run.returncode, "seconds": round(time.monotonic() - start, 3)})
    summary = re.findall(r"(\d+) passed \| (\d+) failed", (OUT / "applied-tests.stdout").read_text())
    assert summary == [("109", "0")], "unexpected tests summary"
    report["tests"] = {"passed": 109, "failed": 0}
    assert all(p["exit_code"] == 0 for p in report["phases"]), "one or more actual check failures"
    report["status"] = "pass"
except Exception as exc:
    report["error"] = str(exc) or type(exc).__name__
finally:
    report.update(source_current_after=cohort(ROOT), reviewed_private_after=cohort(STAGE), runtime_after=sha(DENO), remote_cache_after=remotes(), runner_after=sha(Path(__file__)), finished_at=datetime.datetime.now(datetime.timezone.utc).isoformat())
    report["source_unchanged"] = report["source_current_before"] == report["source_current_after"] == report["reviewed_private_before"] == report["reviewed_private_after"] == EXPECTED
    report["tools_unchanged"] = report["runtime_before"] == report["runtime_after"] and report["remote_cache_before"] == report["remote_cache_after"] and report["runner_before"] == report["runner_after"]
    if not report["source_unchanged"] or not report["tools_unchanged"]:
        report["status"] = "fail"
        report["error"] = "source/tool/cache drift"
    (OUT / "applied-verification.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"status": report["status"], "tests": report.get("tests"), "phase_exit_codes": [p["exit_code"] for p in report["phases"]], "source_inputs": len(EXPECTED), "remote_cache_inputs": len(report["remote_cache_before"]), "source_unchanged": report["source_unchanged"], "tools_unchanged": report["tools_unchanged"], "error": report.get("error")}))
    raise SystemExit(0 if report["status"] == "pass" else 1)
