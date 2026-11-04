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
import time
import urllib.request

import yaml

ENDPOINT = "https://api.osv.dev/v1/querybatch"
MAX_BYTES = 8 * 1024 * 1024
MAX_RECORDS = 500
MAX_SECONDS = 180
MAX_TOTAL_RESPONSE_BYTES = 32 * 1024 * 1024


class RefuseRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise ValueError("Advisory redirects are forbidden")


def unique_json(raw):
    def unique(pairs):
        value = {}
        for key, item in pairs:
            if key in value:
                raise ValueError("Duplicate JSON key")
            value[key] = item
        return value
    return json.loads(raw, object_pairs_hook=unique)


class UniqueSafeLoader(yaml.SafeLoader):
    def construct_mapping(self, node, deep=False):
        value = {}
        for key_node, value_node in node.value:
            key = self.construct_object(key_node, deep=deep)
            if key in value:
                raise ValueError("Duplicate YAML key")
            value[key] = self.construct_object(value_node, deep=deep)
        return value


def unique_yaml(raw):
    return yaml.load(raw, Loader=UniqueSafeLoader)


def read_input(path: Path):
    if path.is_symlink() or not path.is_file() or path.stat().st_size > MAX_BYTES:
        raise ValueError("Input must be a bounded regular file")
    raw = path.read_bytes()
    if len(raw) > MAX_BYTES:
        raise ValueError("Input grew beyond its bound")
    return raw, {"path": str(path.absolute()), "sha256": hashlib.sha256(raw).hexdigest(), "bytes": len(raw)}


def packages(sbom: dict | None, pub: dict, npm, ruby: str | None = None):
    found, skipped = {}, []

    def add(ecosystem, name, version, scope):
        if (not isinstance(name, str) or not isinstance(version, str)
                or not name or not version or len(name) > 300 or len(version) > 100
                or re.search(r"[\x00-\x20\x7f]", name + version)
                or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9.+_-]*", version)):
            raise ValueError("Invalid public package identity")
        key = (ecosystem, name, version)
        found.setdefault(key, {"package": {"ecosystem": ecosystem, "name": name}, "version": version, "scopes": []})["scopes"].append(scope)

    if sbom is not None and (sbom.get("bomFormat") != "CycloneDX" or not isinstance(sbom.get("components"), list)):
        raise ValueError("Expected an observed CycloneDX input")
    for row in (sbom or {}).get("components", []):
        skipped.append({"source": "Android SBOM", "identity": row.get("bom-ref"), "reason": "Maven repository origin is not established; local projects are not inferred"})
    for name, row in pub.get("packages", {}).items():
        description = row.get("description")
        if row.get("source") == "hosted" and isinstance(description, dict) and description.get("url") == "https://pub.dev":
            if description.get("name") != name:
                raise ValueError("Pub identity alias needs explicit review")
            if not re.fullmatch(r"[a-z0-9_]+", name):
                raise ValueError("Invalid Pub registry identity")
            add("Pub", name, row["version"], "Dart lock: " + str(row.get("dependency", "unknown")))
        else:
            skipped.append({"source": "Dart lock", "identity": name, "reason": "SDK, local, fork or non-public host; no hosted identity inferred"})
    npm_locks = [("npm lock", npm)] if isinstance(npm, dict) else npm
    for source, lock in npm_locks:
        if lock.get("lockfileVersion") != 3 or not isinstance(lock.get("packages"), dict):
            raise ValueError("Expected an npm v3 package lock")
        for path, row in lock["packages"].items():
            if not path:
                continue
            if not row.get("link") and str(row.get("resolved", "")).startswith("https://registry.npmjs.org/") and "node_modules/" in path:
                name = path.rsplit("node_modules/", 1)[1]
                if row.get("name", name) != name:
                    raise ValueError("npm alias needs explicit review")
                if not re.fullmatch(r"(?:@[a-z0-9._~-]+/)?[a-z0-9._~-]+", name):
                    raise ValueError("Invalid npm registry identity")
                expected = "https://registry.npmjs.org/" + name + "/-/" + name.rsplit("/", 1)[-1] + "-" + str(row.get("version")) + ".tgz"
                if row["resolved"] != expected:
                    raise ValueError("npm tarball identity needs explicit review")
                flags = [flag for flag in ("dev", "optional", "devOptional") if row.get(flag) is True]
                root = lock["packages"].get("", {})
                direct = [key for key in ("dependencies", "devDependencies", "optionalDependencies") if path == "node_modules/" + name and name in root.get(key, {})]
                add("npm", name, row["version"], source + ": " + (",".join(direct) or "transitive") + ": " + (",".join(flags) or "unmarked") + ": " + path)
            else:
                skipped.append({"source": source, "identity": path, "reason": "Non-public, linked or unresolved declaration"})
    if ruby is not None:
        lines = ruby.splitlines()
        sections = [line for line in lines if re.fullmatch(r"[A-Z][A-Z ]+", line)]
        if sections not in (["GEM", "PLATFORMS", "DEPENDENCIES", "BUNDLED WITH"], ["GEM", "PLATFORMS", "DEPENDENCIES", "CHECKSUMS", "BUNDLED WITH"]) or [line for line in lines if line.startswith("  remote:")] != ["  remote: https://rubygems.org/"]:
            raise ValueError("Ruby lock has ambiguous or non-public sources")
        gem = ruby.split("\nPLATFORMS\n", 1)[0]
        direct = ruby.split("\nDEPENDENCIES\n", 1)[1].split("\nCHECKSUMS\n", 1)[0].split("\nBUNDLED WITH\n", 1)[0]
        direct_names = set(re.findall(r"^  ([A-Za-z0-9_.-]+)(?:\s|$)", direct, re.M))
        locked = re.findall(r"^    ([A-Za-z0-9_.-]+) \(([^)]+)\)$", gem, re.M)
        entries = [line for line in gem.splitlines() if line.startswith("    ") and not line.startswith("      ")]
        if not locked or len(locked) != len(set(locked)) or len(entries) != len(locked) or not direct_names.issubset({name for name, _ in locked}):
            raise ValueError("Ruby lock entries are missing or duplicated")
        for name, version in locked:
            add("RubyGems", name, version, "Gemfile.lock: " + ("direct" if name in direct_names else "transitive"))
    if not found or len(found) > 2000:
        raise ValueError("Unexpected query inventory size")
    return [found[k] for k in sorted(found)], skipped


