#!/usr/bin/env python3
"""Read-only public advisory research, confined to this dated report directory.

Only public package identities, exact versions and public advisory IDs leave
the machine. Source contents, inventory hashes and paths are never sent.
No credentials, registry installs, build hooks, upgrades or source writes.
"""
from __future__ import annotations

import argparse
import concurrent.futures
import datetime
import hashlib
import importlib.util
import json
import re
import ssl
import urllib.error
import urllib.parse
import urllib.request
from collections import Counter
from pathlib import Path

OUT = Path(__file__).resolve().parent
ROOT = OUT.parents[3]
CTX = ssl.create_default_context()
HEADERS = {"User-Agent": "Collect-readonly-public-advisory-triage/1.0"}


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def sha(data):
    return hashlib.sha256(data).hexdigest()


def write(name, value):
    path = OUT / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def fetch(label, url, payload=None):
    assert url.startswith("https://")
    assert urllib.parse.urlsplit(url).hostname in {
        "api.osv.dev", "api.github.com", "google.github.io",
        "ossf.github.io", "docs.github.com", "pypi.org", "pub.dev",
        "registry.npmjs.org", "rubygems.org", "raw.githubusercontent.com",
        "github.com", "www.jetbrains.com", "nvd.nist.gov",
    }
    raw = None if payload is None else json.dumps(payload, sort_keys=True, separators=(",", ":")).encode()
    if raw is not None:
        (OUT / (label + ".request.json")).parent.mkdir(parents=True, exist_ok=True)
        (OUT / (label + ".request.json")).write_bytes(raw)
    headers = dict(HEADERS)
    if raw is not None:
        headers["Content-Type"] = "application/json"
    if urllib.parse.urlsplit(url).hostname == "api.github.com":
        headers.update({"Accept": "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28"})
    meta = {"requested_at": now(), "request_url": url, "method": "GET" if raw is None else "POST",
            "tls_certificate_verification": "Python default trust store, hostname verification enabled",
            "authentication": "none", "request_sha256": None if raw is None else sha(raw)}
    body = None
    try:
        with urllib.request.urlopen(urllib.request.Request(url, data=raw, headers=headers), timeout=45, context=CTX) as response:
            body = response.read()
            if not response.url.startswith("https://"):
                raise ValueError("Non-TLS final response URL")
            meta.update({"status": response.status, "response_url": response.url,
                         "headers": {k: v for k, v in response.headers.items() if k.lower() in
                                     {"date", "content-type", "etag", "last-modified", "link", "x-ratelimit-remaining", "x-ratelimit-reset"}}})
    except urllib.error.HTTPError as error:
        body = error.read()
        meta.update({"status": error.code, "error": str(error)})
    except Exception as error:
        meta.update({"status": None, "error": str(error)})
    meta["retrieved_at"] = now()
    if body is not None:
        path = OUT / (label + ".response")
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(body)
        meta.update({"response_path": path.relative_to(OUT).as_posix(), "response_sha256": sha(body), "response_bytes": len(body)})
    write(label + ".metadata.json", meta)
    if meta.get("status") != 200:
        return meta, None
    try:
        return meta, json.loads(body)
    except (ValueError, TypeError):
        return meta, None


