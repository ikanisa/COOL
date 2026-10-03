#!/usr/bin/env python3
"""Prepare physical consumer copies; never modify the maintained checkout."""
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import stat

ROOT = Path(__file__).resolve().parents[4]
PACKET = Path(__file__).resolve().parent
PRIOR = PACKET.parent / "successor-gateway-inventory-batch1"

def sha(raw):
    return hashlib.sha256(raw).hexdigest()

def dump(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")

def identity(st):
    return [st.st_dev, st.st_ino, stat.S_IMODE(st.st_mode), st.st_size,
            st.st_mtime_ns, st.st_ctime_ns, st.st_nlink]

def read(path):
    if any(p.is_symlink() for p in (path, *path.parents)):
        raise ValueError(f"symlink refused: {path}")
    before = path.stat()
    if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1:
        raise ValueError(f"not a unique regular file: {path}")
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    try:
        opened = os.fstat(fd)
        if identity(before) != identity(opened):
            raise ValueError(f"source changed before read: {path}")
        with os.fdopen(fd, "rb", closefd=False) as handle:
            raw = handle.read()
        if identity(opened) != identity(os.fstat(fd)):
            raise ValueError(f"source changed during read: {path}")
    finally:
        os.close(fd)
    if identity(before) != identity(path.stat()):
        raise ValueError(f"source path replaced: {path}")
    return raw, {"sha256": sha(raw), "bytes": len(raw), "mode": stat.S_IMODE(before.st_mode),
                 "identity": identity(before)}

def main():
    prior = json.loads((PRIOR / "batch.json").read_text())
    prior_checks = {}
    for name, expected in prior["artifacts"].items():
        raw, facts = read(PRIOR / name)
        assert all(facts[k] == expected[k] for k in ("sha256", "bytes", "mode")), name
        prior_checks[name] = facts
    assert len(prior_checks) == prior["artifact_count"] == 36
    dump(PACKET / "prior-packet-readback.json", {
        "batch_sha256": sha((PRIOR / "batch.json").read_bytes()),
        "verified_artifact_count": len(prior_checks), "artifacts": prior_checks})

    explicit = {
        "Makefile", ".supabase-cli-version", ".dvmrc", "supabase/config.toml",
        "scripts/edge_function_inventory.rb", "scripts/edge_function_inventory.sh",
        "scripts/tests/edge_function_inventory_test.rb",
        "scripts/supabase_production_readiness.sh",
        "scripts/tests/supabase_delivery_contract_test.py",
        "scripts/supabase_deploy.sh", "scripts/supabase_cli_helpers.sh",
        "scripts/load_dotenv_strict.sh", "scripts/qa/backend_release_delivery.py",
        "scripts/qa/collect_release_candidate.py", "scripts/supabase_schema_inventory.sh",
        "scripts/audits/collect_index_inventory.rb", "scripts/supabase_advisors_gate.sh",
        "scripts/supabase_advisors_warning_inventory.sh", "scripts/collect_linked_uat.sh",
        "scripts/rwanda_momo_readiness_uat.sql", "scripts/collect_admin_security_uat.sh",
    }
    source_inputs = json.loads((PRIOR / "readback.json").read_text())["source_before"]
    selected = explicit | set(source_inputs) | {
        str(p.relative_to(ROOT)) for directory in ("contracts", "supabase/functions", "supabase/migrations")
        for p in (ROOT / directory).rglob("*") if p.is_file() or p.is_symlink()
    }
    before, copies = {}, {"baseline": {}, "candidate": {}}
    for name in sorted(selected):
        raw, facts = read(ROOT / name)
        before[name] = facts
        for stage in copies:
            target = PACKET / stage / "source" / name
            target.parent.mkdir(parents=True, exist_ok=True)
            with target.open("xb") as handle:
                handle.write(raw)
            target.chmod(facts["mode"])
            _, copied = read(target)
            assert (copied["identity"][0:2] != facts["identity"][0:2]
                    and all(copied[k] == facts[k] for k in ("sha256", "bytes", "mode"))), name
            copies[stage][name] = copied
    after = {name: read(ROOT / name)[1] for name in sorted(selected)}
    assert before == after, "maintained source changed during private copy"
    compared = {name: {"same_bytes": before[name]["sha256"] == facts["sha256"],
                       "same_mode": before[name]["mode"] == facts["mode"]}
                for name, facts in source_inputs.items() if name in before}
    assert all(v["same_bytes"] and v["same_mode"] for v in compared.values()), compared
    fixtures = [str(p) for p in json.loads((PRIOR / "readback.json").read_text())["declared_fixture_imports"]]
    fixture_status = {name: (ROOT / "supabase/functions/collect-receipt-successor-gateway" / name).exists()
                      for name in fixtures}
    dump(PACKET / "source-before.json", before)
    dump(PACKET / "copy-readback.json", copies)
    dump(PACKET / "source-after-copy.json", after)
    dump(PACKET / "preparation.json", {
        "prepared_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "maintained_input_count": len(before), "copied_stage_count": 2,
        "compared_prior_source_inputs": compared,
        "source_entries": sorted(p.parent.name for p in (ROOT / "supabase/functions").glob("*/index.ts")),
        "missing_declared_fixtures": fixture_status,
        "source_only": True, "handler_tests_executed": False,
        "maintained_writes": 0, "network_or_hosted_operations": False})
    print(json.dumps({"copied_maintained_inputs": len(before), "source_entries": len(list((ROOT / "supabase/functions").glob("*/index.ts"))),
                      "missing_fixtures": sum(not v for v in fixture_status.values())}))

if __name__ == "__main__":
    main()
