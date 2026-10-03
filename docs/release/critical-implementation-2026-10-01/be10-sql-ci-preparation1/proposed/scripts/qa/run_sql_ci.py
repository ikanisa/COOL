#!/usr/bin/env python3
"""Frozen ordinary-installer SQL recipe; hosted/runtime recovery are separate.

Requires an already acquired exact image. Creates only the original two owned,
networkless synthetic containers; never accepts a database URL or provider key.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import stat
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = "scripts/tests/fixtures/ordinary_installer_v1"
PYTHON_VERSION = "3.12.14"
IMAGE_ID = "sha256:35ebf7c6d3b77a430146b0a91974ed1fc14432b5741db4a3e41cd5f899b17f1a"
IMAGE_TAG = "public.ecr.aws/supabase/postgres:17.6.1.095"
PLATFORM_SHA = "1415f6c49a30dae485de238e9f0945b13350cacccf7ce6b26a52cb55ca95a99f"
PREDECESSOR_SHA = "0a9ca2a20bcdb5f3b75ca485eaf2c32f48f0095f4c014ea5d6990e5ac504d8ab"
OWNER_NAME = re.compile(r"collect_current_rehearsal_ordinary_(clean|populated)_[0-9a-f]{12}\Z")
HELPERS = (
    "scripts/tests/current_ordinary_installer_rehearsal.py",
    "scripts/tests/collect_current_release_upgrade_uat.py",
    "scripts/sql/receipt_transport_platform_prerequisites.sql",
    "scripts/sql/collect_recovery_source_catalog.sql",
)
IMAGE_FIELDS = '{"Id":{{json .Id}},"Os":{{json .Os}},"Architecture":{{json .Architecture}}}'
TARGET_FIELDS = ('{"Image":{{json .Image}},"Config":{"Labels":{{json .Config.Labels}}},'
                 '"HostConfig":{"NetworkMode":{{json .HostConfig.NetworkMode}},'
                 '"PortBindings":{{json .HostConfig.PortBindings}}}}')


class Refused(RuntimeError):
    pass


def sha(body: bytes) -> str:
    return hashlib.sha256(body).hexdigest()


def file_sha(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(65536), b""):
            digest.update(block)
    return digest.hexdigest()


def read_regular(path: Path, limit: int = 8 * 1024**2) -> bytes:
    info = path.lstat()
    if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1 or info.st_size > limit:
        raise Refused("SQL_INPUT_NOT_BOUNDED_REGULAR_FILE")
    return path.read_bytes()


def source_inventory(root: Path) -> dict[str, str]:
    migrations = sorted((root / "supabase/migrations").glob("*.sql"))
    if len(migrations) < 124:
        raise Refused("SQL_PREDECESSOR_PREFIX_MISSING")
    names = [p.name for p in migrations]
    if any(not re.fullmatch(r"(?:[0-9]{12}|[0-9]{14})_[A-Za-z0-9_]+\.sql", n) for n in names):
        raise Refused("SQL_MIGRATION_NAME_INVALID")
    if len({n.split("_", 1)[0] for n in names}) != len(names):
        raise Refused("SQL_MIGRATION_VERSION_DUPLICATE")
    paths = [*HELPERS, ".github/workflows/ci.yml", "scripts/qa/run_sql_ci.py",
             "scripts/tests/sql_ci_runner_test.py",
             *(f"{FIXTURES}/{n}" for n in ("manifest.json", "platform-bootstrap.sql", "predecessor.json")),
             *(str(p.relative_to(root)) for p in migrations)]
    return {rel: sha(read_regular(root / rel)) for rel in paths}


def fixture_lock(root: Path, pin: str, sources: dict[str, str]) -> dict:
    raw = read_regular(root / FIXTURES / "manifest.json", 65536)
    if not re.fullmatch(r"[0-9a-f]{64}", pin) or sha(raw) != pin:
        raise Refused("SQL_FIXTURE_WHOLE_LOCK_MISMATCH")
    lock = json.loads(raw)
    runtime = lock.get("runtime", {})
    expected = {"python": PYTHON_VERSION, "image_id": IMAGE_ID,
                "image_tag": IMAGE_TAG, "required_platform": "linux/arm64"}
    if lock.get("format") != "collect-ordinary-installer-fixture-v1" or any(
        runtime.get(key) != value for key, value in expected.items()
    ):
        raise Refused("SQL_RUNTIME_COHORT_UNREVIEWED")
    if lock.get("files") != {"platform-bootstrap.sql": PLATFORM_SHA, "predecessor.json": PREDECESSOR_SHA}:
        raise Refused("SQL_FIXTURE_COHORT_UNREVIEWED")
    for name, expected_sha in lock["files"].items():
        if sources.get(f"{FIXTURES}/{name}") != expected_sha:
            raise Refused("SQL_FIXTURE_BYTES_DRIFTED")
    if set(lock.get("helpers", {})) != set(HELPERS) or any(
        sources.get(rel) != pin for rel, pin in lock["helpers"].items()
    ):
        raise Refused("SQL_ORIGINAL_HELPER_BYTES_DRIFTED")
    cases = lock.get("expected_cases")
    if not isinstance(cases, list) or len(cases) != 37 or len(set(cases)) != 37 or not all(
        isinstance(name, str) and 1 <= len(name) <= 240 for name in cases
    ):
        raise Refused("SQL_ORIGINAL_CASE_MATRIX_INVALID")
    predecessor = json.loads(read_regular(root / FIXTURES / "predecessor.json", 32768))
    prefix = [Path(p).stem.split("_", 1)[0] for p in sources if p.startswith("supabase/migrations/")][:124]
    if prefix != [r["version"] for r in predecessor["migrations"]] or prefix[-1] != "20260906160000":
        raise Refused("SQL_HISTORICAL_PREFIX_DRIFTED")
    return lock


def docker_path(path: Path, pin: str) -> Path:
    if not path.is_absolute() or path.is_symlink() or not os.access(path, os.X_OK):
        raise Refused("SQL_DOCKER_EXACT_EXECUTABLE_REQUIRED")
    physical = path.resolve(strict=True)
    if not re.fullmatch(r"[0-9a-f]{64}", pin) or sha(read_regular(physical, 128 * 1024**2)) != pin:
        raise Refused("SQL_DOCKER_BYTES_DRIFTED")
    return physical


def local_socket(value: str) -> str:
    if not re.fullmatch(r"unix:///[-A-Za-z0-9_./]+", value) or "/../" in value or value.endswith("/.."):
        raise Refused("SQL_LOCAL_UNIX_DOCKER_ENDPOINT_REQUIRED")
    return value


def clean_env(output: Path, socket: str) -> dict[str, str]:
    home = output / "empty-home"
    config = output / "empty-docker-config"
    home.mkdir(mode=0o700)
    config.mkdir(mode=0o700)
    return {"PATH": "/usr/bin:/bin", "HOME": str(home), "DOCKER_CONFIG": str(config),
            "DOCKER_HOST": local_socket(socket), "LANG": "C.UTF-8", "LC_ALL": "C.UTF-8",
            "PYTHONDONTWRITEBYTECODE": "1", "PYTHONUTF8": "1", "PYTHONIOENCODING": "utf-8"}


def group_absent(pid: int) -> bool:
    try:
        os.killpg(pid, 0)
        return False
    except ProcessLookupError:
        return True


def run_process(argv: list[str], cwd: Path, env: dict, deadline: float,
                stdout: Path, stderr: Path, limit: int = 64 * 1024**2) -> dict:
    started = time.monotonic()
    if started >= deadline:
        raise Refused("SQL_PROCESS_DEADLINE_EXPIRED_BEFORE_SPAWN")
    timed_out = False
    overflow = False
    residual = False
    with stdout.open("xb") as out, stderr.open("xb") as err:
        child = subprocess.Popen(argv, cwd=cwd, env=env, stdin=subprocess.DEVNULL,
                                 stdout=out, stderr=err, start_new_session=True)
        try:
            while child.poll() is None:
                timed_out = time.monotonic() >= deadline
                overflow = stdout.stat().st_size + stderr.stat().st_size > limit
                if timed_out or overflow:
                    break
                time.sleep(min(.02, max(0, deadline - time.monotonic())))
            # Completion observed after the bound is still a timeout.
            timed_out = timed_out or time.monotonic() >= deadline
            residual = child.poll() is not None and not group_absent(child.pid)
        finally:
            if child.poll() is None or not group_absent(child.pid):
                try:
                    os.killpg(child.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
            child.wait(timeout=5)
        stop_deadline = time.monotonic() + 5
        while not group_absent(child.pid) and time.monotonic() < stop_deadline:
            time.sleep(.02)
        absent = group_absent(child.pid)
        overflow = overflow or stdout.stat().st_size + stderr.stat().st_size > limit
    return {"argv": argv, "pid": child.pid, "exit_code": child.returncode,
            "timed_out": timed_out, "output_overflow": overflow,
            "residual_group_required_stop": residual, "owned_process_group_absent": absent,
            "elapsed_seconds": time.monotonic() - started,
            "stdout_sha256": file_sha(stdout), "stderr_sha256": file_sha(stderr),
            "pass": child.returncode == 0 and not timed_out and not overflow and not residual and absent}


def image_matches(value: object) -> bool:
    return isinstance(value, list) and len(value) == 1 and isinstance(value[0], dict) and all(
        value[0].get(k) == v for k, v in {"Id": IMAGE_ID, "Os": "linux", "Architecture": "arm64"}.items()
    )


def owned_target(value: object, name: str) -> bool:
    return bool(OWNER_NAME.fullmatch(name) and isinstance(value, list) and len(value) == 1 and isinstance(value[0], dict)
                and value[0].get("Image") == IMAGE_ID
                and value[0].get("Config", {}).get("Labels", {}).get("collect.rehearsal.owner") == name
                and value[0].get("HostConfig", {}).get("NetworkMode") == "none"
                and not value[0].get("HostConfig", {}).get("PortBindings"))


def acceptance(result: dict, lock: dict, before: dict[str, str]) -> bool:
    migrations = []
    for rel, pin in before.items():
        if rel.startswith("supabase/migrations/"):
            version, name = Path(rel).stem.split("_", 1)
            migrations.append({"path": rel, "version": version, "name": name, "sha256": pin})
    return (result.get("status") == "pass" and result.get("all_task_containers_removed") is True
            and result.get("source_inventory") == migrations
            and result.get("cases") == [{"name": name, "status": "pass"} for name in lock["expected_cases"]]
            and all(result.get(k) is False for k in ("hosted_called", "provider_called", "source_rows_copied",
                                                     "shared_database_written", "managed_hosted_owner_parity")))


def cleanup_owned(entries: list[dict], metadata, deadline: float) -> tuple[list[dict], bool]:
    if len(entries) > 2 or len({x["name"] for x in entries}) != len(entries):
        raise Refused("SQL_OWNED_TARGET_REGISTRY_INVALID")
    observations = []
    fallback = False
    for i, entry in enumerate(entries):
        name = entry["name"]
        if not OWNER_NAME.fullmatch(name) or entry["image_id"] != IMAGE_ID:
            raise Refused("SQL_OWNED_TARGET_IDENTITY_INVALID")
        inspect = ["container", "inspect", name, "--format", TARGET_FIELDS]
        result, text, error = metadata(f"cleanup-{i}-inspect", inspect, deadline, (0, 1))
        missing = lambda value: any(message in value.lower() for message in (
            "no such container: " + name, "no such object: " + name))
        absent = result["exit_code"] == 1 and missing(error)
        if result["exit_code"] == 0:
            if not owned_target([json.loads(text)], name):
                raise Refused("SQL_REFUSED_CLEANUP_OF_UNBOUND_TARGET")
            metadata(f"cleanup-{i}-remove", ["rm", "--force", "--volumes", name], deadline)
            check, _, error = metadata(f"cleanup-{i}-verify", inspect, deadline, (1,))
            absent = check["exit_code"] == 1 and missing(error)
            fallback = True
        observations.append({"name": name, "verified_absent": absent})
        if not absent:
            raise Refused("SQL_OWNED_TARGET_ABSENCE_UNPROVED")
    return observations, fallback


CHILD = r'''import hashlib,importlib,json,os,sys,time
from pathlib import Path
config=Path(sys.argv[1]);raw=config.read_bytes()
assert hashlib.sha256(raw).hexdigest()==sys.argv[2], 'Frozen child configuration changed'
c=json.loads(raw);root=Path(c['candidate'])
for rel,pin in c['source_before'].items():
 assert hashlib.sha256((root/rel).read_bytes()).hexdigest()==pin, 'Captured source changed'
sys.path.insert(0,str(root/'scripts/tests'))
replay=importlib.import_module('collect_current_release_upgrade_uat')
replay.DOCKER=c['docker'];replay.IMAGE=c['image_id'];replay.HOSTED=root/c['predecessor']
sql=(root/c['platform']).read_bytes()
assert hashlib.sha256(sql).hexdigest()==c['platform_sha256']
replay.platform_shape=lambda:(sql.decode(),c['platform_provenance'])
original_command=replay.command
def checked_command(args,*a,**kw):
 assert time.monotonic()<c['execution_deadline'], 'Execution deadline reached'
 assert args[0]==c['docker'], 'Only the bound Docker executable is admitted'
 path=Path(c['docker']);assert path.stat().st_size<=128*1024**2, 'Docker exceeds bound'
 assert hashlib.sha256(path.read_bytes()).hexdigest()==c['docker_sha256'], 'Docker bytes drifted'
 return original_command(args,*a,**kw)
replay.command=checked_command
original_init=replay.Target.__init__
def register(self,*args,**kwargs):
 original_init(self,*args,**kwargs)
 with open(c['owned'],'a') as stream:
  stream.write(json.dumps({'name':self.name,'phase':self.phase,'image_id':replay.IMAGE_ID})+'\n')
  stream.flush();os.fsync(stream.fileno())
replay.Target.__init__=register
runner=importlib.import_module('current_ordinary_installer_rehearsal')
sys.argv=[runner.__file__,'--output',c['report']]
runner.main()
'''


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, allow_abbrev=False)
    parser.add_argument("--docker", type=Path, required=True)
    parser.add_argument("--docker-sha256", required=True)
    parser.add_argument("--docker-host", required=True)
    parser.add_argument("--fixture-lock-sha256", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    if output.exists() or not output.is_relative_to(ROOT / ".cache"):
        parser.error("Fresh repository-contained .cache output is required")
    output.mkdir(mode=0o700, parents=True)
    start = time.monotonic()
    whole = start + 600
    execution = start + 540
    report = {"status": "fail", "scope": "ordinary local synthetic clean/populated SQL only",
              "started_at": dt.datetime.now(dt.timezone.utc).isoformat(),
              "whole_deadline_seconds": 600, "execution_budget_seconds": 540, "cleanup_budget_seconds": 60,
              "source_mutations": False, "hosted_or_provider_calls": False, "image_acquisition_performed": False,
              "current_SQL_executed": False, "full_BE10_closed": False, "commands": [], "cleanup": []}
    before = None
    docker = env = None
    candidate = output / "source"

    def metadata(label: str, tail: list[str], deadline: float, accept: tuple[int, ...] = (0,)):
        docker_path(docker, args.docker_sha256)
        result = run_process([str(docker), *tail], ROOT, env, min(time.monotonic() + 15, deadline),
                             output / (label + ".stdout"), output / (label + ".stderr"), 1024**2)
        report["commands"].append(result)
        if (result["exit_code"] not in accept or result["timed_out"] or result["output_overflow"]
                or result["residual_group_required_stop"] or not result["owned_process_group_absent"]):
            raise Refused("SQL_DOCKER_METADATA_FAILED")
        return result, (output / (label + ".stdout")).read_text(), (output / (label + ".stderr")).read_text()

    try:
        if ".".join(map(str, sys.version_info[:3])) != PYTHON_VERSION:
            raise Refused("SQL_PINNED_PYTHON_REQUIRED")
        before = source_inventory(ROOT)
        lock = fixture_lock(ROOT, args.fixture_lock_sha256, before)
        docker = docker_path(args.docker, args.docker_sha256)
        env = clean_env(output, args.docker_host)
        report.update(source_before=before, fixture_lock_sha256=args.fixture_lock_sha256,
                      runtime={"python": PYTHON_VERSION, "python_executable": sys.executable,
                               "python_executable_sha256": file_sha(Path(sys.executable).resolve()),
                               "docker": str(docker), "docker_sha256": args.docker_sha256,
                               "docker_host": env["DOCKER_HOST"], "image_id": IMAGE_ID,
                               "required_platform": "linux/arm64", "prior37_platform_observation": False})
        for rel, pin in before.items():
            body = read_regular(ROOT / rel)
            if sha(body) != pin:
                raise Refused("SQL_SOURCE_DRIFT_BEFORE_COPY")
            dest = candidate / rel
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(body)
        if source_inventory(candidate) != before or source_inventory(ROOT) != before:
            raise Refused("SQL_SOURCE_DRIFT_AFTER_COPY")
        _, text, _ = metadata("image-inspect", ["image", "inspect", IMAGE_ID, "--format", IMAGE_FIELDS], execution)
        if not image_matches([json.loads(text)]):
            raise Refused("SQL_EXACT_IMAGE_OR_PLATFORM_MISMATCH")
        config = {"candidate": str(candidate), "docker": str(docker), "docker_sha256": args.docker_sha256,
                  "image_id": IMAGE_ID, "source_before": before, "execution_deadline": execution,
                  "platform": f"{FIXTURES}/platform-bootstrap.sql", "platform_sha256": PLATFORM_SHA,
                  "predecessor": f"{FIXTURES}/predecessor.json", "platform_provenance": lock["platform_provenance"],
                  "owned": str(output / "owned-targets.jsonl"),
                  "report": str(candidate / "docs/release/ordinary-sql-ci")}
        raw = (json.dumps(config, indent=2) + "\n").encode()
        (output / "child-config.json").write_bytes(raw)
        (output / "child.py").write_text(CHILD)
        report["current_SQL_executed"] = None
        child = run_process([sys.executable, "-B", str(output / "child.py"),
                             str(output / "child-config.json"), sha(raw)], candidate, env, execution,
                            output / "rehearsal.stdout", output / "rehearsal.stderr")
        report["commands"].append(child)
        result = json.loads(read_regular(Path(config["report"]) / "result.json", 32 * 1024**2))
        report.update(current_SQL_executed=any(p.get("migrations") for p in result.get("phases", {}).values()),
                      actual_case_count=len(result.get("cases", [])),
                      rehearsal_result_sha256=sha((Path(config["report"]) / "result.json").read_bytes()))
        if not child["pass"] or not acceptance(result, lock, before):
            raise Refused("SQL_COMPLETE_ORIGINAL_REHEARSAL_FAILED")
        report["status"] = "pass"
    except (Exception, KeyboardInterrupt):
        # Never echo inherited inputs, Docker exception text or credential values.
        report["failure_code"] = "SQL_RECIPE_FAILED_INSPECT_OWNED_EVIDENCE"
    finally:
        try:
            if docker is not None:
                docker_path(docker, args.docker_sha256)
            owned = output / "owned-targets.jsonl"
            if owned.exists() and docker is not None and env is not None:
                entries = [json.loads(line) for line in read_regular(owned, 4096).decode().splitlines()]
                report["cleanup"], fallback = cleanup_owned(entries, metadata, whole)
                if fallback:
                    report.update(status="fail", cleanup_fallback_required=True)
            if before is not None:
                report["source_after"] = source_inventory(ROOT)
                report["captured_source_after"] = source_inventory(candidate)
                report["source_unchanged"] = before == report["source_after"] == report["captured_source_after"]
                if not report["source_unchanged"]:
                    report["status"] = "fail"
            if report["status"] == "pass" and (len(report["cleanup"]) != 2 or time.monotonic() >= whole):
                report["status"] = "fail"
        except (Exception, KeyboardInterrupt):
            report.update(status="fail", cleanup_or_source_refused=True)
        report.update(elapsed_seconds=time.monotonic() - start,
                      completed_at=dt.datetime.now(dt.timezone.utc).isoformat())
        (output / "validation.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({k: report.get(k) for k in ("status", "actual_case_count", "current_SQL_executed", "source_unchanged")}))
    return 0 if report["status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
