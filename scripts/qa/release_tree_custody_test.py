"""Exercise offline packet and restore verification with a synthetic Git tree."""
import gzip
import hashlib
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).with_name("release_tree_custody.py")
UNIT = "docs/release/example"


class ReleaseTreeCustodyTest(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name).resolve()
        self.repo = self.root / "source.git"
        subprocess.run(["git", "init", "--bare", "--quiet", str(self.repo)], check=True)

        def git(*args, data=b""):
            return subprocess.check_output(["git", "-C", str(self.repo), *args], input=data).strip()

        plain = git("hash-object", "-w", "--stdin", data=b"test bytes\n")
        target = git("hash-object", "-w", "--stdin", data=b"plain")
        tree = git("mktree", data=b"100644 blob " + plain + b"\tplain\n100755 blob " +
                   plain + b"\trun\n120000 blob " + target + b"\tlink\n")
        for name in (b"example", b"release", b"docs"):
            tree = git("mktree", data=b"040000 tree " + tree + b"\t" + name + b"\n")
        # This synthetic commit object needs no working tree, index, branch or author config.
        author = b"Fixture <fixture@example.invalid> 1700000000 +0000"
        commit = git("hash-object", "-w", "-t", "commit", "--stdin",
                     data=b"tree " + tree + b"\nauthor " + author + b"\ncommitter " + author + b"\n\nfixture\n")
        self.packet = self.root / "packet"
        captured = self.command("capture", self.repo, commit.decode(), UNIT, self.packet)
        self.assertEqual(captured.returncode, 0, captured.stderr)
        self.pin = json.loads(captured.stdout)["receipt_sha256"]
        self.assertEqual(self.pin, hashlib.sha256((self.packet / "receipt.json").read_bytes()).hexdigest())
        self.destination = self.root / "restored"

    def command(self, *args):
        return subprocess.run([sys.executable, str(SCRIPT), *map(str, args)], cwd=self.root,
                              umask=0o077, capture_output=True, text=True)

    def test_private_restore_reproduces_git_executable_bits_and_link(self):
        result = self.command("restore", self.packet, self.pin, self.destination)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(stat.S_IMODE(self.destination.stat().st_mode), 0o700)
        checkout = self.destination / UNIT
        self.assertEqual((checkout / "run").stat().st_mode & 0o111, 0o111)
        self.assertEqual((checkout / "plain").stat().st_mode & 0o111, 0)
        self.assertEqual(os.readlink(checkout / "link"), "plain")
        verified = self.command("verify", self.packet, self.pin, self.destination)
        self.assertEqual(verified.returncode, 0, verified.stderr)
        self.assertEqual(json.loads(verified.stdout)["paths"], 3)

    def test_wrong_receipt_or_restored_executable_mode_is_rejected(self):
        wrong = self.command("restore", self.packet, "0" * 64, self.destination)
        self.assertNotEqual(wrong.returncode, 0)
        self.assertIn("Unexpected custody receipt", wrong.stderr)
        self.assertFalse(self.destination.exists())
        restored = self.command("restore", self.packet, self.pin, self.destination)
        self.assertEqual(restored.returncode, 0, restored.stderr)
        (self.destination / UNIT / "run").chmod(0o700)
        verified = self.command("verify", self.packet, self.pin, self.destination)
        self.assertNotEqual(verified.returncode, 0)
        self.assertIn("mode or size differs", verified.stderr)

    def test_packet_verification_uses_only_the_retained_store(self):
        self.repo.rename(self.root / "unavailable-source.git")
        verified = self.command("verify-packet", self.packet, self.pin)
        self.assertEqual(verified.returncode, 0, verified.stderr)
        result = json.loads(verified.stdout)
        self.assertEqual(result["scope"], "packet")
        self.assertEqual(result["paths"], 3)
        self.assertEqual(result["git_modes"], {"100644": 1, "100755": 1, "120000": 1})
        self.assertFalse(self.destination.exists())

    def test_packet_verification_reads_blob_bytes_against_every_inventory_row(self):
        inventory = self.packet / "paths.jsonl.gz"
        rows = [json.loads(line) for line in gzip.decompress(inventory.read_bytes()).splitlines()]
        rows[0][-1] = "0" * 64
        changed = b"".join((json.dumps(row, separators=(",", ":")) + "\n").encode() for row in rows)
        inventory.write_bytes(gzip.compress(changed, mtime=0))
        receipt = self.packet / "receipt.json"
        document = json.loads(receipt.read_bytes())
        document["inventory_sha256"] = hashlib.sha256(inventory.read_bytes()).hexdigest()
        raw = json.dumps(document).encode()
        receipt.write_bytes(raw)
        refused = self.command("verify-packet", self.packet, hashlib.sha256(raw).hexdigest())
        self.assertNotEqual(refused.returncode, 0)
        self.assertIn("Evidence differs at", refused.stderr)


if __name__ == "__main__":
    unittest.main()
