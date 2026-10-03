"""One exact-source maintained Linux acceptance plus bounded dependency cases."""
from __future__ import annotations

import datetime as dt
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parents[4]
PACKET = Path(__file__).resolve().parent / "attempt2"
CACHE = ROOT / ".cache/decoder-dependency-batch1"
DOCKER = Path("/Volumes/PRO-G40/Applications/Docker.app/Contents/Resources/bin/docker")
DENO = ROOT / ".cache/roster-deno-2.5.6-20260929/deno"
PYTHON = CACHE / "fixture-generator-venv/bin/python"
TEST = ROOT / "tools/roster-decoder/test_dependency_security.py"
OLD_IMAGE = "sha256:79afc61b97669e70a7d5dff4219d7be318b3c2220ff7a25b32ad0c15b89933ea"
IDENTITIES = {
    "supabase/functions/_shared/roster_decoder.ts":
        "d91966ea21705aa50dc6daeb6316961ee02ec10e2685ee746cddf2aa5b82efdb",
    "supabase/functions/_shared/roster_decoder_test.ts":
        "1c45764e93d64198e3a39a9dfe17d26acd5e800e59407765cf9e4ffada6bbc1e",
    "supabase/functions/prepare-roster-import/handler_test.ts":
        "964264c15f33e6d6e798888904379f61eea871d80ff6fc3cd3d3b51104b9109f",
    "scripts/tests/verify_roster_decoder.py":
        "2208aaf3239a22f79467583e8ea4a394dd13c6dd6e4820e810f93023c75ab73d",
}


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    stage = CACHE / "attempt2/source"
    output = stage / ".cache/linux-acceptance"
    if stage.exists() or (PACKET / "acceptance.json").exists():
        raise ValueError("A fresh explicit source stage and receipt are required")
    sys.path.insert(0, str(ROOT / "scripts/qa"))
    import run_edge_ci as canonical
    from run_edge_unit_tests import passed_summary
    paths = canonical.source_paths()
    before = {str(p.relative_to(ROOT)): sha(p) for p in paths}
    if any(before.get(n) != h for n, h in IDENTITIES.items()):
        raise ValueError("The parent's explicitly coordinated consumer source changed")
    PACKET.mkdir(mode=0o700)
    stage.mkdir(mode=0o700, parents=True)
    for path in paths:
        if path.is_symlink() or not path.is_file():
            raise ValueError("Contained regular source files required")
        target = stage / path.relative_to(ROOT)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, target)
        target.chmod(0o444)
    if any(sha(stage / n) != h for n, h in before.items()):
        raise ValueError("Copied source bytes must match the frozen closure")
    shim = CACHE / "attempt2/pinned-tools"
    canonical.install_deno_shim(shim, DENO, PYTHON, PACKET / "linux-deno-commands.jsonl")
    socket = subprocess.check_output([str(DOCKER), "context", "inspect", "--format",
                                     "{{.Endpoints.docker.Host}}"], text=True, timeout=10).strip()
    if not socket.startswith("unix://"):
        raise ValueError("Local Unix Docker endpoint required")
    env = {"PATH": os.pathsep.join([str(shim), str(DOCKER.parent), os.defpath]),
           "DOCKER_HOST": socket, "PYTHONDONTWRITEBYTECODE": "1", "NO_COLOR": "1",
           "DENO_DIR": str(ROOT / ".cache/edge-clean-cache-batch1/attempt3/deno-dir"),
           "DENO_NO_UPDATE_CHECK": "1", "DENO_NO_PROMPT": "1"}
    command = [sys.executable, "-B", "scripts/tests/verify_roster_decoder.py",
               "--python", str(PYTHON), "--output", str(output)]
    report = {"status": "fail", "started_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
              "source_before": before, "read_only_source_copy": str(stage),
              "runtime_sha256": sha(DENO), "driver_sha256": sha(__file__),
              "fixture_generator_python": str(PYTHON), "command": command,
              "provider_calls": 0, "current_sql_executed": False, "steps": []}

    def execute(label, argv, timeout=20, cwd=stage, expected_exit=0):
        stdout, stderr = PACKET / (label + ".stdout"), PACKET / (label + ".stderr")
        start = time.monotonic()
        with stdout.open("xb") as out, stderr.open("xb") as err:
            result = subprocess.run(argv, cwd=cwd, env=env, stdout=out, stderr=err, timeout=timeout)
        step = {"label": label, "command": argv, "exit_code": result.returncode,
                "elapsed_seconds": round(time.monotonic() - start, 3),
                "stdout_sha256": sha(stdout), "stderr_sha256": sha(stderr)}
        report["steps"].append(step)
        if result.returncode != expected_exit:
            raise ValueError(f"{label} failed with exit{result.returncode}; evidence retained")
        return stdout.read_text()

    def container_case(label, image, arguments):
        name = "collect_decoder_dependency_" + uuid.uuid4().hex[:12]
        argv = [str(DOCKER), "run", "--rm", "--name", name, "--network", "none",
                "--read-only", "--security-opt", "no-new-privileges", "--cap-drop", "ALL",
                "--memory", "512m", "--cpus", "1", "--pids-limit", "16",
                "--tmpfs", "/tmp:rw,noexec,nosuid,size=8m",
                "--mount", f"type=bind,src={stage / TEST.relative_to(ROOT)},dst=/app/test_dependency_security.py,readonly",
                "--entrypoint", "python", image, "-I", *arguments]
        try:
            return execute(label, argv, expected_exit=1 if label == "previous-pdf-negative" else 0)
        finally:
            # Only the uniquely named container owned by this exact invocation.
            listing = subprocess.run([str(DOCKER), "ps", "-a", "--filter", "name=^/" + name + "$",
                                      "--format", "{{.ID}}"], env=env, capture_output=True, text=True, timeout=10)
            if listing.returncode:
                raise ValueError("Could not verify task container cleanup")
            if listing.stdout.strip():
                subprocess.run([str(DOCKER), "rm", "-f", name], env=env,
                               capture_output=True, text=True, check=True, timeout=10)
                raise ValueError("Timed-out or remaining task container was removed; phase is incomplete")
            report.setdefault("removed_owned_containers", []).append(name)

    try:
        (PACKET / "acceptance.json").write_text(json.dumps(report, indent=2) + "\n")
        execute("maintained-linux", command, timeout=600)
        linux = json.loads((output / "validation.json").read_text())
        if linux.get("passed") is not True or linux["source_before"] != linux["source_after"]:
            raise ValueError("Actual maintained Linux source-stable acceptance is required")
        report["linux"] = {"image_id": linux["image_id"], "cases": len(linux["cases"]),
                           "integration": passed_summary((output / "edge-decoder-integration.log").read_text()),
                           "regressions": passed_summary((output / "regressions.log").read_text()),
                           "decoder_build_sha256": linux["decoder_build_sha256"]}
        if report["linux"]["cases"] != 32:
            raise ValueError("All32 original maintained cases are required")
        versions = container_case("installed-package-versions", linux["image_id"], ["-c",
            "import importlib.metadata as m,json,sys;print(json.dumps({'python':'.'.join(map(str,sys.version_info[:3])),'packages':{n:m.version(n)for n in ['Pillow','pypdf','pypdfium2','openpyxl','defusedxml','et-xmlfile']}}))"])
        report["installed_linux_versions"] = json.loads(versions)
        if report["installed_linux_versions"] != {
            "python": "3.12.14", "packages": {"Pillow": "12.3.0", "pypdf": "6.19.0",
            "pypdfium2": "5.2.0", "openpyxl": "3.1.5", "defusedxml": "0.7.1", "et-xmlfile": "2.0.0"}
        }:
            raise ValueError("The actual image's package versions must exactly match the reviewed pins")
        container_case("dependency-security", linux["image_id"], ["/app/test_dependency_security.py"])
        completed = (PACKET / "dependency-security.stderr").read_text()
        if "Ran 6 tests" not in completed or not completed.rstrip().endswith("OK") or "skipped" in completed:
            raise ValueError("All six bounded security regression cases must complete")
        report["dependency_security_tests"] = {"passed": 6, "failed": 0, "skipped": 0,
            "scope": "Actual tiny hostile PDFs and signed-coordinate API inputs under production isolate limits"}
        container_case("previous-pdf-negative", OLD_IMAGE, ["/app/test_dependency_security.py", "HostilePdf"])
        prior = (PACKET / "previous-pdf-negative.stderr").read_text()
        if "Ran 3 tests" not in prior or "FAILED (failures=2)" not in prior:
            raise ValueError("The previous exact image must fail only the two newly covered font-token cases")
        report["prior_pdf_negative"] = {"image_id": OLD_IMAGE, "cases": 3,
            "benign_passed": 1, "hostile_expected_failures": 2,
            "scope": "Only bounded PDF cases; no vulnerable native coordinate primitive executed"}
        report["status"] = "pass"
    except Exception as error:
        report["error"] = str(error)
    finally:
        after = {n: sha(ROOT / n) for n in before}
        copied = {n: sha(stage / n) for n in before}
        report.update(source_after=after, current_source_unchanged=after == before,
                      copied_source_unchanged=copied == before,
                      finished_at_utc=dt.datetime.now(dt.timezone.utc).isoformat())
        if after != before or copied != before:
            report.update(status="fail", source_error="Frozen source closure changed during execution")
        if output.exists():
            shutil.copytree(output, PACKET / "linux-acceptance")
        report["artifact_sha256"] = {str(p.relative_to(PACKET)): sha(p)
            for p in sorted(PACKET.rglob("*")) if p.is_file() and p.name != "acceptance.json"}
        (PACKET / "acceptance.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({k: report.get(k) for k in
                      ("status", "error", "linux", "dependency_security_tests", "current_source_unchanged")}))
    return 0 if report["status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
