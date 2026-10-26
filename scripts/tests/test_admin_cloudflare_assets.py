"""Admin output font exclusion; no source mutation, Flutter build, or deploy."""

import base64
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/admin_cloudflare_assets.py"
SPEC = importlib.util.spec_from_file_location("admin_assets_under_test", SCRIPT)
assets = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = assets
SPEC.loader.exec_module(assets)
REGULAR = "assets/typefaces/AeonikPro-Regular.ttf"
MEDIUM = "assets/typefaces/AeonikPro-Medium.ttf"
INTER = "assets/typefaces/Inter-Variable.ttf"
LOGO = "assets/brand/logo.png"


def sdk_string(value):
    """A short literal StandardMessageCodec string (SDK type 7)."""
    raw = value.encode("utf-8")
    assert len(raw) < 254
    return b"\x07" + bytes([len(raw)]) + raw


def fixture_manifest(paths):
    # The fixture's bytes are constructed from the SDK wire format, independently
    # of the helper's writer: ordered map -> list -> metadata map -> asset string.
    result = bytearray(b"\x0d" + bytes([len(paths)]))
    for path in paths:
        result.extend(sdk_string(path))
        result.extend(b"\x0c\x01\x0d\x01" + sdk_string("asset") + sdk_string(path))
    return bytes(result)


def write_manifest(build, binary):
    folder = build / "assets"
    (folder / "AssetManifest.bin").write_bytes(binary)
    (folder / "AssetManifest.bin.json").write_text(json.dumps(base64.b64encode(binary).decode("ascii")))


def snapshot(folder):
    return {path.relative_to(folder).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in folder.rglob("*") if path.is_file() and not path.is_symlink()}