def read_osv(request, endpoint):
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), RefuseRedirect())
    with opener.open(request, timeout=30) as response:
        if response.status != 200 or response.url != endpoint:
            raise ValueError("Unexpected advisory endpoint response")
        raw = response.read(MAX_BYTES + 1)
    if len(raw) > MAX_BYTES:
        raise ValueError("Advisory response exceeded its bound")
    return unique_json(raw), raw


def query_osv(payload):
    request = urllib.request.Request(ENDPOINT, data=json.dumps(payload).encode(), headers={"Content-Type": "application/json", "Accept": "application/json"}, method="POST")
    return read_osv(request, ENDPOINT)


def fetch_record(identifier):
    if not isinstance(identifier, str) or not re.fullmatch(r"[A-Za-z0-9._-]{1,120}", identifier):
        raise ValueError("Invalid advisory identifier")
    endpoint = "https://api.osv.dev/v1/vulns/" + identifier
    request = urllib.request.Request(endpoint, headers={"Accept": "application/json"}, method="GET")
    value, raw = read_osv(request, endpoint)
    if not isinstance(value, dict) or value.get("id") != identifier:
        raise ValueError("Advisory record identity mismatch")
    return value, raw


def charge_response(raw, budget):
    if not isinstance(raw, bytes) or len(raw) > MAX_BYTES:
        raise ValueError("Invalid bounded advisory response")
    if budget is not None:
        budget[0] += len(raw)
        if budget[0] > MAX_TOTAL_RESPONSE_BYTES:
            raise ValueError("Total advisory response budget exceeded")


