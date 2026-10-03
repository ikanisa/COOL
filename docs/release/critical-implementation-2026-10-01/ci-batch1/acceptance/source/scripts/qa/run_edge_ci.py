#!/usr/bin/env python3
"""Canonical local/CI Edge gate: frozen types, units, HTTP and actual Linux decoder.

Current SQL acceptance, hosted providers, deployment and devices are separate.
The unit observation contract is dated synthetic SQL output, not a live database.
"""
from __future__ import annotations

import argparse
import datetime as dt
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).parent))
from run_edge_unit_tests import FIXTURE, INTEGRATION, passed_summary, sha, validate_fixture


def source_paths() -> list[Path]:
    paths = list((ROOT / "supabase/functions").rglob("*.ts"))
    paths += list((ROOT / "supabase/functions").rglob("fixtures/*.json"))
    for pattern in ("*.py", "requirements.*", "Dockerfile"):
        paths += list((ROOT / "tools/roster-decoder").glob(pattern))
    paths += list((ROOT / "contracts/collect-android-attempt-archive-v3/fixtures").glob("*.json"))
    paths += list((ROOT / "contracts/collect-android-dispatch-v2/fixtures").glob("*.json"))
    paths += validate_fixture(FIXTURE)
    # Match every source actually exercised by the existing Linux gate.
    spec = importlib.util.spec_from_file_location("roster_gate", ROOT / "scripts/tests/verify_roster_decoder.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    paths += module.SOURCES
    paths += [ROOT / p for p in (
        ".dvmrc", ".github/workflows/ci.yml", "supabase/functions/deno.lock",
        "supabase/config.toml", "Makefile", "scripts/qa/run_edge_ci.py",
        "scripts/qa/run_edge_unit_tests.py", "scripts/qa/run_edge_http_uat.py",
        "docs/release/critical-implementation-2026-10-01/ci-batch1/test_runner_contract.py",
        "scripts/qa/edge_http_runtime_uat.ts")]
    return sorted(set(paths))


def install_deno_shim(directory: Path, binary: Path, python: Path, trace: Path) -> None:
    """Existing Linux gate uses PATH Deno; enforce the same exact binary and lock."""
    directory.mkdir()
    script = "#!" + str(python) + "\n" + (
        "import json,os,sys\n"
        f"binary={str(binary)!r}\n"
        f"trace={str(trace)!r}\n"
        "args=sys.argv[1:]\n"
        "if not args or args[0] not in ('test','run','check'):\n"
        " raise SystemExit('Only pinned test/run/check commands are permitted')\n"
        "flags=['--no-config','--frozen','--lock=supabase/functions/deno.lock']\n"
        "if args[0] in ('test','run'):flags+=['--cached-only','--no-prompt']\n"
        "command=[binary,args[0],*flags,*args[1:]]\n"
        "with open(trace,'a') as log:log.write(json.dumps(command)+'\\n')\n"
        "os.execv(binary,command)\n"
    )
    target = directory / "deno"
    target.write_text(script)
    target.chmod(0o700)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--deno", type=Path, required=True)
    parser.add_argument("--decoder-python", type=Path, required=True,
                        help="Python 3.12 venv with tools/roster-decoder/requirements.lock installed")
    parser.add_argument("--output", type=Path, required=True, help="Fresh repository .cache directory")
    parser.add_argument("--cache-dependencies", action="store_true",
                        help="Resolve the frozen graph before execution; no runtime provider calls")
    args = parser.parse_args()
    output = args.output.resolve()
    if output.exists() or not output.is_relative_to(ROOT / ".cache"):
        parser.error("Fresh contained .cache output directory required")
    output.mkdir(parents=True, mode=0o700)
    report = {"status": "fail", "started_at": dt.datetime.now(dt.timezone.utc).isoformat(),
              "required_phases": ["runner_contract", "types", "units", "edge_http", "linux_decoder"],
              "phases": {}, "provider_calls": 0, "current_sql_executed": False,
              "sql_scope": "Immutable dated synthetic observation decoder contract; current SQL is a separate gate",
              "integration_file": INTEGRATION}
    paths, before = [], None
    env = None

    def execute(name: str, command: list[str], timeout: int = 180) -> str:
        step = {"status": "fail", "command": command}
        report["phases"][name] = step
        with (output / (name + ".stdout")).open("xb") as stdout, \
                (output / (name + ".stderr")).open("xb") as stderr:
            completed = subprocess.run(command, cwd=ROOT, env=env, stdout=stdout, stderr=stderr, timeout=timeout)
        step.update(exit_code=completed.returncode,
                    stdout_sha256=sha(output / (name + ".stdout")),
                    stderr_sha256=sha(output / (name + ".stderr")))
        if completed.returncode:
            raise RuntimeError(f"{name} command failed; inspect its evidence")
        step["status"] = "pass"
        return (output / (name + ".stdout")).read_text()

    try:
        binary = args.deno.resolve(strict=True)
        python = args.decoder_python.absolute()
        runtime = json.loads(subprocess.check_output([str(binary), "info", "--json"], text=True, timeout=10))
        if runtime["denoVersion"] != (ROOT / ".dvmrc").read_text().strip():
            raise RuntimeError("Deno must exactly match .dvmrc")
        pyversion = subprocess.check_output([str(python), "-c", "import sys;print('.'.join(map(str,sys.version_info[:3])))"],
                                            text=True, timeout=10).strip()
        if not pyversion.startswith("3.12."):
            raise RuntimeError("Linux decoder fixture generator requires Python 3.12")
        docker, ruby = shutil.which("docker"), shutil.which("ruby")
        if not docker or not ruby:
            raise RuntimeError("Actual Docker Linux daemon and Ruby syntax check are mandatory prerequisites")
        tool_dirs = {str(Path(p).parent) for p in (docker, ruby)}
        shim = output / "pinned-tools"
        install_deno_shim(shim, binary, python, output / "linux-deno-commands.jsonl")
        env = {"PATH": os.pathsep.join([str(shim), *sorted(tool_dirs), os.defpath]),
               "DENO_DIR": runtime["denoDir"], "NO_COLOR": "1", "DENO_NO_UPDATE_CHECK": "1",
               "PYTHONDONTWRITEBYTECODE": "1", "DENO_NO_PROMPT": "1", "DENO_BIN": str(binary)}
        # Docker Desktop on macOS may select a local Unix socket through its context.
        socket = subprocess.check_output([docker, "context", "inspect", "--format",
                                          "{{.Endpoints.docker.Host}}"], text=True, timeout=10).strip()
        if not socket.startswith("unix://"):
            raise RuntimeError("Local Unix Docker endpoint required; no remote container operations")
        env["DOCKER_HOST"] = socket
        platform = subprocess.check_output([docker, "info", "--format", "{{.OSType}}/{{.Architecture}}"],
                                           env=env, text=True, timeout=15).strip()
        if platform not in ("linux/aarch64", "linux/arm64"):
            raise RuntimeError("Native Linux ARM64 daemon required by the hash-locked decoder wheels")
        report["runtime"] = {"version": runtime["denoVersion"], "binary_sha256": sha(binary),
                             "decoder_python": pyversion, "docker_platform": platform}
        paths = source_paths()
        before = {str(p.relative_to(ROOT)): sha(p) for p in paths}
        report["source_before"] = before
        for path in paths:
            target = output / "source" / path.relative_to(ROOT)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, target)
        execute("runner_contract", [sys.executable,
                "docs/release/critical-implementation-2026-10-01/ci-batch1/test_runner_contract.py"])
        ts = sorted(str(p.relative_to(ROOT)) for p in (ROOT / "supabase/functions").rglob("*.ts"))
        graph = [*ts, "scripts/qa/edge_http_runtime_uat.ts",
                 "scripts/tests/roster_extraction_evaluation.ts", "scripts/tests/roster_extraction_evaluation_test.ts"]
        flags = ["--no-config", "--frozen", "--lock=supabase/functions/deno.lock"]
        if args.cache_dependencies:
            execute("frozen_dependency_cache", [str(binary), "cache", *flags, *graph], 300)
        execute("types", [str(binary), "check", *flags, *graph])
        report["phases"]["types"]["files_checked"] = len(graph)
        execute("units", [sys.executable, "scripts/qa/run_edge_unit_tests.py", "--deno", str(binary),
                          "--output", str(output / "units")])
        units = json.loads((output / "units/validation.json").read_text())
        if units["status"] != "pass" or not units["source_unchanged"] or units["tests_ignored"] != 0:
            raise RuntimeError("Complete unit acceptance required")
        report["phases"]["units"].update(test_files=units["test_file_count"], tests=units["tests_passed"], ignored=0)
        execute("edge_http", [sys.executable, "scripts/qa/run_edge_http_uat.py", str(output / "edge-http")])
        http = json.loads((output / "edge-http/report.json").read_text())
        if http["status"] != "pass" or not http["source_inputs_unchanged"]:
            raise RuntimeError("Actual source-stable HTTP acceptance required")
        report["phases"]["edge_http"]["checks"] = len(http["runtime_result"]["checks"])
        execute("linux_decoder", [sys.executable, "scripts/tests/verify_roster_decoder.py",
                                 "--python", str(python), "--output", str(output / "linux-decoder")], 600)
        linux = json.loads((output / "linux-decoder/validation.json").read_text())
        if linux.get("passed") is not True or linux.get("source_before") != linux.get("source_after"):
            raise RuntimeError("Actual source-stable Linux sandbox acceptance required")
        integration = passed_summary((output / "linux-decoder/edge-decoder-integration.log").read_text())
        regression = passed_summary((output / "linux-decoder/regressions.log").read_text())
        commands = [json.loads(line) for line in (output / "linux-deno-commands.jsonl").read_text().splitlines()]
        if len(commands) != 4 or not any(INTEGRATION in command for command in commands):
            raise RuntimeError("All four pinned Linux Deno commands, including integration, are required")
        report["phases"]["linux_decoder"].update(cases=len(linux["cases"]), integration=integration,
                                                regressions=regression, commands=commands, image_id=linux["image_id"])
        if any(report["phases"].get(name, {}).get("status") != "pass" for name in report["required_phases"]):
            raise RuntimeError("Every required phase must pass")
        report["status"] = "pass"
    except Exception as error:
        report["error"] = str(error)
    finally:
        try:
            after = {str(p.relative_to(ROOT)): sha(p) for p in paths}
            report.update(source_after=after, source_unchanged=before is not None and before == after)
        except OSError as error:
            report.update(source_unchanged=False, source_error=str(error))
        if not report["source_unchanged"]:
            report["status"] = "fail"
            report.setdefault("error", "Source inputs changed during canonical acceptance")
        report["finished_at"] = dt.datetime.now(dt.timezone.utc).isoformat()
        (output / "validation.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"status": report["status"], "phases": {
        name: {k: v for k, v in phase.items() if k in ("status", "tests", "checks", "cases", "ignored")}
        for name, phase in report["phases"].items()}, "error": report.get("error"),
        "report": str(output / "validation.json")}))
    return 0 if report["status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
