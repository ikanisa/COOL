#!/usr/bin/env python3
"""Read-only local wheel/source/tool metadata; no installation or runtime gate."""
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[4]
PROOF = Path(__file__).resolve().parent
PRIOR = ROOT / "docs/release/critical-implementation-2026-10-01/decoder-dependency-batch1"
DOCKER = Path("/Volumes/PRO-G40/Applications/Docker.app/Contents/Resources/bin/docker")


def observe(path, maximum=128 * 1024 * 1024):
    path = Path(path)
    if not path.is_absolute() or any(p in (".", "..") for p in path.parts):
        raise ValueError("canonical_absolute_path_required")
    for parent in reversed(path.parents):
        if not stat.S_ISDIR(parent.lstat().st_mode):
            raise ValueError("unsafe_ancestor")
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    try:
        before = os.fstat(fd)
        if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1 or before.st_size > maximum:
            raise ValueError("unsafe_or_oversized_file")
        digest = hashlib.sha256()
        size = 0
        while chunk := os.read(fd, 1024 * 1024):
            size += len(chunk)
            if size > maximum or size > before.st_size:
                raise ValueError("file_changed")
            digest.update(chunk)
        after, named = os.fstat(fd), path.lstat()
        def identity(info):
            return (info.st_dev, info.st_ino, info.st_size, info.st_mode, info.st_mtime_ns, info.st_ctime_ns, info.st_nlink)
        if identity(before) != identity(after) or identity(before) != identity(named) or size != before.st_size:
            raise ValueError("file_changed")
        return {"path": str(path), "sha256": digest.hexdigest(), "size": size,
                "mode": stat.S_IMODE(before.st_mode), "mtime_ns": before.st_mtime_ns,
                "device": str(before.st_dev), "inode": str(before.st_ino)}
    finally:
        os.close(fd)


def run(label, command, environment, timeout=10):
    started = time.monotonic()
    try:
        completed = subprocess.run(command, env=environment, capture_output=True, text=True, timeout=timeout)
        status = {"command": command, "exit_code": completed.returncode,
                  "timeout_seconds": timeout, "deadline_expired": False,
                  "elapsed_seconds": time.monotonic() - started}
        out, err = completed.stdout, completed.stderr
    except subprocess.TimeoutExpired as error:
        status = {"command": command, "exit_code": None, "timeout_seconds": timeout,
                  "deadline_expired": True, "elapsed_seconds": time.monotonic() - started}
        out, err = error.stdout or b"", error.stderr or b""
        out = out.decode(errors="replace") if isinstance(out, bytes) else out
        err = err.decode(errors="replace") if isinstance(err, bytes) else err
    (PROOF / (label + ".stdout")).write_text(out)
    (PROOF / (label + ".stderr")).write_text(err)
    return status, out


