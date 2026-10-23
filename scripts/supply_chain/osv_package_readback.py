#!/usr/bin/env python3
"""Read current OSV matches for public package identities, not source uploads.

Inputs stay hash-bound. This reports advisory matches at the observation time;
it cannot certify package coverage, exploitability, licences or store approval.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
from pathlib import Path
import re
import urllib.request

import yaml

ENDPOINT = "https://api.osv.dev/v1/querybatch"
MAX_BYTES = 8 * 1024 * 1024


def read_input(path: Path):
    if path.is_symlink() or not path.is_file() or path.stat().st_size > MAX_BYTES:
        raise ValueError("Input must be a bounded regular file")
    raw = path.read_bytes()
    if len(raw) > MAX_BYTES:
        raise ValueError("Input grew beyond its bound")
    return raw, {"path": str(path.absolute()), "sha256": hashlib.sha256(raw).hexdigest(), "bytes": len(raw)}


def packages(sbom: dict, pub: dict, npm: dict):
    found, skipped = {}, []

    def add(ecosystem, name, version, scope):
        if (not isinstance(name, str) or not isinstance(version, str)
                or not name or not version or len(name) > 300 or len(version) > 100
                or re.search(r"[\x00-\x20\x7f]", name + version)):
            raise ValueError("Invalid public package identity")
        key = (ecosystem, name, version)
        found.setdefault(key, {"package": {"ecosystem": ecosystem, "name": name}, "version": version, "scopes": []})["scopes"].append(scope)

    if sbom.get("bomFormat") != "CycloneDX" or not isinstance(sbom.get("components"), list):
        raise ValueError("Expected an observed CycloneDX input")
    for row in sbom["components"]:
        if isinstance(row.get("purl"), str) and row["purl"].startswith("pkg:maven/"):
            add("Maven", row["group"] + ":" + row["name"], row["version"], "observed Android Gradle component")
        else:
            skipped.append({"source": "Android SBOM", "identity": row.get("bom-ref"), "reason": "No supported public Maven identity; local projects are not inferred"})
    for name, row in pub.get("packages", {}).items():
        description = row.get("description")
        if row.get("source") == "hosted" and isinstance(description, dict) and description.get("url") == "https://pub.dev":
            if description.get("name") != name:
                raise ValueError("Pub identity alias needs explicit review")
            add("Pub", name, row["version"], "Dart lock declaration")
        else:
            skipped.append({"source": "Dart lock", "identity": name, "reason": "SDK, local, fork or non-public host; no hosted identity inferred"})
    if npm.get("lockfileVersion") != 3 or not isinstance(npm.get("packages"), dict):
        raise ValueError("Expected an npm v3 package lock")
    for path, row in npm["packages"].items():
        if not path:
            continue
        if not row.get("link") and str(row.get("resolved", "")).startswith("https://registry.npmjs.org/") and "node_modules/" in path:
            name = path.rsplit("node_modules/", 1)[1]
            if row.get("name", name) != name:
                raise ValueError("npm alias needs explicit review")
            add("npm", name, row["version"], "backend tooling lock declaration")
        else:
            skipped.append({"source": "npm lock", "identity": path, "reason": "Non-public, linked or unresolved declaration"})
    if not found or len(found) > 2000:
        raise ValueError("Unexpected query inventory size")
    return [found[k] for k in sorted(found)], skipped


def query_osv(payload):
    request = urllib.request.Request(ENDPOINT, data=json.dumps(payload).encode(), headers={"Content-Type": "application/json", "Accept": "application/json"}, method="POST")
    with urllib.request.urlopen(request, timeout=30) as response:
        if response.status != 200 or response.url != ENDPOINT:
            raise ValueError("Unexpected advisory endpoint response")
        raw = response.read(MAX_BYTES + 1)
    if len(raw) > MAX_BYTES:
        raise ValueError("Advisory response exceeded its bound")
    return json.loads(raw)


def scan(inventory, output: Path, query=query_osv):
    results = [[] for _ in inventory]
    pending = [(i, {k: row[k] for k in ["package", "version"]}) for i, row in enumerate(inventory)]
    request_number = 0
    for page in range(10):
        if not pending:
            return results
        successors = []
        for start in range(0, len(pending), 100):
            batch = pending[start:start + 100]
            payload = {"queries": [q for _, q in batch]}
            prefix = f"batch-{request_number:03d}"
            (output / (prefix + "-query.json")).write_text(json.dumps(payload, indent=2) + "\n")
            response = query(payload)
            (output / (prefix + "-response.json")).write_text(json.dumps(response, indent=2) + "\n")
            request_number += 1
            if not isinstance(response, dict) or not isinstance(response.get("results"), list) or len(response["results"]) != len(batch):
                raise ValueError("Advisory response cardinality mismatch")
            for (index, sent), result in zip(batch, response["results"]):
                if not isinstance(result, dict) or set(result) - {"vulns", "next_page_token"}:
                    raise ValueError("Unexpected advisory result")
                vulns = result.get("vulns", [])
                if not isinstance(vulns, list) or len(vulns) > 3000 or any(not isinstance(v, dict) or not isinstance(v.get("id"), str) or not re.fullmatch(r"[A-Za-z0-9._-]{1,120}", v["id"]) for v in vulns):
                    raise ValueError("Invalid advisory identifiers")
                results[index].extend(vulns)
                token = result.get("next_page_token")
                if token is not None:
                    if not isinstance(token, str) or not token or len(token) > 8192 or sent.get("page_token") == token:
                        raise ValueError("Invalid or repeated pagination token")
                    successors.append((index, {**sent, "page_token": token}))
        pending = successors
    raise ValueError("Advisory pagination did not complete within the bound")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ["android-sbom", "pub-lock", "npm-lock", "output-directory"]:
        parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--query-public-packages", action="store_true", required=True)
    args = parser.parse_args()
    output = args.output_directory
    output.mkdir(mode=0o700)
    observed = dt.datetime.now(dt.timezone.utc).isoformat()
    report = {"observed_at": observed, "endpoint": ENDPOINT, "complete": False, "whole_dependency_clearance": False, "production_release_approval": False}
    try:
        captured = [read_input(p) for p in [args.android_sbom, args.pub_lock, args.npm_lock]]
        inventory, skipped = packages(json.loads(captured[0][0]), yaml.safe_load(captured[1][0]), json.loads(captured[2][0]))
        report.update(inputs=[row for _, row in captured], inventory=inventory, skipped=skipped)
        findings = scan(inventory, output)
        for _, row in captured:
            if read_input(Path(row["path"]))[1] != row:
                raise ValueError("An input changed during the advisory readback")
        report.update(complete=True, package_count=len(inventory), matches=[{**row, "advisories": matches} for row, matches in zip(inventory, findings) if matches], scope="Public package version matches at observation time. Native SBOM identities are observed; Dart/npm are lock declarations. Local/fork/SDK packages remain explicit exclusions. No source, credentials or user records were sent. Absence of matches is not proof of safety or licence approval.")
    except Exception as error:
        report["error"] = type(error).__name__ + ": " + str(error)
    (output / "result.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({k: report.get(k) for k in ["complete", "package_count", "error"]}))
    if not report["complete"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
