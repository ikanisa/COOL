#!/usr/bin/env python3
"""Separate-process termination at authenticated migration boundaries; synthetic data only."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

CUTS = ["migration_created", "migration_written", "migration_forced", "migration_directory_forced",
        "anchor_created", "anchor_written", "anchor_forced", "anchor_directory_forced",
        "pending_created", "pending_written", "pending_forced", "pending_directory_forced",
        "published", "published_directory_forced"]

def inventory(root: Path) -> dict[str, str]:
    return {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in root.iterdir()}

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--jar", required=True, type=Path)
    args = parser.parse_args()
    names = []
    records = []
    with tempfile.TemporaryDirectory(prefix="authenticated-restart-") as temporary:
        for cut in CUTS:
            outer = Path(temporary)/cut
            outer.mkdir()
            root = outer/"journal"
            root.mkdir()
            legacy = outer/"legacy.bin"
            original = b"synthetic retained ciphertext - not a real SMS or ledger"
            legacy.write_bytes(original)
            run = subprocess.run(["java", "-jar", str(args.jar), "crash", str(root), cut],
                                 capture_output=True, text=True, timeout=25)
            if run.returncode != 73:
                raise AssertionError((cut, "missing crash", run.returncode, run.stdout, run.stderr))
            before = inventory(root)
            mode = "blocked" if cut.endswith("_created") else "resume"
            reopened = subprocess.run(["java", "-jar", str(args.jar), mode, str(root)],
                                      capture_output=True, text=True, timeout=25)
            expected = "BLOCKED_RETAINED" if mode == "blocked" else "RESUMED"
            if reopened.returncode != 0 or reopened.stdout.strip() != expected:
                raise AssertionError((cut, reopened.returncode, reopened.stdout, reopened.stderr))
            after = inventory(root)
            if mode == "blocked" and before != after:
                raise AssertionError("recovery changed damaged evidence")
            for name, digest in before.items():
                if name.endswith(".pending") and mode == "resume":
                    if after.get(name.replace(".pending", ".snapshot")) != digest:
                        raise AssertionError("promotion changed ciphertext bytes")
                elif after.get(name) != digest:
                    raise AssertionError("existing evidence changed")
            if legacy.read_bytes() != original:
                raise AssertionError("legacy evidence modified")
            names.append(f"authenticated-process-kill-{cut}")
            records.append({"boundary": cut, "termination_exit": run.returncode,
                            "reopen_exit": reopened.returncode, "result": expected,
                            "legacy_sha256": hashlib.sha256(original).hexdigest(),
                            "journal_before": before, "journal_after": after})
    print(json.dumps({"status": "passed", "checks": len(names), "names": names,
                      "records": records, "scope": "JVM process termination; NOT Android or power loss"}))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
