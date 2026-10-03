#!/usr/bin/env python3
"""Independent sealed-artifact readback; no source or external operations."""
import hashlib
import json
from pathlib import Path
import stat

PACKET = Path(__file__).resolve().parent

def main():
    batch = json.loads((PACKET / "batch.json").read_text())
    checked = 0
    for name, expected in batch["artifacts"].items():
        path = PACKET / name
        st = path.lstat()
        assert stat.S_ISREG(st.st_mode) and st.st_nlink == 1 and not path.is_symlink(), name
        raw = path.read_bytes()
        assert len(raw) == expected["bytes"] and hashlib.sha256(raw).hexdigest() == expected["sha256"], name
        assert stat.S_IMODE(st.st_mode) == expected["mode"], name
        checked += 1
    expected_names = set(batch["artifacts"]) | {"batch.json", "SHA256SUMS"}
    actual_names = {str(p.relative_to(PACKET)) for p in PACKET.rglob("*") if p.is_file() or p.is_symlink()}
    assert actual_names == expected_names, actual_names ^ expected_names
    for line in (PACKET / "SHA256SUMS").read_text().splitlines():
        expected, name = line.split("  ", 1)
        assert hashlib.sha256((PACKET / name).read_bytes()).hexdigest() == expected, name
    assert checked == batch["artifact_count"]
    print(json.dumps({"verified_artifacts": checked, "checksum_rows": checked + 1,
                      "batch_sha256": hashlib.sha256((PACKET / "batch.json").read_bytes()).hexdigest()}))

if __name__ == "__main__":
    main()
