#!/usr/bin/env python3
"""Source SBOM inventory identity remains bound to the parsed bytes."""
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("source_sbom", ROOT / "scripts/supply_chain/source_sbom.py")
source_sbom = importlib.util.module_from_spec(spec)
spec.loader.exec_module(source_sbom)


class SourceSbomIdentityTest(unittest.TestCase):
    def test_inventory_hash_tracks_parsed_contents_when_file_is_replaced(self):
        inventory = {
            "source_sha256": {}, "assets": [], "packages": [],
            "checks": {"dart": {"pubspec_version": "1.2.3"}},
            "coverage": {"included": ["first"], "excluded": []},
        }
        original = (json.dumps(inventory, indent=2) + "\n").encode("utf-8")
        replacement = b'{"unexpected":"different inventory"}'
        with tempfile.TemporaryDirectory() as directory:
            inventory_path = Path(directory) / "inventory.json"
            inventory_path.write_bytes(original)
            original_read_text, original_read_bytes = Path.read_text, Path.read_bytes
            replaced = False

            def replace_after_read(path, value):
                nonlocal replaced
                if path == inventory_path and not replaced:
                    path.write_bytes(replacement)
                    replaced = True
                return value

            def read_text(path, *args, **kwargs):
                return replace_after_read(path, original_read_text(path, *args, **kwargs))

            def read_bytes(path):
                return replace_after_read(path, original_read_bytes(path))

            with patch.object(Path, "read_text", read_text), patch.object(Path, "read_bytes", read_bytes):
                result = source_sbom.build(inventory_path)

            self.assertTrue(replaced)
            self.assertEqual(result["metadata"]["component"]["version"], "1.2.3")
            properties = {p["name"]: p["value"] for p in result["metadata"]["properties"]}
            self.assertEqual(properties["collect:inventory_sha256"], hashlib.sha256(original).hexdigest())
            self.assertNotEqual(properties["collect:inventory_sha256"], hashlib.sha256(replacement).hexdigest())
            self.assertEqual(inventory_path.read_bytes(), replacement)

    def test_cli_output_and_reproduction_check_use_current_inventory(self):
        inventory = {
            "source_sha256": {}, "assets": [], "packages": [],
            "checks": {"dart": {"pubspec_version": "1.2.3"}},
            "coverage": {"included": ["first"], "excluded": []},
        }
        with tempfile.TemporaryDirectory() as directory:
            inventory_path = Path(directory) / "inventory.json"
            output_path = Path(directory) / "source-bom.json"
            original = (json.dumps(inventory, indent=2) + "\n").encode("utf-8")
            inventory_path.write_bytes(original)
            command = [sys.executable, str(ROOT / "scripts/supply_chain/source_sbom.py"),
                       "--inventory", str(inventory_path), "--output", str(output_path)]
            self.assertEqual(subprocess.run(command, capture_output=True, text=True).returncode, 0)
            report = json.loads(output_path.read_bytes())
            properties = {p["name"]: p["value"] for p in report["metadata"]["properties"]}
            self.assertEqual(properties["collect:inventory_sha256"], hashlib.sha256(original).hexdigest())
            self.assertEqual(subprocess.run(command + ["--check"], capture_output=True, text=True).returncode, 0)
            inventory["checks"]["dart"]["pubspec_version"] = "1.2.4"
            inventory_path.write_text(json.dumps(inventory))
            check = subprocess.run(command + ["--check"], capture_output=True, text=True)
            self.assertEqual(check.returncode, 1)
            self.assertIn("differs", check.stdout)
            self.assertEqual(json.loads(output_path.read_bytes()), report)


if __name__ == "__main__":
    unittest.main()
