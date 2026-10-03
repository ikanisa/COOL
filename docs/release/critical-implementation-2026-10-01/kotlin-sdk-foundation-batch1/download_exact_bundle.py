#!/usr/bin/env python3
"""Authenticate one frozen official bundle; never extract or execute it."""
import base64, datetime, hashlib, json, os, shutil, signal, sys, time, urllib.request
from pathlib import Path
PACKET = Path(__file__).resolve().parent
FROZEN_HASH = "f5f191773eb51aeef483aab4718b7b89ba778be6732ced61db8a6274a8665459"
TARGET = Path("/Volumes/PRO-G40/Development/Codex-Candidates/COOL-ARC09/public-artifacts/flutter_macos_arm64_3.44.4-stable.zip")
PARTIAL = TARGET.with_suffix(TARGET.suffix + ".part")
TIMEOUT_SECONDS = 1800
RECEIPT = PACKET / "bundle-transfer-attempt1.json"
def utc():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()
def save(value):
    temp = RECEIPT.with_suffix(".json.tmp")
    temp.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")
    os.replace(temp, RECEIPT)
def expired(signum, frame):
    raise TimeoutError("fixed actual transfer/readback deadline expired")
raw = (PACKET / "metadata-freeze.json").read_bytes()
if hashlib.sha256(raw).hexdigest() != FROZEN_HASH:
    raise SystemExit("frozen metadata changed")
meta = json.loads(raw)
for name, identity in meta["files"].items():
    body = (PACKET / "public-origin" / name).read_bytes()
    if len(body) != identity["bytes"] or hashlib.sha256(body).hexdigest() != identity["sha256"]:
        raise SystemExit("frozen public metadata drift: " + name)
TARGET.parent.mkdir(parents=True, exist_ok=True)
if TARGET.exists() or PARTIAL.exists() or RECEIPT.exists():
    raise SystemExit("attempt destination already exists; no overwrite/resume")
free = shutil.disk_usage(TARGET.parent).free
if free < meta["expected_bytes"] * 2 + 1024 ** 3:
    raise SystemExit("insufficient checked space for fresh transfer")
start = time.monotonic()
result = {"schema_version": 1, "started_utc": utc(), "pid": os.getpid(),
    "timeout_seconds": TIMEOUT_SECONDS, "deadline_utc": (datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(seconds=TIMEOUT_SECONDS)).isoformat(),
    "frozen_metadata_sha256": FROZEN_HASH, "source_url": meta["archive_url"],
    "target": str(TARGET), "partial_path": str(PARTIAL), "free_bytes_at_start": free,
    "expected_bytes": meta["expected_bytes"], "expected_sha256": meta["expected_sha256"],
    "expected_generation": meta["expected_generation"], "bytes_received": 0,
    "state": "running", "archive_extracted": False, "sdk_executed": False,
    "scope": "Fresh official public bundle transfer and complete digest readback only; no extraction, source patches, SDK execution, cache reuse or acceptance."}
save(result)
signal.signal(signal.SIGALRM, expired)
signal.alarm(TIMEOUT_SECONDS)
try:
    request = urllib.request.Request(meta["archive_url"], headers={"User-Agent": "COOL-public-origin-audit/1", "Accept-Encoding": "identity"})
    sha = hashlib.sha256(); md5 = hashlib.md5(); last = start
    with urllib.request.urlopen(request, timeout=40) as response:
        result.update({"http_status": response.status, "final_url": response.geturl(), "response_headers": {k: response.headers.get(k) for k in ["Content-Length", "Content-Type", "ETag", "x-goog-generation", "x-goog-hash"]}})
        if response.status != 200 or response.geturl() != meta["archive_url"]:
            raise ValueError("unexpected HTTP status/redirect")
        if int(response.headers.get("Content-Length", "-1")) != meta["expected_bytes"]:
            raise ValueError("publisher length changed")
        if response.headers.get("x-goog-generation") != meta["expected_generation"]:
            raise ValueError("publisher generation changed")
        with PARTIAL.open("xb") as stream:
            while True:
                chunk = response.read(4 * 1024 * 1024)
                if not chunk: break
                if result["bytes_received"] + len(chunk) > meta["expected_bytes"]:
                    raise ValueError("response exceeds frozen exact size")
                stream.write(chunk); sha.update(chunk); md5.update(chunk)
                result["bytes_received"] += len(chunk)
                if time.monotonic() - last >= 20:
                    result.update({"last_progress_utc": utc(), "elapsed_seconds": round(time.monotonic() - start, 3)})
                    save(result); print("received", result["bytes_received"], "of", meta["expected_bytes"], flush=True); last = time.monotonic()
            stream.flush(); os.fsync(stream.fileno())
    if result["bytes_received"] != meta["expected_bytes"]:
        raise ValueError("truncated official response")
    result["stream_sha256"] = sha.hexdigest()
    result["stream_md5_base64"] = base64.b64encode(md5.digest()).decode()
    if sha.hexdigest() != meta["expected_sha256"] or result["stream_md5_base64"] != meta["expected_md5_base64"]:
        raise ValueError("official transfer digest mismatch")
    result["state"] = "complete_readback_running"; save(result)
    disk_sha = hashlib.sha256(); disk_md5 = hashlib.md5(); size = 0
    with PARTIAL.open("rb") as stream:
        while True:
            chunk = stream.read(8 * 1024 * 1024)
            if not chunk: break
            disk_sha.update(chunk); disk_md5.update(chunk); size += len(chunk)
    result.update({"readback_bytes": size, "readback_sha256": disk_sha.hexdigest(), "readback_md5_base64": base64.b64encode(disk_md5.digest()).decode()})
    if size != meta["expected_bytes"] or disk_sha.hexdigest() != meta["expected_sha256"] or result["readback_md5_base64"] != meta["expected_md5_base64"]:
        raise ValueError("complete filesystem readback digest mismatch")
    if TARGET.exists(): raise ValueError("target appeared during transfer")
    PARTIAL.rename(TARGET)
    result.update({"state": "authenticated", "passed": True, "finished_utc": utc(), "elapsed_seconds": round(time.monotonic() - start, 3), "regular_file_nlink": TARGET.stat().st_nlink})
except BaseException as error:
    result.update({"state": "failed", "passed": False, "error_type": type(error).__name__, "error": str(error), "finished_utc": utc(), "elapsed_seconds": round(time.monotonic() - start, 3), "partial_retained": PARTIAL.exists()})
    if PARTIAL.exists():
        result["partial_bytes"] = PARTIAL.stat().st_size
    save(result); print(json.dumps({k: result.get(k) for k in ["state", "error_type", "error", "bytes_received", "elapsed_seconds"]}), flush=True)
    sys.exit(2)
finally:
    signal.alarm(0)
save(result)
print(json.dumps({k: result.get(k) for k in ["state", "readback_bytes", "readback_sha256", "elapsed_seconds"]}), flush=True)
