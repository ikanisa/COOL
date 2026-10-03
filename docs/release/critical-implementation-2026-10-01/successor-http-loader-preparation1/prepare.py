#!/usr/bin/env python3
"""Prepare an exact thirteenth literal HTTP loader; execute no Edge code."""
import datetime as dt
import difflib
import hashlib
import json
import os
from pathlib import Path
import re
import stat

ROOT = Path(__file__).resolve().parents[4]
OUT = Path(__file__).resolve().parent
QA = "scripts/qa/edge_http_runtime_uat.ts"
BASE = "27fcd434f5a4c5c30d298c1df2e1e059c22e206e82ec42e6a84523f9c12293c9"
SUCCESSOR = "collect-receipt-successor-gateway"
REGISTRATION = '''  "collect-receipt-successor-gateway": () =>
    import("../../supabase/functions/collect-receipt-successor-gateway/index.ts"),
'''
BRANCH = '''    if (slug === "collect-receipt-successor-gateway") {
      // The successor wire has its own audience/family and includes a false
      // send-authority field even in schema/method refusals. These unsigned
      // presence checks must stop before key lookup or any successor RPC.
      const body = JSON.stringify({
        contract_version: 1,
        protocol_family: "receipt_successor",
        audience: "collect-receipt-successor-gateway",
        action: "dispatch_grant",
        device_id: userId,
        request_id: crypto.randomUUID(),
        issued_at: new Date().toISOString(),
        payload: {},
      });
      for (const method of ["OPTIONS", "PUT"]) {
        const refusal = await request(
          slug,
          `${slug}: successor protocol refuses ${method}`,
          { method },
        );
        check(
          refusal.label,
          refusal.http_status === 405 && refusal.cors === null &&
            refusal.no_store && refusal.dependencies.length === 0 &&
            JSON.stringify(refusal.response) === JSON.stringify({
              ok: false,
              code: "GATEWAY_POST_REQUIRED",
              send_authority: false,
            }),
          refusal,
        );
      }
      for (const [label, requestBody, headers] of [
        ["empty unsigned envelope", "{}", {}],
        ["unsigned successor envelope", body, {}],
        ["bearer cannot replace successor signature", body, {
          authorization: "Bearer qa-invalid",
        }],
        ["malformed successor signature", body, {
          "X-Collect-Gateway-Key-Id": "a".repeat(64),
          "X-Collect-Gateway-Signature": btoa("malformed"),
        }],
      ] as Array<[string, string, Record<string, string>]>) {
        const refusal = await request(slug, `${slug}: ${label}`, {
          body: requestBody,
          headers,
        });
        check(
          refusal.label,
          refusal.http_status === 400 && refusal.cors === null &&
            refusal.no_store && refusal.dependencies.length === 0 &&
            JSON.stringify(refusal.response) === JSON.stringify({
              ok: false,
              code: "GATEWAY_REQUEST_INVALID",
              send_authority: false,
            }),
          refusal,
        );
      }
      continue;
    }
'''

def sha(raw):
    return hashlib.sha256(raw).hexdigest()

def dump(name, value):
    (OUT / name).write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")

def identity(st):
    return [st.st_dev, st.st_ino, stat.S_IMODE(st.st_mode), st.st_size,
            st.st_mtime_ns, st.st_ctime_ns, st.st_nlink]

def read(path):
    if any(p.is_symlink() for p in (path, *path.parents)):
        raise ValueError(f"symlink refused: {path}")
    before = path.lstat()
    assert stat.S_ISREG(before.st_mode) and before.st_nlink == 1, path
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    try:
        opened = os.fstat(fd)
        assert identity(opened) == identity(before), path
        with os.fdopen(fd, "rb", closefd=False) as f:
            raw = f.read()
        assert identity(os.fstat(fd)) == identity(opened), path
    finally:
        os.close(fd)
    assert identity(path.lstat()) == identity(before), path
    return raw, {"sha256": sha(raw), "bytes": len(raw), "mode": stat.S_IMODE(before.st_mode),
                 "identity": identity(before)}

def loader_names(text):
    block = text.split("const entrypointLoaders:", 1)[1].split("\n};", 1)[0]
    names = re.findall(r'^  "([^"]+)":', block, re.M)
    imports = re.findall(r'import\("\.\./\.\./supabase/functions/([^/]+)/index\.ts"\)', block)
    assert len(names) == len(set(names)) and names == imports
    return sorted(names)

