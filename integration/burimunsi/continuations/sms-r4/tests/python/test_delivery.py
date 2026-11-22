"""Actual temporary-checkout install tests and fixture/provenance consistency checks."""
import base64
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("sms_install", ROOT / "scripts/install_overlay.py")
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)

class DeliveryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="sms-checkout-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def checkout(self, app="burimunsi"):
        target = self.root / app
        namespace = "rw/ikanisa/burimunsi/core" if app == "burimunsi" else "com/ikanisa/mmoney/core"
        core = target / "core/src/main/kotlin" / namespace
        core.mkdir(parents=True)
        vendor = "buri" if app == "burimunsi" else "mmoney"
        for p in (ROOT / "vendor" / vendor / "core").glob("*.kt"):
            shutil.copy2(p, core / p.name)
        (target / "untouched.txt").write_text("preserve\n")
        return target

    def snapshot(self, directory):
        return {str(p.relative_to(directory)): p.read_bytes() for p in directory.rglob("*") if p.is_file()}

    def test_dry_run_writes_nothing(self):
        target = self.checkout()
        before = self.snapshot(target)
        result = installer.install(target, "burimunsi")
        self.assertTrue(result["files"])
        self.assertEqual(result["mode"], "dry_run")
        self.assertEqual(before, self.snapshot(target))

    def test_apply_and_repeat_both_applications(self):
        for app in ("burimunsi", "mmoney"):
            with self.subTest(application=app):
                target = self.checkout(app)
                before = self.snapshot(target)
                result = installer.install(target, app, True)
                self.assertEqual(result["runtime_wiring"], "not_modified")
                after = self.snapshot(target)
                self.assertTrue(all(after[p] == value for p, value in before.items()))
                self.assertEqual(len(after), len(before) + len(result["files"]))
                second = installer.install(target, app, True)
                self.assertTrue(all(x["action"] == "already_present" for x in second["files"]))
                self.assertEqual(after, self.snapshot(target))

    def test_local_edit_is_refused_without_writes(self):
        target = self.checkout()
        installer.install(target, "burimunsi", True)
        path = target / "core/src/main/kotlin/rw/ikanisa/sms/policy/Queue.kt"
        path.write_text("unrecognized local edits\n")
        before = self.snapshot(target)
        with self.assertRaises(installer.Refusal):
            installer.install(target, "burimunsi", True)
        self.assertEqual(before, self.snapshot(target))

    def test_unknown_baseline_is_refused(self):
        target = self.checkout()
        path = target / "core/src/main/kotlin/rw/ikanisa/burimunsi/core/Receipt.kt"
        path.write_text(path.read_text() + "\n// changed\n")
        before = self.snapshot(target)
        with self.assertRaises(installer.Refusal):
            installer.install(target, "burimunsi", True)
        self.assertEqual(before, self.snapshot(target))

    def test_missing_baseline_is_refused(self):
        target = self.checkout()
        (target / "core/src/main/kotlin/rw/ikanisa/burimunsi/core/Receipt.kt").unlink()
        with self.assertRaises(installer.Refusal):
            installer.install(target, "burimunsi")

    def test_preexisting_collision_blocks_entire_plan(self):
        target = self.checkout()
        path = target / "core/src/main/kotlin/rw/ikanisa/sms/policy/Queue.kt"
        path.parent.mkdir(parents=True)
        path.write_text("foreign implementation\n")
        before = self.snapshot(target)
        with self.assertRaises(installer.Refusal):
            installer.install(target, "burimunsi", True)
        self.assertEqual(before, self.snapshot(target))

    def test_symlink_root_is_refused(self):
        target = self.checkout()
        link = self.root / "link"
        link.symlink_to(target, target_is_directory=True)
        with self.assertRaises(installer.Refusal):
            installer.install(link, "burimunsi", True)

    def test_symlink_destination_is_refused(self):
        target = self.checkout()
        namespace = target / "core/src/main/kotlin/rw/ikanisa/sms"
        outside = self.root / "outside"
        outside.mkdir()
        namespace.symlink_to(outside, target_is_directory=True)
        with self.assertRaises(installer.Refusal):
            installer.install(target, "burimunsi", True)
        self.assertEqual(list(outside.iterdir()), [])

    def test_traversal_and_absolute_paths_are_refused(self):
        for name in ("../outside", "/etc/passwd", "safe/../../outside"):
            with self.subTest(path=name):
                with self.assertRaises(installer.Refusal):
                    installer.checked(self.root, name)

    def test_unknown_application_is_refused(self):
        with self.assertRaises(installer.Refusal):
            installer.install(self.checkout(), "other", True)

    def test_fixture_transport_preserves_exact_originals(self):
        document = json.loads((ROOT / "fixtures/classification.json").read_text())
        cases = document["cases"]
        rows = (ROOT / "fixtures/classification.tsv").read_text().splitlines()[1:]
        self.assertEqual(len(rows), len(cases))
        self.assertEqual(len(cases), len({x["id"] for x in cases}))
        for line, case in zip(rows, cases):
            ident, contract, sender, body, expected = line.split("\t")
            self.assertEqual(ident, case["id"])
            self.assertEqual(contract, case["contract"])
            self.assertEqual(None if sender == "-" else base64.b64decode(sender).decode(), case["sender"])
            self.assertEqual(base64.b64decode(body).decode(), case["body"])
            self.assertEqual(expected, case["expected"])

    def test_inherited_fixture_originals_unchanged(self):
        inherited = json.loads((ROOT / "fixtures/mmoney-inherited.json").read_text())["cases"]
        derived = {x["id"]: x for x in json.loads((ROOT / "fixtures/classification.json").read_text())["cases"]}
        for original in inherited:
            new = derived["mm-" + original["id"]]
            self.assertEqual(new["body"], original["body"])
            self.assertEqual(new["sender"], original["sender"])
            # The new layer distinguishes absent metadata from unsupported-but-complete messages.
            if original["sender"] is None:
                self.assertEqual(new["expected"], "INCOMPLETE")
            else:
                self.assertEqual(new["expected"].startswith("SUPPORTED_"), original["cloudEligible"])

    def test_r1_effective_acknowledgement_matches_pinned_generation(self):
        raw = (ROOT / "vendor/buri/receiver/ReceiptAckPolicy.kt").read_text()
        effective = (ROOT / "vendor/buri/effective/ReceiptAckPolicy.kt").read_text()
        anchor = "                if (item != null) sha256(item.rawBody) == digest else acknowledged[id] == digest"
        guard = "                (acknowledged[id] == null || acknowledged[id] == digest) &&\n"
        self.assertEqual(raw.count(anchor), 1)
        self.assertEqual(raw.replace(anchor, guard + anchor), effective)

    def test_pinned_sources_match_provenance(self):
        entries = json.loads((ROOT / "vendor/PROVENANCE.json").read_text())["files"]
        self.assertEqual(len(entries), len({x["path"] for x in entries}))
        for entry in entries:
            self.assertEqual(hashlib.sha256((ROOT / entry["path"]).read_bytes()).hexdigest(), entry["sha256"])

if __name__ == "__main__":
    unittest.main()