class AdminAssetPruneTest(unittest.TestCase):
    def setUp(self):
        # Resolve the macOS /var -> /private/var system alias. The actual build
        # passed to the helper must have no symlink anywhere in its path.
        self.temporary = tempfile.TemporaryDirectory(prefix="collect-admin-font-test-", dir=Path(tempfile.gettempdir()).resolve())
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.build = self.directory / "admin-output"
        self.build.mkdir()
        for marker in ("index.html", "flutter_bootstrap.js"):
            (self.build / marker).write_text("existing Flutter output " + marker)
        for path in (REGULAR, MEDIUM, INTER, LOGO):
            file = self.build / "assets" / path
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_bytes(("retained original bytes for " + path).encode())
        self.fonts = [
            {"family": "Inter", "fonts": [{"asset": INTER}], "extra": {"ordered": [2, 1]}},
            {"family": "Aeonik Pro", "fonts": [{"weight": 400, "asset": REGULAR}, {"weight": 500, "asset": MEDIUM}]},
        ]
        self.write_fonts(self.fonts)
        write_manifest(self.build, fixture_manifest((LOGO, REGULAR, INTER, MEDIUM)))

    def write_fonts(self, value):
        (self.build / "assets/FontManifest.json").write_text(json.dumps(value))

    def assert_refused_unchanged(self):
        before = snapshot(self.build)
        with self.assertRaises(assets.ManifestError):
            assets.prune_admin_fonts(self.build)
        self.assertEqual(before, snapshot(self.build))
        self.assertFalse(any(self.build.glob(".admin-font-prune-*")))

    def test_prunes_family_files_both_manifests_and_preserves_every_other_file(self):
        source = self.directory / "source-fonts"
        source.mkdir()
        (source / "AeonikPro-Regular.ttf").write_bytes(b"untouched source font")
        source_before = snapshot(source)
        before = snapshot(self.build)
        receipt = assets.prune_admin_fonts(self.build)
        self.assertEqual("Aeonik Pro", receipt["removed_font_family"])
        self.assertEqual([MEDIUM, REGULAR], receipt["removed_assets"])
        self.assertEqual((4, 2), (receipt["asset_entries_before"], receipt["asset_entries_after"]))
        self.assertTrue(receipt["changed"])
        after = snapshot(self.build)
        for relative, digest in before.items():
            if relative in {"assets/" + REGULAR, "assets/" + MEDIUM}:
                self.assertNotIn(relative, after)
            elif relative not in {"assets/" + name for name in assets.MANIFESTS}:
                self.assertEqual(digest, after[relative], relative)
        self.assertEqual(self.fonts[:1], json.loads((self.build / "assets/FontManifest.json").read_bytes()))
        binary = (self.build / "assets/AssetManifest.bin").read_bytes()
        self.assertEqual(fixture_manifest((LOGO, INTER)), binary)
        self.assertEqual(binary, base64.b64decode(json.loads((self.build / "assets/AssetManifest.bin.json").read_bytes()), validate=True))
        self.assertEqual(source_before, snapshot(source))
        before_replay = snapshot(self.build)
        self.assertFalse(assets.prune_admin_fonts(self.build)["changed"])
        self.assertEqual(before_replay, snapshot(self.build))

    def test_metadata_entries_leave_both_manifests_without_deleting_retained_metadata(self):
        names = ('nested/._logo.txt', 'nested/.DS_Store')
        for name in names:
            path = self.build / 'assets' / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b'retained filesystem metadata')
        write_manifest(self.build, fixture_manifest((LOGO, REGULAR, INTER, MEDIUM, *names)))
        result = assets.prune_admin_fonts(self.build)
        self.assertEqual(sorted(names), result['excluded_metadata_assets'])
        binary = (self.build / 'assets/AssetManifest.bin').read_bytes()
        self.assertEqual({LOGO, INTER}, set(assets._asset_manifest(assets.decode_manifest(binary))))
        self.assertEqual(binary, base64.b64decode(json.loads((self.build / 'assets/AssetManifest.bin.json').read_bytes())))
        for name in names:
            self.assertEqual(b'retained filesystem metadata', (self.build / 'assets' / name).read_bytes())
        self.assertFalse(assets.prune_admin_fonts(self.build)['changed'])

    @unittest.skipUnless((ROOT / "build/admin-cloudflare/assets/AssetManifest.bin").is_file(), "Existing local Admin output is not present")
    def test_copied_real_flutter_output_is_lossless_except_excluded_fonts(self):
        original = ROOT / "build/admin-cloudflare"
        copied = self.directory / "actual-admin-copy"
        copied.mkdir()
        shutil.copytree(original / "assets", copied / "assets")
        for marker in ("index.html", "flutter_bootstrap.js"):
            shutil.copy2(original / marker, copied / marker)
        source_before = snapshot(ROOT / "assets/typefaces")
        original_manifests = {name: (original / "assets" / name).read_bytes() for name in assets.MANIFESTS}
        original_decoded = assets.decode_manifest(original_manifests["AssetManifest.bin"])
        self.assertEqual(original_manifests["AssetManifest.bin"], assets.encode_manifest(original_decoded))
        before = snapshot(copied)
        font_before = json.loads(original_manifests["FontManifest.json"])
        receipt = assets.prune_admin_fonts(copied)
        excluded = set(receipt["removed_assets"])
        manifest_excluded = excluded | set(receipt['excluded_metadata_assets'])
        expected_rows = tuple((key, value) for key, value in original_decoded.value if key.value not in manifest_excluded)
        actual_rows = assets.decode_manifest((copied / "assets/AssetManifest.bin").read_bytes()).value
        self.assertEqual(expected_rows, actual_rows)  # all values, types, metadata/map order
        expected_fonts = [family for family in font_before if family["family"] != "Aeonik Pro"]
        self.assertEqual(expected_fonts, json.loads((copied / "assets/FontManifest.json").read_bytes()))
        after = snapshot(copied)
        changed_manifests = {"assets/" + name for name in assets.MANIFESTS} if receipt["changed"] else set()
        for relative, digest in before.items():
            if relative in {"assets/" + name for name in excluded}:
                self.assertNotIn(relative, after)
            elif relative not in changed_manifests:
                self.assertEqual(digest, after[relative], relative)
        wrapped = json.loads((copied / "assets/AssetManifest.bin.json").read_bytes())
        self.assertEqual((copied / "assets/AssetManifest.bin").read_bytes(), base64.b64decode(wrapped, validate=True))
        self.assertEqual(source_before, snapshot(ROOT / "assets/typefaces"))
        self.assertEqual(original_manifests, {name: (original / "assets" / name).read_bytes() for name in assets.MANIFESTS})
        self.assertFalse(assets.prune_admin_fonts(copied)["changed"])

    def test_cli_has_actionable_json_and_nonzero_refusal(self):
        completed = subprocess.run([sys.executable, str(SCRIPT), str(self.build)], text=True, capture_output=True, check=False)
        self.assertEqual(0, completed.returncode, completed.stderr)
        self.assertEqual([MEDIUM, REGULAR], json.loads(completed.stdout)["removed_assets"])
        (self.build / "assets/AssetManifest.bin.json").write_text("{}")
        refused = subprocess.run([sys.executable, str(SCRIPT), str(self.build)], text=True, capture_output=True, check=False)
        self.assertEqual(1, refused.returncode)
        self.assertEqual("", refused.stdout)
        self.assertIn("must be a base64 JSON string", refused.stderr)

    def test_local_engine_fallback_uses_existing_inter_bytes_and_is_idempotent(self):
        before = snapshot(self.build)
        receipt = assets.prune_admin_fonts(self.build, local_engine_fallback=True)
        fonts = json.loads((self.build / "assets/FontManifest.json").read_bytes())
        self.assertEqual("Inter", receipt["local_engine_fallback"])
        self.assertEqual({"family": "Roboto", "fonts": self.fonts[0]["fonts"]}, fonts[-1])
        self.assertEqual(before["assets/" + INTER], snapshot(self.build)["assets/" + INTER])
        replay = snapshot(self.build)
        self.assertFalse(assets.prune_admin_fonts(self.build, local_engine_fallback=True)["changed"])
        self.assertEqual(replay, snapshot(self.build))

    def test_missing_inter_or_foreign_fallback_fails_before_mutation(self):
        for fonts in (self.fonts[1:], [*self.fonts, {"family": "Roboto", "fonts": [{"asset": LOGO}]}]):
            self.write_fonts(fonts)
            before = snapshot(self.build)
            with self.assertRaises(assets.ManifestError):
                assets.prune_admin_fonts(self.build, local_engine_fallback=True)
            self.assertEqual(before, snapshot(self.build))

    def test_web_wrapper_disagreement_or_invalid_base64_is_refused(self):
        for wrapper in ("not-base64!", base64.b64encode(b"different bytes").decode(), {}, []):
            with self.subTest(wrapper=wrapper):
                (self.build / "assets/AssetManifest.bin.json").write_text(json.dumps(wrapper))
                self.assert_refused_unchanged()

    def test_malformed_binary_is_refused_before_any_changes(self):
        good = fixture_manifest((LOGO, REGULAR, INTER, MEDIUM))
        cases = [b"", good[:-1], good + b"\x00", b"\x0d\xff\xff\xff\xff\xff", b"\x0f", b"\x0d\x01\x07\x01\xff\x00", b"\x0d\xfe\x01\x00"]
        for binary in cases:
            with self.subTest(binary=binary[:12]):
                write_manifest(self.build, binary)
                self.assert_refused_unchanged()

    def test_duplicate_binary_keys_and_wrong_manifest_shapes_are_refused(self):
        for binary in (fixture_manifest((INTER, INTER)), b"\x0c\x00", b"\x0d\x01" + sdk_string(INTER) + b"\x00", b"\x0d\x01" + sdk_string(INTER) + b"\x0c\x00"):
            with self.subTest(binary=binary[:12]):
                write_manifest(self.build, binary)
                self.assert_refused_unchanged()

    def test_malformed_font_json_duplicate_keys_and_nonfinite_values_are_refused(self):
        for raw in (b"{", b"{}", b"\xff", b'[ {"family":"Inter","family":"Aeonik Pro","fonts":[]} ]', b'[{"family":"Inter","fonts":[{"asset":"assets/typefaces/Inter-Variable.ttf","weight":true}]}]', b'[{"family":"Inter","fonts":[{"asset":"assets/typefaces/Inter-Variable.ttf"}],"other":NaN}]', b'[{"family":"Inter","fonts":[{"asset":"assets/typefaces/Inter-Variable.ttf"}],"other":1e999}]', b'[{"family":"\\ud800","fonts":[]}]', b'[{"family":"Inter","fonts":[],"other":' + b'9' * 5000 + b'}]'):
            with self.subTest(raw=raw[:45]):
                (self.build / "assets/FontManifest.json").write_bytes(raw)
                self.assert_refused_unchanged()

    def test_path_traversal_absolute_paths_encoded_traversal_and_backslashes_fail(self):
        for unsafe in ("../outside.ttf", "/tmp/outside.ttf", "assets/../outside.ttf", "assets/%2e%2e/outside.ttf", "assets\\outside.ttf", "assets//outside.ttf", "assets/./outside.ttf", "C:/outside.ttf", "assets/zero\0.ttf"):
            with self.subTest(unsafe=unsafe):
                write_manifest(self.build, fixture_manifest((unsafe,)))
                self.assert_refused_unchanged()
        write_manifest(self.build, fixture_manifest((LOGO, REGULAR, INTER, MEDIUM)))
        fonts = json.loads(json.dumps(self.fonts))
        fonts[1]["fonts"][0]["asset"] = "../../source-font.ttf"
        self.write_fonts(fonts)
        self.assert_refused_unchanged()
        with self.assertRaises(assets.ManifestError):
            assets.prune_admin_fonts(self.build / ".." / self.build.name)

    def test_symlinked_files_directories_and_output_roots_fail(self):
        for relative in ("assets/AssetManifest.bin", "assets/" + REGULAR, "index.html"):
            with self.subTest(relative=relative):
                path = self.build / relative
                content = path.read_bytes()
                target = self.directory / "unrelated-original"
                target.write_bytes(content)
                path.unlink()
                path.symlink_to(target)
                self.assert_refused_unchanged()
                self.assertEqual(content, target.read_bytes())
                path.unlink()
                path.write_bytes(content)
        link = self.build / "unrelated-output-alias"
        link.symlink_to(self.directory, target_is_directory=True)
        self.assert_refused_unchanged()
        link.unlink()
        root_link = self.directory / "linked-build"
        root_link.symlink_to(self.build, target_is_directory=True)
        with self.assertRaises(assets.ManifestError):
            assets.prune_admin_fonts(root_link)

    def test_hardlinked_source_and_missing_assets_are_refused(self):
        source = self.directory / "source-original-font"
        source.write_bytes(b"retained source original")
        font = self.build / "assets" / REGULAR
        font.unlink()
        os.link(source, font)
        self.assert_refused_unchanged()
        self.assertEqual(b"retained source original", source.read_bytes())
        font.unlink()
        self.assert_refused_unchanged()

    def test_other_font_family_cannot_alias_excluded_assets(self):
        aliases = [{"family": "Something else", "fonts": [{"asset": REGULAR}]}, *self.fonts]
        self.write_fonts(aliases)
        self.assert_refused_unchanged()
        self.write_fonts(self.fonts)
        # A nonexcluded asset key sharing Aeonik bytes is also refused.
        aliased = b"\x0d\x05" + fixture_manifest((LOGO, REGULAR, INTER, MEDIUM))[2:]
        aliased += sdk_string("assets/font-alias.ttf") + b"\x0c\x01\x0d\x01" + sdk_string("asset") + sdk_string(REGULAR)
        write_manifest(self.build, aliased)
        self.assert_refused_unchanged()

    def test_partial_previous_prune_can_remove_orphaned_excluded_files(self):
        self.write_fonts(self.fonts[:1])
        write_manifest(self.build, fixture_manifest((LOGO, INTER)))
        receipt = assets.prune_admin_fonts(self.build)
        self.assertEqual([MEDIUM, REGULAR], receipt["removed_assets"])
        self.assertIsNone(receipt["removed_font_family"])
        self.assertEqual((2, 2), (receipt["asset_entries_before"], receipt["asset_entries_after"]))

    def test_prune_crosses_sdk_map_size_boundary_and_preserves_float_metadata(self):
        retained = [INTER, *[f"assets/item-{index}.bin" for index in range(252)]]
        paths = [REGULAR, MEDIUM, *retained]
        binary = bytearray(b"\x0d\xfe" + struct.pack("=H", 255))
        for path in paths:
            file = self.build / "assets" / path
            file.parent.mkdir(parents=True, exist_ok=True)
            if not file.exists():
                file.write_bytes(b"unchanged asset")
            binary.extend(sdk_string(path) + b"\x0c\x01\x0d\x02")
            binary.extend(sdk_string("asset") + sdk_string(path))
            binary.extend(sdk_string("dpr") + b"\x06")
            binary.extend(b"\0" * ((-len(binary)) % 8) + struct.pack("=d", 2.0))
        write_manifest(self.build, bytes(binary))
        prior = assets.decode_manifest(bytes(binary))
        expected = tuple((key, value) for key, value in prior.value if key.value in retained)
        before = snapshot(self.build)
        receipt = assets.prune_admin_fonts(self.build)
        output = (self.build / "assets/AssetManifest.bin").read_bytes()
        self.assertEqual(b"\x0d\xfd", output[:2])  # uint16 -> one-byte map size
        self.assertEqual((255, 253), (receipt["asset_entries_before"], receipt["asset_entries_after"]))
        self.assertEqual(expected, assets.decode_manifest(output).value)
        after = snapshot(self.build)
        for path in retained:
            self.assertEqual(before["assets/" + path], after["assets/" + path])

    def test_unexpected_io_failure_rolls_back_all_affected_output(self):
        before = snapshot(self.build)
        real_replace = assets.os.replace
        failed = False

        def fail_once(source, destination):
            nonlocal failed
            if Path(destination).name == "AssetManifest.bin" and not failed:
                failed = True
                raise OSError("simulated publish failure")
            return real_replace(source, destination)

        with patch.object(assets.os, "replace", side_effect=fail_once), self.assertRaises(OSError):
            assets.prune_admin_fonts(self.build)
        self.assertTrue(failed)
        self.assertEqual(before, snapshot(self.build))
        self.assertFalse(any(self.build.glob(".admin-font-prune-*")))

    def test_requires_generated_output_markers_and_rejects_source_asset_folder(self):
        (self.build / "flutter_bootstrap.js").unlink()
        self.assert_refused_unchanged()
        with self.assertRaises(assets.ManifestError):
            assets.prune_admin_fonts(ROOT / "assets")