def main():
    selected = {QA, "scripts/qa/run_edge_unit_tests.py", "scripts/qa/run_edge_http_uat.py",
                "scripts/qa/run_edge_ci.py", "scripts/tests/edge_runner_contract_test.py",
                "scripts/tests/play_integrity_handler_test.ts", "supabase/config.toml",
                "contracts/edge-functions.json", "supabase/functions/deno.lock", ".dvmrc"}
    selected |= {str(p.relative_to(ROOT)) for p in (ROOT / "supabase/functions").rglob("*.ts")}
    before, copied = {}, {}
    for name in sorted(selected):
        raw, facts = read(ROOT / name)
        before[name] = facts
        target = OUT / "inputs" / name
        target.parent.mkdir(parents=True, exist_ok=True)
        with target.open("xb") as handle:
            handle.write(raw)
        target.chmod(facts["mode"])
        _, copied[name] = read(target)
        assert all(copied[name][k] == facts[k] for k in ("sha256", "bytes", "mode"))
        assert copied[name]["identity"][:2] != facts["identity"][:2]
    raw = read(ROOT / QA)[0]
    assert sha(raw) == BASE, "QA changed before candidate preparation"
    old = raw.decode()
    registration_anchor = '  "collect-receipt-supervisor": () =>\n'
    branch_anchor = '    if (slug === "collect-android-gateway" || slug === "collect-receipt-supervisor") {\n'
    assert old.count(registration_anchor) == 1 and old.count(branch_anchor) == 1
    new = old.replace(registration_anchor, REGISTRATION + registration_anchor, 1)
    new = new.replace(branch_anchor, BRANCH + branch_anchor, 1)
    # Removing only the two added blocks recovers the entire original file,
    # including every original suite, assertion, parity gate and cleanup path.
    assert new.replace(REGISTRATION, "", 1).replace(BRANCH, "", 1) == old
    target = OUT / "candidate/source" / QA
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(new.encode())
    target.chmod(before[QA]["mode"])
    candidate = read(target)[1]
    (OUT / "registration-insertion.txt").write_text(REGISTRATION)
    (OUT / "refusal-branch-insertion.txt").write_text(BRANCH)
    patch = "diff --git a/" + QA + " b/" + QA + "\n"
    patch += ''.join(difflib.unified_diff(old.splitlines(keepends=True), new.splitlines(keepends=True),
                                        fromfile="a/" + QA, tofile="b/" + QA))
    (OUT / "full-candidate.patch").write_text(patch)
    after = {name: read(ROOT / name)[1] for name in selected}
    assert before == after, "maintained source changed during candidate capture"
    source_names = sorted(p.parent.name for p in (ROOT / "supabase/functions").glob("*/index.ts"))
    config_names = sorted(re.findall(r'^\[functions\.([^\]]+)\]', (OUT / "inputs/supabase/config.toml").read_text(), re.M))
    manifest_names = sorted(row["name"] for row in json.loads((OUT / "inputs/contracts/edge-functions.json").read_text())["functions"])
    current_loaders, candidate_loaders = loader_names(old), loader_names(new)
    assert len(current_loaders) == 12 and len(candidate_loaders) == 13
    assert source_names == config_names == manifest_names == candidate_loaders
    assert set(candidate_loaders) - set(current_loaders) == {SUCCESSOR}
    gateway_test = (OUT / "inputs/supabase/functions" / SUCCESSOR / "handler_test.ts").read_text()
    fixture_names = sorted(set(re.findall(r'"(\./fixtures/[^"\n]+)"', gateway_test)))
    fixture_status = {name: {"exists": (ROOT / "supabase/functions" / SUCCESSOR / name).exists(),
                             "symlink": (ROOT / "supabase/functions" / SUCCESSOR / name).is_symlink()}
                      for name in fixture_names}
    assert len(fixture_status) == 10 and all(not row["exists"] and not row["symlink"] for row in fixture_status.values())
    function_tests = sorted(str(p.relative_to(ROOT)) for p in (ROOT / "supabase/functions").rglob("*.ts")
                            if p.name.endswith("_test.ts") and str(p.relative_to(ROOT)) != "supabase/functions/_shared/roster_decoder_integration_test.ts")
    units = function_tests + ["scripts/tests/play_integrity_handler_test.ts"]
    assert "supabase/functions/" + SUCCESSOR + "/handler_test.ts" in units
    dump("source-before.json", before)
    dump("copy-readback.json", copied)
    dump("source-after.json", after)
    dump("preservation.json", {
        "entire_original_file_restored_after_removing_only_two_insertions": True,
        "original_file_sha256": BASE,
        "restored_file_sha256": sha(new.replace(REGISTRATION, "", 1).replace(BRANCH, "", 1).encode()),
        "original_suites_assertions_parity_failures_and_start_once_cleanup_bytes_preserved": True,
        "unit_and_canonical_runner_bytes_unchanged": True,
        "additional_HTTP_runtime_assertions_planned_not_executed": 6,
    })
    dump("current-discovery.json", {
        "source_endpoints": source_names, "config_endpoints": config_names, "manifest_endpoints": manifest_names,
        "current_literal_loaders": current_loaders, "candidate_literal_loaders": candidate_loaders,
        "missing_successor_fixtures": fixture_status,
        "declared_successor_test_count": len(re.findall(r'Deno\.test\(', gateway_test)),
        "declared_tests_executed": False, "unit_files_dynamically_discovered": units,
        "current_unit_entryfile_count": len(units),
        "Linux_roster_integration_allocation_preserved": "supabase/functions/_shared/roster_decoder_integration_test.ts",
        "current_TS_input_count": sum(name.startswith("supabase/functions/") and name.endswith(".ts") for name in before),
        "no_unit_registration_change_required": True,
    })
    dump("proposal.json", {
        "prepared_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "status": "private_one_file_preparation_not_promoted_not_executed",
        "base": {"path": str(ROOT / QA), **before[QA]},
        "candidate": {"path": str(target), **candidate},
        "patch": {"path": str(OUT / "full-candidate.patch"), "sha256": sha(patch.encode()), "lines": len(patch.splitlines())},
        "changed_paths": [QA], "input_count": len(before),
        "preferred_strategy": "Exact thirteenth literal registration retains frozen SDK redirect alias graph binding and exact source/config parity",
        "dynamic_unit_discovery": "Already includes successor; do not add an exclude/filter/fallback or hide its missing imports",
        "planned_refusal_cases": ["OPTIONS405", "PUT405", "empty JSON400", "unsigned valid namespace400", "bearer-only400", "malformed dedicated signature400"],
        "case_invariants": "Exact refusal JSON includes send_authority:false, no CORS, no-store and zero dependency requests before key lookup; provider denial/start-once/cleanup unchanged",
        "type_or_Deno_runtime_execution": False, "handler_SQL_or_native_execution": False,
        "hosted_or_provider_operations": False, "maintained_source_writes": 0,
        "real_missing_fixture_creation": False,
        "blocking_dependencies": [
            "Root Edge owner completes frozen140 cohort and releases current QA write boundary",
            "Genuine ten declared observed fixtures with immutable source/origin/completion/hash proof",
            "Root full-patch review and current exact base hash authorization",
            "New final source freeze and full current canonical gate retaining every unit/HTTP/Linux/security obligation",
        ],
        "test_plan": [
            "Validate genuine fixtures as contained regular files with all ten declared names and immutable source/provenance receipts; no fabricated JSON or missing-import skips",
            "Freeze final source/manifest/config and unchanged lock; discover counts from completed reports rather than declarations or earlier137/140 packets",
            "Run maintained type closure, all dynamically discovered units and zero-ignored requirement; missing imports must fail before any acceptance",
            "Run maintained run_edge_http_uat.py with original60s deadline/frozen cached-only lock and loopback-only dependencies, starting all13 real entrypoints once; six new unsigned checks must match exact shapes/zero RPC and all old assertions must pass",
            "Require actual gateway fixture-driven P-256/six-action/route/replay/uncertainty tests to pass, retaining nonauthorizing response assertions; SQL/current hosted/device/carrier acceptance remains separate",
            "Run original Linux codec/integration, security and regression phases in full canonical runner; preserve failures and original deadlines rather than weakening checks",
        ],
    })
    print(json.dumps({"current_literal_loaders": len(current_loaders), "candidate_literal_loaders": len(candidate_loaders),
                      "current_unit_entryfiles": len(units), "missing_fixtures": len(fixture_status),
                      "maintained_inputs": len(before), "base_sha256": BASE,
                      "candidate_sha256": candidate["sha256"], "patch_sha256": sha(patch.encode())}))

if __name__ == "__main__":
    main()
