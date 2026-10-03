"""One reviewed current154 private invocation; no maintained-source mutation or SQL acceptance."""
from pathlib import Path
import datetime as dt
import hashlib
import json
import os
import re
import shutil
import signal
import stat
import subprocess
import sys
import time

EVIDENCE = Path(__file__).absolute().parent
ROOT = EVIDENCE.parents[3]
FREEZE = json.loads((EVIDENCE / "private-source-freeze.json").read_text())
CANDIDATE = Path(FREEZE["private_candidate"])
COHORT = Path(FREEZE["cohort"])
OUTPUT = CANDIDATE / ".cache/canonical"
DENO = ROOT / ".cache/roster-deno-2.5.6-20260929/deno"
PYTHON = ROOT / ".cache/decoder-dependency-batch1/fixture-generator-venv/bin/python"
DOCKER = Path("/Volumes/PRO-G40/Applications/Docker.app/Contents/Resources/bin/docker")
RUBY = Path(shutil.which("ruby"))
ENV = {"PATH": os.pathsep.join([str(DOCKER.parent), str(RUBY.parent), os.defpath]),
       "DENO_DIR": FREEZE["deno_cache"], "NO_COLOR": "1", "DENO_NO_UPDATE_CHECK": "1",
       "DENO_NO_PROMPT": "1", "PYTHONDONTWRITEBYTECODE": "1"}


def sha(path):
    result = hashlib.sha256()
    with path.open("rb") as value:
        while chunk := value.read(1024 * 1024):
            result.update(chunk)
    return result.hexdigest()


def observe(path):
    info = path.lstat()
    if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1:
        raise ValueError("Regular unaliased source required")
    return {"sha256": sha(path), "bytes": info.st_size, "mode": stat.S_IMODE(info.st_mode)}


def source_map(base):
    return {row["path"]: observe(base / row["path"]) for row in FREEZE["source_manifest"]}


def maintained_source_map():
    original = json.loads((EVIDENCE / "maintained-source-before.json").read_text())
    return {name: observe(ROOT / name) for name in original}


def process_table():
    value = subprocess.run(["ps", "-axo", "pid=,ppid=,pgid=,stat=,lstart="],
        capture_output=True, text=True, timeout=5, env=ENV)
    if value.returncode:
        raise RuntimeError("Owned process observation unavailable")
    records = {}
    for line in value.stdout.splitlines():
        fields = line.split()
        if len(fields) < 9:
            continue
        records[int(fields[0])] = {"ppid": int(fields[1]), "pgid": int(fields[2]),
                                  "stat": fields[3], "birth": " ".join(fields[4:])}
    return records


def descendants(table, parent):
    found = {parent}
    while True:
        new = found | {pid for pid, row in table.items() if row["ppid"] in found}
        if new == found:
            return found
        found = new


def terminate_owned(observed):
    table = process_table()
    owned = {pid: row for pid, row in table.items() if pid in observed
             and row["birth"] == observed[pid]["birth"] and not row["stat"].startswith("Z")}
    groups = {row["pgid"] for row in owned.values()}
    if os.getpgrp() in groups:
        raise RuntimeError("Refusing to terminate supervisor/shared process group")
    for group in groups:
        try:
            os.killpg(group, signal.SIGKILL)
        except ProcessLookupError:
            pass
    return {"owned_live_pids_before_cleanup": sorted(owned), "killed_owned_groups": sorted(groups)}


def command(name, args, timeout=15, permit_failure=False):
    with (EVIDENCE / (name + ".stdout")).open("xb") as stdout, (EVIDENCE / (name + ".stderr")).open("xb") as stderr:
        child = subprocess.Popen(args, cwd=CANDIDATE, env=ENV, stdin=subprocess.DEVNULL,
            stdout=stdout, stderr=stderr, start_new_session=True)
        try:
            code = child.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            os.killpg(child.pid, signal.SIGKILL); child.wait(timeout=2)
            raise RuntimeError("Owned metadata command deadline")
    RECORD["metadata_commands"].append({"name": name, "command": args,
        "deadline_seconds": timeout, "exit_code": code,
        "stdout_sha256": sha(EVIDENCE / (name + ".stdout")),
        "stderr_sha256": sha(EVIDENCE / (name + ".stderr"))})
    if code and not permit_failure:
        raise RuntimeError("Metadata prerequisite failed")
    return code, (EVIDENCE / (name + ".stdout")).read_text()


RECORD = {"started_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(), "status": "fail",
          "whole_deadline_seconds": 1200, "build_deadline_seconds": 300,
          "linux_phase_deadline_seconds": 600, "private_candidate": str(CANDIDATE),
          "maintained_source_mutations": 0, "live_publisher_acquisition": False,
          "hosted_provider_database_customer_calls": False, "current_checkout_acceptance_claimed": False,
          "composition": FREEZE["composition"], "metadata_commands": []}