class StandardMessageCodecManifestTest(unittest.TestCase):
    def test_sdk_numeric_types_alignment_and_nested_map_order_are_preserved(self):
        # Hand-coded SDK bytes include every standard scalar/typed-data type.
        # Original scalar payloads survive even when container offsets change.
        binary = bytearray(b"\x0d\x01" + sdk_string("assets/example.bin") + b"\x0c\x01\x0d\x0d")
        binary.extend(sdk_string("asset") + sdk_string("assets/example.bin"))
        binary.extend(sdk_string("dpr") + b"\x06")
        binary.extend(b"\0" * ((-len(binary)) % 8) + struct.pack("=d", 2.0))
        for key, wire in (("integer", b"\x03" + struct.pack("=i", -7)), ("large", b"\x04" + struct.pack("=q", 4294967297)), ("bool", b"\x01"), ("false", b"\x02"), ("null", b"\x00"), ("hex", b"\x05\x04abcd"), ("bytes", b"\x08\x03\x01\x02\x03")):
            binary.extend(sdk_string(key) + wire)
        for key, tag, width, wire in (("ints", 9, 4, struct.pack("=i", -2)), ("longs", 10, 8, struct.pack("=q", 3)), ("floats", 14, 4, struct.pack("=f", 1.5)), ("doubles", 11, 8, struct.pack("=d", 1.25))):
            binary.extend(sdk_string(key) + bytes([tag, 1]))
            binary.extend(b"\0" * ((-len(binary)) % width) + wire)
        decoded = assets.decode_manifest(bytes(binary))
        self.assertEqual(bytes(binary), assets.encode_manifest(decoded))
        fields = decoded.value[0][1].value[0].value
        self.assertEqual(["asset", "dpr", "integer", "large", "bool", "false", "null", "hex", "bytes", "ints", "longs", "floats", "doubles"], [key.value for key, _ in fields])
        # Re-encoding after prepending an asset changes double alignment but
        # preserves every metadata value and key order in the original row.
        another = assets.decode_manifest(fixture_manifest((LOGO,))).value[0]
        shifted = assets.CodecValue(13, (another, *decoded.value))
        encoded = assets.encode_manifest(shifted)
        self.assertEqual(shifted, assets.decode_manifest(encoded))
        assets._asset_manifest(shifted)

    def test_extended_string_and_map_sizes_follow_sdk_uint16_uint32_format(self):
        # 254-byte UTF-8 string and 65536-byte string exercise both size labels.
        for length, size_wire in ((254, b"\xfe" + struct.pack("=H", 254)), (65536, b"\xff" + struct.pack("=I", 65536))):
            raw = b"\x07" + size_wire + b"a" * length
            self.assertEqual(raw, assets.encode_manifest(assets.decode_manifest(raw)))
        pair = lambda number: sdk_string(str(number)) + b"\x00"
        raw = b"\x0d\xfe" + struct.pack("=H", 254) + b"".join(pair(index) for index in range(254))
        self.assertEqual(raw, assets.encode_manifest(assets.decode_manifest(raw)))

    def test_invalid_padding_and_dpr_do_not_pass_as_valid_manifests(self):
        prefix = bytearray(b"\x0d\x01" + sdk_string(LOGO) + b"\x0c\x01\x0d\x02")
        prefix.extend(sdk_string("asset") + sdk_string(LOGO) + sdk_string("dpr") + b"\x06")
        padding = (-len(prefix)) % 8
        valid = bytes(prefix) + b"\0" * padding + struct.pack("=d", float("nan"))
        with self.assertRaises(assets.ManifestError):
            assets._asset_manifest(assets.decode_manifest(valid))
        if padding:
            corrupt = bytes(prefix) + b"\x01" + b"\0" * (padding - 1) + struct.pack("=d", 2.0)
            with self.assertRaises(assets.ManifestError):
                assets.decode_manifest(corrupt)


if __name__ == "__main__":
    unittest.main()