def compare_modified(batch, record):
    pattern = r"(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(?:\.(\d{1,9}))?Z"
    a = re.fullmatch(pattern, batch) if isinstance(batch, str) else None
    b = re.fullmatch(pattern, record) if isinstance(record, str) else None
    if not a or not b:
        raise ValueError("Invalid advisory modification timestamp")
    try:
        dt.datetime.strptime(a[1], "%Y-%m-%dT%H:%M:%S")
        dt.datetime.strptime(b[1], "%Y-%m-%dT%H:%M:%S")
    except ValueError as error:
        raise ValueError("Invalid advisory modification timestamp") from error
    first, second = a[2] or "", b[2] or ""
    precision = min(len(first), len(second))
    if a[1] != b[1] or first[:precision] != second[:precision]:
        raise ValueError("Advisory changed between query and detail readback")
    return {"shared_fractional_digits": precision,
            "batch_fractional_digits": len(first), "record_fractional_digits": len(second),
            "consistent_to_common_precision": True,
            "finer_precision_or_unchanged_record_proven": False}


def scan(inventory, output: Path, query=query_osv, deadline=None, budget=None):
    results = [[] for _ in inventory]
    seen_tokens = [set() for _ in inventory]
    seen_ids = [set() for _ in inventory]
    pending = [(i, {k: row[k] for k in ["package", "version"]}) for i, row in enumerate(inventory)]
    request_number = 0
    for page in range(10):
        if not pending:
            return results
        successors = []
        for start in range(0, len(pending), 100):
            if deadline is not None and time.monotonic() >= deadline:
                raise ValueError("Advisory request time budget exhausted")
            batch = pending[start:start + 100]
            payload = {"queries": [q for _, q in batch]}
            prefix = f"batch-{request_number:03d}"
            (output / (prefix + "-query.json")).write_bytes(json.dumps(payload).encode())
            returned = query(payload)
            response, raw = returned if isinstance(returned, tuple) else (returned, json.dumps(returned).encode())
            charge_response(raw, budget)
            (output / (prefix + "-response.json")).write_bytes(raw)
            request_number += 1
            if not isinstance(response, dict) or not isinstance(response.get("results"), list) or len(response["results"]) != len(batch):
                raise ValueError("Advisory response cardinality mismatch")
            for (index, sent), result in zip(batch, response["results"]):
                if not isinstance(result, dict) or set(result) - {"vulns", "next_page_token"}:
                    raise ValueError("Unexpected advisory result")
                vulns = result.get("vulns", [])
                if not isinstance(vulns, list) or len(vulns) > 3000 or any(not isinstance(v, dict) or not isinstance(v.get("id"), str) or not re.fullmatch(r"[A-Za-z0-9._-]{1,120}", v["id"]) or ("modified" in v and not isinstance(v["modified"], str)) for v in vulns):
                    raise ValueError("Invalid advisory identifiers")
                ids = [v["id"] for v in vulns]
                if len(ids) != len(set(ids)) or any(identifier in seen_ids[index] for identifier in ids):
                    raise ValueError("Repeated advisory identifier in a query")
                seen_ids[index].update(ids)
                results[index].extend(vulns)
                token = result.get("next_page_token")
                if token is not None:
                    if not isinstance(token, str) or not token or len(token) > 8192 or token in seen_tokens[index]:
                        raise ValueError("Invalid or repeated pagination token")
                    seen_tokens[index].add(token)
                    successors.append((index, {**sent, "page_token": token}))
        pending = successors
    if not pending:
        return results
    raise ValueError("Advisory pagination did not complete within the bound")