def main():
    process, observed = None, {}
    started = time.monotonic()
    try:
        expected = {row["path"]: {"sha256": row["sha256"], "bytes": row["bytes"], "mode": row["copy_mode"]}
                    for row in FREEZE["source_manifest"]}
        RECORD["private_source_before"] = source_map(CANDIDATE)
        if RECORD["private_source_before"] != expected:
            raise RuntimeError("Private source changed before execution")
        if list(Path(ENV["DENO_DIR"]).iterdir()):
            raise RuntimeError("Initially empty exclusive Deno directory required")
        RECORD["initial_deno_file_count"] = 0
        RECORD["tool_sha256"] = {str(p): sha(p.resolve()) for p in (DENO, PYTHON, DOCKER, RUBY, Path(sys.executable))}
        if RECORD["tool_sha256"][str(DENO)] != "a371e0605be5039a91a079a802d66b22c124a42e31573e43136c93c2b362f1c0":
            raise RuntimeError("Pinned Deno bytes required")
        if RECORD["tool_sha256"][str(PYTHON)] != "69b35956b6a60fdcc0e7a11c062cbd89dd389caa8a3c862221feb56105f2a643":
            raise RuntimeError("Captured fixture Python bytes required")
        _, deno = command("deno-runtime", [str(DENO), "--version"])
        if not deno.startswith("deno 2.5.6 "):
            raise RuntimeError("Actual pinned Deno version required")
        _, python = command("fixture-python", [str(PYTHON), "-I", "-c",
            "import sys,json,importlib.metadata as m; print(json.dumps({'python':'.'.join(map(str,sys.version_info[:3])),'packages':{p:m.version(p) for p in ['Pillow','pypdf','pypdfium2','openpyxl','defusedxml','et-xmlfile']}}))"])
        actual = json.loads(python)
        if actual != {"python": "3.12.14", "packages": {"Pillow": "12.3.0", "pypdf": "6.19.0", "pypdfium2": "5.2.0", "openpyxl": "3.1.5", "defusedxml": "0.7.1", "et-xmlfile": "2.0.0"}}:
            raise RuntimeError("Exact fixture generator version metadata required")
        RECORD["fixture_generator_version_metadata"] = actual
        command("ruby-runtime", [str(RUBY), "--version"])
        _, socket = command("docker-socket", [str(DOCKER), "context", "inspect", "--format", "{{.Endpoints.docker.Host}}"])
        if not socket.strip().startswith("unix://"):
            raise RuntimeError("Local Unix Docker endpoint required")
        ENV["DOCKER_HOST"] = socket.strip()
        _, platform = command("docker-platform", [str(DOCKER), "info", "--format", "{{.OSType}}/{{.Architecture}}"])
        if platform.strip() not in ("linux/aarch64", "linux/arm64"):
            raise RuntimeError("Native Linux ARM64 daemon required")
        RECORD["docker_platform"] = platform.strip()
        command("pinned-base", [str(DOCKER), "image", "inspect",
            "python:3.12-slim-bookworm@sha256:392307d22300de8b5986851a12d9176dfc0fc073e65bf6523ebd7dcbeb23564e",
            "--format", "{{.Id}} {{json .RepoDigests}}"])
        args = [sys.executable, "-B", "scripts/qa/run_edge_ci.py", "--deno", str(DENO),
                "--decoder-python", str(PYTHON), "--wheel-source", FREEZE["wheel_source"],
                "--publisher-receipt", FREEZE["publisher_receipt_copy"], "--publisher-sha256", FREEZE["publisher_sha256"],
                "--metadata-directory", FREEZE["metadata_directory"], "--cache-dependencies", "--output", str(OUTPUT)]
        RECORD["command"] = args
        (EVIDENCE / "started.json").write_text(json.dumps(RECORD, indent=2) + "\n")
        with (EVIDENCE / "canonical.stdout").open("xb") as out, (EVIDENCE / "canonical.stderr").open("xb") as err:
            process = subprocess.Popen(args, cwd=CANDIDATE, env=ENV, stdin=subprocess.DEVNULL,
                stdout=out, stderr=err, start_new_session=True)
            RECORD["owned_canonical_pid"] = process.pid
            while process.poll() is None:
                table = process_table()
                for pid in descendants(table, process.pid):
                    if pid in table:
                        observed[pid] = table[pid]
                if time.monotonic() - started >= 1200:
                    RECORD["timed_out"] = True
                    RECORD["deadline_cleanup"] = terminate_owned(observed)
                    process.wait(timeout=2)
                    raise RuntimeError("Actual whole canonical deadline exceeded")
                time.sleep(1)
        RECORD["exit_code"] = process.returncode
        RECORD["observed_owned_processes"] = observed
        terminal = json.loads((OUTPUT / "validation.json").read_text())
        RECORD["canonical_validation"] = terminal
        if process.returncode != 0 or terminal.get("status") != "pass" or terminal.get("source_unchanged") is not True:
            raise RuntimeError("Complete source-stable canonical acceptance required")
        linux = json.loads((OUTPUT / "linux-decoder/validation.json").read_text())
        RECORD["new_image_id"] = linux["image_id"]
        if linux["image_id"] in ("sha256:057e01a1e1cec280a89696ac30949bc6ac4c86f422f273ef3976164fb795ef04",
                                "sha256:1804707ebbd146cfecd373da7bf2041457c9f7192b26540c41fa3d1955a38b96"):
            raise RuntimeError("Dated image substitution refused")
        code, installed = command("fresh-image-toolchain", [str(DOCKER), "run", "--rm", "--network", "none",
            "--read-only", "--security-opt", "no-new-privileges", "--cap-drop", "ALL", "--memory", "128m", "--cpus", "1", "--pids-limit", "16",
            linux["image_id"], "python", "-I", "-c",
            "import sys,json,importlib.metadata as m; print(json.dumps({'python':'.'.join(map(str,sys.version_info[:3])),'packages':{p:m.version(p) for p in ['Pillow','pypdf','pypdfium2','openpyxl','defusedxml','et-xmlfile']}}))"])
        if json.loads(installed) != actual:
            raise RuntimeError("Actual fresh Linux image toolchain does not match pinned identity")
        RECORD["fresh_image_toolchain"] = json.loads(installed)
        RECORD["status"] = "pass"
    except Exception as error:
        RECORD["error"] = str(error)
        if process is not None and process.poll() is None:
            RECORD["failure_cleanup"] = terminate_owned(observed)
            process.wait(timeout=2)
    finally:
        if observed:
            RECORD["remaining_owned_process_cleanup"] = terminate_owned(observed)
        start = OUTPUT / "linux-decoder/start.log"
        if start.exists():
            container = start.read_text().strip()
            if re.fullmatch(r"[0-9a-f]{64}", container):
                code, detail = command("owned-container-readback", [str(DOCKER), "inspect", "--format", "{{.Name}} {{.Config.Image}}", container], permit_failure=True)
                RECORD["supervisor_container_id"] = container
                RECORD["supervisor_absent_after_gate"] = code == 1 and any(("error: no such " + kind + ": " + container) in (EVIDENCE / "owned-container-readback.stderr").read_text().lower() for kind in ("object", "container"))
                if code == 0:
                    fields = detail.strip().split()
                    if len(fields) != 2 or not re.fullmatch(r"/collect_roster_decoder_[0-9a-f]{12}", fields[0]) or fields[1] != fields[0][1:] + ":qa":
                        raise RuntimeError("Refusing cleanup without exact owned container identity")
                    command("owned-container-failure-logs", [str(DOCKER), "logs", container], permit_failure=True)
                    command("owned-container-failure-cleanup", [str(DOCKER), "rm", "-f", container])
                    RECORD["status"] = "fail"
                    RECORD["error"] = "Maintained container cleanup was incomplete; owned fallback retained"
        RECORD["private_source_after"] = source_map(CANDIDATE)
        RECORD["private_source_unchanged"] = RECORD.get("private_source_before") == RECORD["private_source_after"]
        RECORD["root_source_after"] = maintained_source_map()
        original = json.loads((EVIDENCE / "maintained-source-before.json").read_text())
        RECORD["root_source_drift"] = {name: value for name, value in RECORD["root_source_after"].items()
                                       if value != original[name]}
        if not RECORD["private_source_unchanged"]:
            RECORD["status"] = "fail"
        RECORD["finished_at_utc"] = dt.datetime.now(dt.timezone.utc).isoformat()
        RECORD["elapsed_seconds"] = time.monotonic() - started
        for name in ("canonical.stdout", "canonical.stderr"):
            if (EVIDENCE / name).exists():
                RECORD[name + "_sha256"] = sha(EVIDENCE / name)
        (EVIDENCE / "execution-result.json").write_text(json.dumps(RECORD, indent=2) + "\n")
    print(json.dumps({k: RECORD.get(k) for k in ("status", "elapsed_seconds", "error", "private_source_unchanged", "root_source_drift", "new_image_id")}))
    return 0 if RECORD["status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