def main():
    result = {"started_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
              "status": "read_only_inventory", "network_requests_performed": 0,
              "package_installs_or_runtime_acceptance_performed": False,
              "production_mutations": False, "provider_calls": 0, "wheels": [], "commands": {}}
    provenance_path = PRIOR / "wheel-provenance.json"
    result["prior_wheel_provenance"] = observe(provenance_path)
    provenance = json.loads(provenance_path.read_text())
    locked = {}
    lock = ROOT / "tools/roster-decoder/requirements.lock"
    for line in lock.read_text().splitlines():
        if line.startswith("#") or not line.strip():
            continue
        match = re.fullmatch(r"([A-Za-z0-9_-]+)==([^ ]+) --hash=sha256:([0-9a-f]{64})", line)
        if not match:
            raise ValueError("unexpected_lock_contract")
        locked[match[1].lower().replace("_", "-")] = (match[2], match[3])
    for row in provenance["wheels"]:
        metadata_path = PRIOR / "primary" / (row["package"].lower() + "-" + row["version"] + "-pypi.json")
        metadata = observe(metadata_path)
        release = json.loads(metadata_path.read_text())
        urls = [r for r in release["urls"] if r["filename"] == row["filename"]]
        actual = observe(Path(row["local_wheel"]))
        correct = (metadata["sha256"] == row["pypi_metadata_sha256"] and len(urls) == 1
                   and urls[0]["digests"]["sha256"] == actual["sha256"] == row["wheel_sha256"]
                   and urls[0]["size"] == actual["size"] == row["expected_size"]
                   and urls[0]["url"] == row["wheel_url"] and not urls[0]["yanked"]
                   and locked.get(row["package"].lower().replace("_", "-")) == (row["version"], actual["sha256"]))
        result["wheels"].append({"package": row["package"], "version": row["version"],
                                  "filename": row["filename"], "current_file": actual,
                                  "primary_metadata": metadata, "publisher_url": row["wheel_url"],
                                  "current_bytes_match_dated_primary_release_and_exact_lock": correct})
    result["current_linux_wheel_count"] = len(result["wheels"])
    result["current_linux_wheel_bytes"] = sum(r["current_file"]["size"] for r in result["wheels"])
    result["all_six_linux_wheels_verified"] = len(result["wheels"]) == len(locked) == 6 and all(
        r["current_bytes_match_dated_primary_release_and_exact_lock"] for r in result["wheels"])
    generator = json.loads((PRIOR / "fixture-generator-environment.json").read_text())
    result["macos_fixture_only_wheels"] = []
    for row in generator["macos_wheels_verified"]:
        actual = observe(Path(row["local_wheel"]))
        release = json.loads((PRIOR / "primary" / (row["package"] + "-" + row["version"] + "-pypi.json")).read_text())
        urls = [r for r in release["urls"] if r["filename"] == row["filename"]]
        result["macos_fixture_only_wheels"].append({"package": row["package"], "version": row["version"],
            "current_file": actual, "verified": len(urls) == 1 and actual["sha256"] == row["sha256"]
            == urls[0]["digests"]["sha256"] and actual["size"] == row["bytes"] == urls[0]["size"],
            "not_for_linux_container": True})
    paths = ["tools/roster-decoder/requirements.lock", "tools/roster-decoder/requirements.in",
             "tools/roster-decoder/Dockerfile", "tools/roster-decoder/decoder.py", "tools/roster-decoder/server.py",
             "tools/roster-decoder/test_dependency_security.py", "scripts/tests/verify_roster_decoder.py",
             "scripts/qa/run_edge_ci.py", "scripts/tests/edge_runner_contract_test.py", ".dvmrc",
             "supabase/functions/deno.lock"]
    result["current_affected_sources"] = {p: observe(ROOT / p) for p in paths}
    current_canonical = json.loads((ROOT / "docs/release/critical-implementation-2026-10-01/edge-current-integration-batch1/attempt2/canonical-batch.json").read_text())
    result["canonical_attempt2_source_count"] = len(current_canonical["source_before"])
    result["canonical_attempt2_current_input_drift"] = []
    for name, expected in current_canonical["source_before"].items():
        current = observe(ROOT / name)
        if current["sha256"] != expected:
            result["canonical_attempt2_current_input_drift"].append({"path": name, "dated_sha256": expected,
                                                                    "current_sha256": current["sha256"]})
    deno = ROOT / ".cache/roster-deno-2.5.6-20260929/deno"
    result["available_deno_binary"] = observe(deno)
    result["matches_canonical_attempt2_deno_binary"] = result["available_deno_binary"]["sha256"] == current_canonical["runtime_sha256_before"]
    python = ROOT / ".cache/decoder-dependency-batch1/fixture-generator-venv/bin/python"
    result["fixture_generator_interpreter_link"] = {"path": str(python), "target": str(python.resolve(strict=True))}
    result["fixture_generator_interpreter_actual_binary"] = observe(python.resolve(strict=True))
    environment = {key: os.environ[key] for key in ("HOME", "TMPDIR") if key in os.environ}
    environment.update(PATH=os.defpath, PYTHONDONTWRITEBYTECODE="1")
    command = [str(python), "-I", "-B", "-c", "import importlib.metadata as m,json,sys;print(json.dumps({'python':'.'.join(map(str,sys.version_info[:3])),'packages':{n:m.version(n)for n in ['Pillow','pypdf','pypdfium2','openpyxl','defusedxml','et-xmlfile']}}))"]
    step, out = run("fixture-generator-installed-metadata", command, environment)
    result["commands"]["fixture_generator_installed_metadata"] = step
    if step["exit_code"] == 0:
        result["fixture_generator_actual_installed_versions"] = json.loads(out)
        result["fixture_generator_matches_dated_verified_install"] = json.loads(out) == generator["installed_versions"]
    result["docker_cli"] = observe(DOCKER)
    step, out = run("local-docker-socket", [str(DOCKER), "context", "inspect", "--format", "{{.Endpoints.docker.Host}}"], environment)
    result["commands"]["local_docker_socket"] = step
    socket = out.strip()
    if step["exit_code"] == 0 and socket.startswith("unix://"):
        environment["DOCKER_HOST"] = socket
        result["local_unix_socket_observed"] = True
        step, out = run("local-docker-platform", [str(DOCKER), "info", "--format", "{{.OSType}}/{{.Architecture}}"], environment, 15)
        result["commands"]["local_docker_platform"] = step
        result["current_docker_platform"] = out.strip()
        images = {"pinned-python-base": "python:3.12-slim-bookworm@sha256:392307d22300de8b5986851a12d9176dfc0fc073e65bf6523ebd7dcbeb23564e",
                  "dated-verified-decoder-not-substitution": "sha256:057e01a1e1cec280a89696ac30949bc6ac4c86f422f273ef3976164fb795ef04"}
        for label, image in images.items():
            fields = '{"id":{{json .Id}},"repo_digests":{{json .RepoDigests}},"os":{{json .Os}},"architecture":{{json .Architecture}},"rootfs_layers":{{json .RootFS.Layers}}}'
            step, out = run(label, [str(DOCKER), "image", "inspect", image, "--format", fields], environment)
            result["commands"][label] = step
            if step["exit_code"] == 0:
                result.setdefault("actual_available_image_metadata", {})[label] = json.loads(out)
    result["finished_at_utc"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    (PROOF / "available-bytes-and-sources.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({key: result.get(key) for key in ("all_six_linux_wheels_verified", "current_linux_wheel_bytes",
        "canonical_attempt2_source_count", "canonical_attempt2_current_input_drift", "matches_canonical_attempt2_deno_binary",
        "fixture_generator_matches_dated_verified_install", "current_docker_platform", "actual_available_image_metadata")}))


if __name__ == "__main__":
    main()
