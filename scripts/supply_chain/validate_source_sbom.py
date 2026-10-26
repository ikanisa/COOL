#!/usr/bin/env python3
"""Offline CycloneDX1.6 schema validation using hash-bound retained schemas.

Schema conformance is a document check, not installed-artifact, vulnerability or
license acceptance. This validator performs no network fetches.
"""
import argparse
import hashlib
import json
from pathlib import Path

from jsonschema import Draft7Validator
from referencing import Registry, Resource

ROOT = Path(__file__).resolve().parents[2]
SCHEMAS = ROOT / "scripts/supply_chain/schemas/cyclonedx-1.6"
PROVENANCE_SHA256 = "b541145f59fc45bfca95bf2668001f8aae99359bcd009100e91653f8e7ea4b9d"


def validate(document_path: Path) -> list[str]:
    provenance_raw = (SCHEMAS / "provenance.json").read_bytes()
    if hashlib.sha256(provenance_raw).hexdigest() != PROVENANCE_SHA256:
        raise ValueError("Retained schema provenance drift")
    provenance = json.loads(provenance_raw)
    files = provenance["schema_files"]
    registry = Registry()
    documents = {}
    for filename, expected in files.items():
        path = SCHEMAS / filename
        raw = path.read_bytes()
        if hashlib.sha256(raw).hexdigest() != expected:
            raise ValueError("Retained schema drift: " + filename)
        document = json.loads(raw)
        documents[filename] = document
        resource = Resource.from_contents(document)
        for url in {document["$id"], "http://cyclonedx.org/schema/" + filename,
                    "https://cyclonedx.org/schema/" + filename}:
            registry = registry.with_resource(url, resource)
    validator = Draft7Validator(documents["bom-1.6.schema.json"], registry=registry)
    return ["/".join(map(str, error.path)) + ": " + error.message
            for error in sorted(validator.iter_errors(json.loads(document_path.read_text())), key=lambda error: str(error.path))]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("document", type=Path)
    args = parser.parse_args()
    errors = validate(args.document)
    print(json.dumps({"status": "fail" if errors else "pass", "schema": "CycloneDX1.6",
                      "network_fetches": 0, "document_sha256": hashlib.sha256(args.document.read_bytes()).hexdigest(),
                      "schema_conformance_only": True, "errors": errors}, indent=2))
    return int(bool(errors))


if __name__ == "__main__":
    raise SystemExit(main())
