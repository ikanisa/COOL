"""Root-owned, exact-hash seven-file promotion and bounded applied checks."""
from pathlib import Path
import datetime
import hashlib
import json
import os
import re
import signal
import stat
import subprocess
import time

ROOT = Path(__file__).resolve().parents[4]
OUT = Path(__file__).resolve().parent
PACKET = OUT.parent / "ai-dispatch-policy-implementation-batch1"
STAGE = ROOT / ".cache/ai-dispatch-policy-implementation-batch1/candidate/source"
DENO = ROOT / ".cache/roster-deno-2.5.6-20260929/deno"
CACHE = ROOT / ".cache/ai-dispatch-policy-implementation-batch1/attempt3/deno-dir"


def read(path):
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    try:
        before = os.fstat(fd)
        assert stat.S_ISREG(before.st_mode), path
        with os.fdopen(fd, "rb", closefd=False) as stream:
            data = stream.read()
        after = os.fstat(fd)
        assert (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns) == (
            after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns
        ), path
        named = path.lstat()
        assert (named.st_dev, named.st_ino) == (after.st_dev, after.st_ino), path
        return data
    finally:
        os.close(fd)


def digest(path):
    return hashlib.sha256(read(path)).hexdigest()


def save(name, obj):
    with (OUT / name).open("x") as stream:
        stream.write(json.dumps(obj, indent=2) + "\n")


def tree(base):
    return {str(p.relative_to(base)): digest(p) for p in sorted(base.rglob("*")) if p.is_file()}


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


assert digest(PACKET / "batch.json") == "da8b8e3692ccaf14224a75e99f803ce4ceb194afd5469ba48d789956232565f5"
assert digest(PACKET / "evidence-index.json") == "f90b86b4a6868bab67f0babc76b403af05f6220b67ef88adcaf96a1f712bf201"
assert digest(PACKET / "full-candidate.patch") == "920b476e03097439515b4f171f3c59827154c22e604c7ab818ce00414d51a9f1"
assert digest(PACKET / "proposal.json") == "bebd637d8a9bc41e13a0706b048bced774b2a989537dd6d608f7ef696fa49d27"
proposal = json.loads(read(PACKET / "proposal.json"))
index = json.loads(read(PACKET / "evidence-index.json"))
assert len(index["files"]) == 213
for row in index["files"]:
    path = ROOT / row["path"]
    assert path.resolve().is_relative_to(PACKET.resolve()), row["path"]
    assert len(read(path)) == row["bytes"] and digest(path) == row["sha256"], row["path"]
inputs = json.loads(read(PACKET / "source-before.json"))["files"]
assert len(inputs) == 22
for row in inputs:
    assert digest(ROOT / row["path"]) == row["sha256"], row["path"]
verification = json.loads(read(PACKET / "attempt3/verification.json"))
assert tree(STAGE) == verification["candidate_after"]
assert len(verification["candidate_after"]) == 25
assert tree(CACHE / "remote") == verification["remote_after"]
assert len(verification["remote_after"]) == 87
assert digest(DENO) == "a371e0605be5039a91a079a802d66b22c124a42e31573e43136c93c2b362f1c0"
assert verification["candidate-tests_summaries"] == [["213", "0", ""]]
assert re.findall(r"(\d+) passed \| (\d+) failed", read(PACKET / "attempt3/candidate-tests.stdout").decode()) == [("213", "0")]
assert all(p["exit_code"] == 0 for p in verification["phases"] if p["label"].startswith("candidate"))
old_test = (ROOT / ".cache/ai-dispatch-policy-implementation-batch1/old/source/supabase/functions/prepare-roster-import/handler_test.ts").read_text()
new_test = (STAGE / "supabase/functions/prepare-roster-import/handler_test.ts").read_text()
suffix = old_test[old_test.index("Deno.test("):].rstrip()
assert suffix in new_test
assert hashlib.sha256(suffix.encode()).hexdigest() == "b5d4faadb0359a8fe2711a1378c0a681df5849e9fe167f5427f72831c45677dd"
fixture = json.loads(read(PACKET / "integration-fixture-preservation-final.json"))
assert len(fixture["callbacks"]) == 6 and fixture["formatted_bodies_preserved"]
assert all(c["formatted_body_sha256"] == c["original_dedented_body_sha256"] for c in fixture["callbacks"])
changes = proposal["changed_files"]
assert len(changes) == 7
before = {}
for row in changes:
    name = row["path"]
    target = ROOT / name
    assert target.parent.resolve() == target.parent
    assert digest(STAGE / name) == row["candidate_sha256"]
    assert len(read(STAGE / name)) == row["candidate_bytes"]
    if row["base_sha256"] is None:
        assert not os.path.lexists(target), name
        before[name] = None
    else:
        assert digest(target) == row["base_sha256"], name
        before[name] = digest(target)