def details(findings, output: Path, deadline, fetch=fetch_record, budget=None):
    identifiers = {}
    for matches in findings:
        for item in matches:
            identifiers.setdefault(item["id"], set()).add(item.get("modified"))
    if len(identifiers) > MAX_RECORDS:
        raise ValueError("Advisory detail record limit exceeded")
    detail = []
    for identifier, modified in sorted(identifiers.items()):
        if not isinstance(identifier, str) or not re.fullmatch(r"[A-Za-z0-9._-]{1,120}", identifier):
            raise ValueError("Invalid advisory identifier")
        if time.monotonic() >= deadline:
            raise ValueError("Advisory request time budget exhausted")
        if len(modified) != 1 or None in modified:
            raise ValueError("Advisory batch modification time is missing or inconsistent")
        record, raw = fetch(identifier)
        charge_response(raw, budget)
        path = output / ("record-" + identifier + ".json")
        path.write_bytes(raw)
        if record.get("id") != identifier:
            raise ValueError("Advisory changed between query and detail readback")
        batch_modified = next(iter(modified))
        comparison = compare_modified(batch_modified, record.get("modified"))
        detail.append({"id": identifier, "batch_modified": batch_modified, "record_modified": record["modified"],
                       "timestamp_comparison": comparison, "sha256": hashlib.sha256(raw).hexdigest(), "path": path.name})
    return detail


def verify_reviewed(inventory, raw):
    expected = {"queries": [{k: row[k] for k in ("package", "version")} for row in inventory]}
    if unique_json(raw) != expected:
        raise ValueError("Public query identities differ from reviewed payload")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--android-sbom", type=Path)
    parser.add_argument("--pub-lock", type=Path, required=True)
    parser.add_argument("--npm-lock", type=Path, action="append", required=True)
    parser.add_argument("--ruby-lock", type=Path)
    parser.add_argument("--reviewed-payload", type=Path)
    parser.add_argument("--output-directory", type=Path, required=True)
    parser.add_argument("--query-public-packages", action="store_true", required=True)
    args = parser.parse_args()
    output = args.output_directory
    output.mkdir(mode=0o700)
    observed = dt.datetime.now(dt.timezone.utc).isoformat()
    report = {"observed_at": observed, "endpoint": ENDPOINT, "complete": False, "whole_dependency_clearance": False, "production_release_approval": False}
    try:
        inputs = ([args.android_sbom] if args.android_sbom else []) + [args.pub_lock] + args.npm_lock + ([args.ruby_lock] if args.ruby_lock else []) + ([args.reviewed_payload] if args.reviewed_payload else [])
        if len({str(p.absolute()) for p in inputs}) != len(inputs):
            raise ValueError("Repeated input path")
        captured = [read_input(p) for p in inputs]
        lookup = {str(p.absolute()): raw for p, (raw, _) in zip(inputs, captured)}
        raw_for = lambda p: lookup[str(p.absolute())]
        sbom = unique_json(raw_for(args.android_sbom)) if args.android_sbom else None
        pub = unique_yaml(raw_for(args.pub_lock))
        npm = [(str(path.absolute()), unique_json(raw_for(path))) for path in args.npm_lock]
        ruby = raw_for(args.ruby_lock).decode("utf-8") if args.ruby_lock else None
        inventory, skipped = packages(sbom, pub, npm, ruby)
        if args.reviewed_payload:
            verify_reviewed(inventory, raw_for(args.reviewed_payload))
        report.update(inputs=[row for _, row in captured], inventory=inventory, skipped=skipped)
        deadline = time.monotonic() + MAX_SECONDS
        budget = [0]
        findings = scan(inventory, output, deadline=deadline, budget=budget)
        detail = details(findings, output, deadline, budget=budget)
        for _, row in captured:
            if read_input(Path(row["path"]))[1] != row:
                raise ValueError("An input changed during the advisory readback")
        report.update(complete=True, package_count=len(inventory), response_bytes=budget[0], records=detail, matches=[{**row, "advisories": matches} for row, matches in zip(inventory, findings) if matches], excluded_ecosystems=["Maven repository origin not bound", "PyPI origin not bound", "JSR", "OCI images", "SDK", "local forks", "private registry packages"], scope="Public package version matches at observation time. Dart, npm and Ruby are lock declarations; runtime reachability and installed membership are not proven. OSV version matching can be fuzzy. No source, credentials or user records were sent. Absence of matches is not proof of safety or licence approval.")
    except Exception as error:
        report["error"] = type(error).__name__ + ": " + str(error)
    report["completed_at"] = dt.datetime.now(dt.timezone.utc).isoformat()
    (output / "result.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({k: report.get(k) for k in ["complete", "package_count", "error"]}))
    if not report["complete"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