def mapping(row):
    eco, name, version = row["ecosystem"], row["name"], row["version"]
    simple = {"dart": "Pub", "maven": "Maven", "npm": "npm", "pnpm": "npm",
              "deno-npm": "npm", "pypi": "PyPI", "rubygems": "RubyGems"}
    rationale = "Exact locked package name/version in the corresponding public ecosystem"
    if eco == "dart" and row.get("qualifier") == "sdk":
        return None, "SDK placeholder 0.0.0 is not a hosted Pub package version; actual SDK/compiler advisories require separately bound toolchain evidence"
    if eco == "dart" and row.get("qualifier") == "path":
        if name == "file_saver" and version == "0.4.0+collect.1":
            version = "0.4.0"
        rationale = "Upstream public package/version proxy only; local fork additions, omissions and patches require the separate source-delta review and are not cleared by this query"
    if eco in simple:
        return {"package": {"ecosystem": simple[eco], "name": name}, "version": version}, rationale
    if eco == "swiftpm":
        return {"package": {"ecosystem": "SwiftURL", "name": row["origin"]}, "version": version}, "Exact public Git origin and resolved version under documented SwiftURL identity; Git URL aliases and native binary contents remain separate coverage limits"
    if eco in {"deno-import", "deno-remote"}:
        match = re.match(r"https://esm\.sh/((?:@[^/]+/)?[^@/?]+)@([^/?]+)", name)
        if match:
            return {"package": {"ecosystem": "npm", "name": match[1]}, "version": match[2]}, "Public npm package/version encoded in locked esm.sh URL; CDN transformation/module bytes are covered by frozen Deno evidence, not npm advisory identity"
        match = re.match(r"https://deno\.land/std@([^/]+)/", name)
        if match:
            return {"package": {"ecosystem": "GIT", "name": "https://github.com/denoland/std.git"}, "version": match[1]}, "Deno standard-library public Git tag proxy; queried tag does not independently authenticate Deno CDN source or assure complete std coverage"
        return None, "Remote module has no safely established package/version advisory mapping"
    if eco == "gradle-plugin":
        names = {"com.android.application": "com.android.tools.build:gradle",
                 "com.google.gms.google-services": "com.google.gms:google-services",
                 "org.jetbrains.kotlin.android": "org.jetbrains.kotlin:kotlin-gradle-plugin"}
        if name in names:
            return {"package": {"ecosystem": "Maven", "name": names[name]}, "version": version}, "Explicit implementation coordinate mapping for the declared public Gradle plugin; complete build-plugin transitive graph remains unobserved"
        return None, "Local Flutter SDK loader version is not a separately published Maven package"
    if eco == "cocoapods":
        return None, "Flutter 1.0.0 local CocoaPods stub does not identify a native SDK version; CocoaPods is not a documented OSV ecosystem"
    if eco == "oci":
        return None, "Image tag/digest cannot be converted to OS package versions without the exact platform manifest and installed package evidence; no container vulnerability clearance"
    return None, "No established exact public advisory mapping"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--inventory", type=Path)
    args = parser.parse_args()
    if args.inventory:
        raw = args.inventory.read_bytes()
        inventory = json.loads(raw)
        binding = {"path": args.inventory.resolve().as_posix(), "sha256": sha(raw)}
    else:
        spec = importlib.util.spec_from_file_location("current_collect_inventory", ROOT / "scripts/supply_chain/inventory.py")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        inventory = module.build()
        write("preliminary-inventory.json", inventory)
        binding = {"path": (OUT / "preliminary-inventory.json").as_posix(),
                   "sha256": sha((OUT / "preliminary-inventory.json").read_bytes()), "final_parent_inventory_pending": True}
    maps, unique = [], {}
    for index, row in enumerate(inventory["packages"]):
        query, rationale = mapping(row)
        key = json.dumps(query, sort_keys=True) if query else None
        if query is not None:
            assert set(query) == {"package", "version"} and set(query["package"]) == {"ecosystem", "name"}
            assert isinstance(query["version"], str) and query["version"]
            unique.setdefault(key, query)
        maps.append({"inventory_row_index": index, "inventory_row": row, "public_query_key": key,
                     "public_query": query, "mapping_rationale": rationale})
    keys = sorted(unique)
    queries = [unique[key] for key in keys]
    write("query-mapping.json", {"inventory": binding, "occurrences": maps,
                                 "unique_public_queries": queries, "created_at": now()})
    results = {}
    receipts = []
    for start in range(0, len(queries), 50):
        subset = queries[start:start+50]
        label = "osv-batch-" + str(start // 50 + 1).zfill(2)
        meta, data = fetch(label, "https://api.osv.dev/v1/querybatch", {"queries": subset})
        receipts.append(meta)
        if not isinstance(data, dict) or not isinstance(data.get("results"), list) or len(data["results"]) != len(subset):
            for offset in range(len(subset)):
                results[keys[start+offset]] = {"error": "HTTP/query result missing or result/input length mismatch", "request_label": label}
        else:
            for offset, result in enumerate(data["results"]):
                results[keys[start+offset]] = {"result": result, "request_label": label}
                if result.get("next_page_token"):
                    query = dict(subset[offset])
                    page = 1
                    seen = set()
                    while result.get("next_page_token"):
                        token = result["next_page_token"]
                        if token in seen:
                            results[keys[start+offset]]["error"] = "Repeated pagination token"
                            break
                        seen.add(token)
                        query["page_token"] = token
                        pm, result = fetch(label + "-q" + str(offset) + "-page" + str(page), "https://api.osv.dev/v1/query", query)
                        receipts.append(pm)
                        if not isinstance(result, dict):
                            results[keys[start+offset]]["error"] = "Pagination response missing"
                            break
                        results[keys[start+offset]]["result"].setdefault("vulns", []).extend(result.get("vulns", []))
                        page += 1
        print(json.dumps({"batch": label, "http": meta.get("status"), "query_count": len(subset)}), flush=True)
    write("query-results.json", {"inventory": binding, "queries": results, "receipts": receipts, "completed_at": now()})
    ids = sorted({v["id"] for item in results.values() for v in item.get("result", {}).get("vulns", [])})
    def get_record(identifier):
        label = "records/" + identifier
        meta, data = fetch(label, "https://api.osv.dev/v1/vulns/" + urllib.parse.quote(identifier, safe=""))
        return identifier, meta, data
    records = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
        for identifier, meta, data in pool.map(get_record, ids):
            records[identifier] = {"receipt": meta, "record": data}
    write("advisory-records-index.json", {"records": records, "completed_at": now()})
    print(json.dumps({"unique_queries": len(queries), "mapped_occurrences": sum(m["public_query"] is not None for m in maps),
                      "unmapped_occurrences": sum(m["public_query"] is None for m in maps), "advisory_record_ids": len(ids),
                      "record_errors": sum(v["record"] is None for v in records.values())}), flush=True)


if __name__ == "__main__":
    main()