save("root-review.json", {
    "observed_at": now(), "status": "pass", "indexed_leaves": 213,
    "maintained_inputs": 22, "private_inputs": 25, "remote_cache_objects": 87,
    "full_patch_review": "Root read all 1552 lines before this exact-hash admission.",
    "original_handler_case_suffix_preserved": True, "fixture_callbacks_preserved": 6,
    "effective_configuration_boundary": proposal["raw_environment_limit"],
    "authorized_changes": changes, "whole_BE13_closed": False,
    "production_acceptance": False,
})

# Recheck the complete maintained closure immediately before the owned writes.
for row in inputs:
    assert digest(ROOT / row["path"]) == row["sha256"], row["path"]
applied = []
for row in changes:
    target = ROOT / row["path"]
    expected = row["base_sha256"]
    if expected is None:
        assert not os.path.lexists(target)
        mode = 0o644
    else:
        assert digest(target) == expected
        mode = stat.S_IMODE(target.stat().st_mode)
    temporary = target.with_name(target.name + ".root-ai-promotion-tmp")
    fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, mode)
    try:
        data = read(STAGE / row["path"])
        with os.fdopen(fd, "wb", closefd=False) as stream:
            stream.write(data)
            stream.flush()
            os.fsync(fd)
        if expected is None:
            assert not os.path.lexists(target)
        else:
            assert digest(target) == expected
        os.replace(temporary, target)
    finally:
        os.close(fd)
    assert digest(target) == row["candidate_sha256"]
    applied.append(row["path"])
save("promotion.json", {"observed_at": now(), "status": "applied_exact_reviewed_seven", "before": before, "applied": applied})

env = {"PATH": os.defpath, "DENO_DIR": str(CACHE), "DENO_NO_UPDATE_CHECK": "1", "NO_COLOR": "1"}
cache_before = tree(CACHE / "remote")
source_before = {name: digest(ROOT / name) for name in verification["candidate_after"]}
phases = []
for p in proposal["candidate_checks"]:
    if not p["label"].startswith("candidate"):
        continue
    started = time.monotonic()
    with (OUT / (p["label"] + ".stdout")).open("xb") as stdout, (OUT / (p["label"] + ".stderr")).open("xb") as stderr:
        process = subprocess.Popen(p["command"], cwd=ROOT, env=env, stdout=stdout, stderr=stderr, start_new_session=True)
        timed_out = False
        try:
            code = process.wait(timeout=120)
        except subprocess.TimeoutExpired:
            timed_out = True
            os.killpg(process.pid, signal.SIGKILL)
            code = process.wait(timeout=10)
    phases.append({"label": p["label"], "command": p["command"], "cwd": str(ROOT), "exit_code": code, "timed_out": timed_out, "deadline_seconds": 120, "seconds": time.monotonic() - started})
    print(p["label"], code, flush=True)
source_after = {name: digest(ROOT / name) for name in verification["candidate_after"]}
cache_after = tree(CACHE / "remote")
summary = re.findall(r"(\d+) passed \| (\d+) failed", (OUT / "candidate-tests.stdout").read_text())
passed = all(p["exit_code"] == 0 and not p["timed_out"] for p in phases) and source_before == source_after and cache_before == cache_after and summary == [("213", "0")]
save("applied-verification.json", {
    "observed_at": now(), "status": "pass" if passed else "fail", "phases": phases,
    "test_counts": summary, "source_before": source_before, "source_after": source_after,
    "source_unchanged_during_checks": source_before == source_after,
    "cache_unchanged": cache_before == cache_after,
    "real_linux_http_executed": False, "provider_calls": 0, "hosted_database_calls": 0,
    "whole_BE13_closed": False, "production_acceptance": False,
})
assert passed, "Applied checks failed; retain actual result and reviewed source for diagnosis."
snapshot = OUT / "source"
for name in source_after:
    target = snapshot / name
    target.parent.mkdir(parents=True, exist_ok=True)
    with target.open("xb") as stream:
        stream.write(read(ROOT / name))
files = []
for path in sorted(OUT.rglob("*")):
    if path.is_file():
        files.append({"path": str(path.relative_to(ROOT)), "bytes": path.stat().st_size, "sha256": digest(path)})
save("packet-files.json", {"status": "sealed", "scope": "Exact seven-file AI dispatch promotion and applied213/type/default-lint/format proof; broader BE13 and current combined backend remain open.", "files": files})
print(json.dumps({"status": "pass", "applied": len(applied), "tests": 213, "sealed_leaves": len(files)}))
