#!/usr/bin/env python3
"""Exclude website-derived Aeonik Pro fonts from an existing Admin web build.

Usage: python3 scripts/admin_cloudflare_assets.py build/admin-cloudflare

This edits build output only. Flutter's web AssetManifest.bin.json is a JSON
string wrapping base64 StandardMessageCodec bytes, not an ordinary asset map.
The codec below follows Flutter services/message_codecs.dart and foundation/
serialization.dart: host-endian sizes/numbers, absolute-message alignment for
doubles/typed data, ordered maps, and the original scalar type discriminators.
No Flutter build, source edit, or deployment is performed.
"""

from __future__ import annotations

import argparse
import base64
import binascii
from dataclasses import dataclass
import json
import math
import os
from pathlib import Path
import re
import stat
import struct
import sys
import tempfile
from urllib.parse import unquote


FONT_FAMILY = "Aeonik Pro"
MANIFESTS = ("FontManifest.json", "AssetManifest.bin", "AssetManifest.bin.json")
MAX_MANIFEST_BYTES = 64 * 1024 * 1024
MAX_CODEC_DEPTH = 100
_ENDIAN = "<" if sys.byteorder == "little" else ">"
_AEONIK_PATH = re.compile(r"assets/typefaces/AeonikPro(?:-[A-Za-z0-9_-]+)?\.(?:ttf|otf|woff2?)\Z")


class ManifestError(ValueError):
    """An unsafe or inconsistent build is refused before any output mutation."""


@dataclass(frozen=True)
class CodecValue:
    tag: int
    value: object


class _CodecReader:
    def __init__(self, data: bytes):
        self.data = data
        self.offset = 0

    def take(self, size: int) -> bytes:
        if size < 0 or size > len(self.data) - self.offset:
            raise ManifestError("Truncated StandardMessageCodec manifest")
        result = self.data[self.offset:self.offset + size]
        self.offset += size
        return result

    def size(self) -> int:
        marker = self.take(1)[0]
        if marker == 254:
            value = struct.unpack(_ENDIAN + "H", self.take(2))[0]
            if value < 254:
                raise ManifestError("Noncanonical StandardMessageCodec size")
            return value
        if marker == 255:
            value = struct.unpack(_ENDIAN + "I", self.take(4))[0]
            if value <= 65535:
                raise ManifestError("Noncanonical StandardMessageCodec size")
            return value
        return marker

    def align(self, width: int) -> None:
        if any(self.take((-self.offset) % width)):
            raise ManifestError("Nonzero StandardMessageCodec alignment padding")

    def read(self, depth: int = 0) -> CodecValue:
        if depth > MAX_CODEC_DEPTH:
            raise ManifestError("StandardMessageCodec nesting exceeds the safe limit")
        tag = self.take(1)[0]
        if tag in (0, 1, 2):
            return CodecValue(tag, None)
        if tag in (3, 4):
            return CodecValue(tag, self.take(4 if tag == 3 else 8))
        if tag == 6:
            self.align(8)
            return CodecValue(tag, self.take(8))
        if tag in (5, 7):
            raw = self.take(self.size())
            try:
                value = raw.decode("utf-8", errors="strict")
            except UnicodeDecodeError as error:
                raise ManifestError("Invalid UTF-8 in StandardMessageCodec string") from error
            return CodecValue(tag, value)
        if tag in (8, 9, 10, 11, 14):
            count = self.size()
            width = {8: 1, 9: 4, 10: 8, 11: 8, 14: 4}[tag]
            self.align(width)
            return CodecValue(tag, self.take(count * width))
        if tag in (12, 13):
            count = self.size()
            if count * (2 if tag == 13 else 1) > len(self.data) - self.offset:
                raise ManifestError("Impossible StandardMessageCodec collection size")
            if tag == 12:
                return CodecValue(tag, tuple(self.read(depth + 1) for _ in range(count)))
            pairs = []
            seen = set()
            for _ in range(count):
                key = self.read(depth + 1)
                # Flutter asset maps and their metadata use string keys. Refuse
                # duplicate keys rather than silently collapsing another asset.
                if key.tag != 7 or key.value in seen:
                    raise ManifestError("Asset manifest maps require unique string keys")
                seen.add(key.value)
                pairs.append((key, self.read(depth + 1)))
            return CodecValue(tag, tuple(pairs))
        raise ManifestError(f"Unsupported StandardMessageCodec discriminator: {tag}")


def decode_manifest(data: bytes) -> CodecValue:
    if not data or len(data) > MAX_MANIFEST_BYTES:
        raise ManifestError("Binary asset manifest is empty or too large")
    reader = _CodecReader(data)
    result = reader.read()
    if reader.offset != len(data):
        raise ManifestError("Trailing bytes in StandardMessageCodec manifest")
    return result


def encode_manifest(value: CodecValue) -> bytes:
    output = bytearray()

    def size(count: int) -> None:
        if count < 254:
            output.append(count)
        elif count <= 65535:
            output.append(254)
            output.extend(struct.pack(_ENDIAN + "H", count))
        else:
            output.append(255)
            output.extend(struct.pack(_ENDIAN + "I", count))

    def align(width: int) -> None:
        output.extend(b"\0" * ((-len(output)) % width))

    def write(node: CodecValue) -> None:
        output.append(node.tag)
        if node.tag in (0, 1, 2):
            return
        if node.tag in (3, 4):
            output.extend(node.value)
        elif node.tag == 6:
            align(8)
            output.extend(node.value)
        elif node.tag in (5, 7):
            raw = node.value.encode("utf-8")
            size(len(raw))
            output.extend(raw)
        elif node.tag in (8, 9, 10, 11, 14):
            width = {8: 1, 9: 4, 10: 8, 11: 8, 14: 4}[node.tag]
            size(len(node.value) // width)
            align(width)
            output.extend(node.value)
        elif node.tag == 12:
            size(len(node.value))
            for item in node.value:
                write(item)
        elif node.tag == 13:
            size(len(node.value))
            for key, item in node.value:
                write(key)
                write(item)
        else:
            raise ManifestError(f"Unsupported StandardMessageCodec discriminator: {node.tag}")

    write(value)
    return bytes(output)


def _unique_json_object(pairs: list[tuple[str, object]]) -> dict:
    result = {}
    for key, value in pairs:
        if key in result:
            raise ManifestError(f"Duplicate JSON key: {key}")
        result[key] = value
    return result


def _load_json(data: bytes, label: str) -> object:
    if not data or len(data) > MAX_MANIFEST_BYTES:
        raise ManifestError(f"{label} is empty or too large")

    def reject_constant(value: str) -> None:
        raise ManifestError(f"Invalid JSON number: {value}")

    def finite_float(value: str) -> float:
        number = float(value)
        if not math.isfinite(number):
            raise ManifestError("JSON number exceeds the finite range")
        return number

    def validate_strings(value: object, depth: int = 0) -> None:
        if depth > MAX_CODEC_DEPTH:
            raise ManifestError("JSON manifest nesting exceeds the safe limit")
        if isinstance(value, str):
            value.encode("utf-8", errors="strict")
        elif isinstance(value, list):
            for item in value:
                validate_strings(item, depth + 1)
        elif isinstance(value, dict):
            for key, item in value.items():
                validate_strings(key, depth + 1)
                validate_strings(item, depth + 1)

    try:
        value = json.loads(
            data.decode("utf-8", errors="strict"),
            object_pairs_hook=_unique_json_object,
            parse_constant=reject_constant,
            parse_float=finite_float,
        )
        validate_strings(value)
        return value
    except ManifestError:
        raise
    except (ValueError, RecursionError) as error:
        raise ManifestError(f"Malformed {label}") from error


def _asset_path(value: object) -> str:
    if not isinstance(value, str) or not value:
        raise ManifestError("Asset paths must be nonempty strings")
    for candidate in (value, unquote(value)):
        if (
            candidate.startswith("/") or "\\" in candidate or ":" in candidate
            or any(ord(character) < 32 or ord(character) == 127 for character in candidate)
            or any(part in ("", ".", "..") for part in candidate.split("/"))
        ):
            raise ManifestError(f"Unsafe asset path: {value!r}")
    return value


def _regular_file(path: Path) -> os.stat_result:
    try:
        information = path.lstat()
    except OSError as error:
        raise ManifestError(f"Required build file is unavailable: {path.name}") from error
    if not stat.S_ISREG(information.st_mode) or information.st_nlink != 1:
        raise ManifestError(f"Build files must be regular, unlinked files: {path.name}")
    return information


def _validate_root(build: Path) -> tuple[Path, dict[Path, os.stat_result]]:
    if ".." in build.parts:
        raise ManifestError("Build output path must not contain parent traversal")
    root = Path(os.path.abspath(build.expanduser()))
    for component in (*reversed(root.parents), root):
        if component.is_symlink():
            raise ManifestError(f"Build output path contains a symlink: {component}")
    if not root.is_dir() or not (root / "assets").is_dir():
        raise ManifestError("Expected a Flutter web build directory containing assets/")
    # These generated files distinguish an output bundle from source assets.
    _regular_file(root / "index.html")
    _regular_file(root / "flutter_bootstrap.js")
    files = {}
    def walk_error(error: OSError) -> None:
        raise ManifestError("Cannot inspect the complete build output") from error

    for folder, directories, names in os.walk(root, followlinks=False, onerror=walk_error):
        parent = Path(folder)
        for name in directories:
            if not stat.S_ISDIR((parent / name).lstat().st_mode):
                raise ManifestError(f"Build output contains a symlink or special directory: {name}")
        for name in names:
            path = parent / name
            files[path] = _regular_file(path)
    return root, files


def _font_manifest(data: bytes) -> tuple[list, list, set[str]]:
    families = _load_json(data, "FontManifest.json")
    if not isinstance(families, list):
        raise ManifestError("FontManifest.json must contain a list")
    kept, removed, names = [], [], set()
    declared = set()
    for family in families:
        if not isinstance(family, dict) or not isinstance(family.get("family"), str) or not family["family"]:
            raise ManifestError("Font manifest family is malformed")
        if family["family"] in names:
            raise ManifestError("Duplicate font manifest family")
        names.add(family["family"])
        fonts = family.get("fonts")
        if not isinstance(fonts, list) or not fonts:
            raise ManifestError("Font manifest fonts must be a nonempty list")
        for font in fonts:
            if not isinstance(font, dict) or "asset" not in font:
                raise ManifestError("Font manifest font is malformed")
            asset = _asset_path(font["asset"])
            for number in ("weight",):
                if number in font and (type(font[number]) is not int or not 1 <= font[number] <= 1000):
                    raise ManifestError("Font weight is malformed")
            if "style" in font and font["style"] not in ("normal", "italic"):
                raise ManifestError("Font style is malformed")
            if family["family"] == FONT_FAMILY:
                if not _AEONIK_PATH.fullmatch(asset):
                    raise ManifestError("Aeonik Pro family references an unexpected font asset")
                declared.add(asset)
            elif _AEONIK_PATH.fullmatch(asset):
                raise ManifestError("Another font family aliases an excluded Aeonik Pro asset")
        (removed if family["family"] == FONT_FAMILY else kept).append(family)
    return kept, removed, declared


def _asset_manifest(value: CodecValue) -> dict[str, tuple[str, ...]]:
    if value.tag != 13:
        raise ManifestError("AssetManifest.bin must contain a map")
    entries = {}
    for key, variants in value.value:
        asset = _asset_path(key.value)
        if variants.tag != 12 or not variants.value:
            raise ManifestError("Each asset manifest entry must have a nonempty variant list")
        paths = []
        for variant in variants.value:
            if variant.tag != 13:
                raise ManifestError("Asset variants must contain metadata maps")
            fields = {name.value: item for name, item in variant.value}
            if "asset" not in fields or fields["asset"].tag != 7:
                raise ManifestError("Asset variant is missing its string asset path")
            paths.append(_asset_path(fields["asset"].value))
            if "dpr" in fields:
                item = fields["dpr"]
                if item.tag == 3:
                    number = struct.unpack(_ENDIAN + "i", item.value)[0]
                elif item.tag == 4:
                    number = struct.unpack(_ENDIAN + "q", item.value)[0]
                elif item.tag == 6:
                    number = struct.unpack(_ENDIAN + "d", item.value)[0]
                else:
                    raise ManifestError("Asset dpr must be a finite positive number")
                if not math.isfinite(number) or number <= 0:
                    raise ManifestError("Asset dpr must be a finite positive number")
        if len(set(paths)) != len(paths):
            raise ManifestError("Duplicate asset variant path")
        entries[asset] = tuple(paths)
    return entries


def _publish(root: Path, original: dict[Path, bytes], replacements: dict[Path, bytes],
             removed: list[Path], files: dict[Path, os.stat_result]) -> None:
    # Stage all replacements and rollback material before touching the bundle.
    # Validation failures never reach here. Unexpected I/O failures roll back
    # the affected manifests and deleted files before being reported.
    with tempfile.TemporaryDirectory(prefix=".admin-font-prune-", dir=root) as directory:
        scratch = Path(directory)
        staged, backups = {}, {}
        for index, (path, data) in enumerate(replacements.items()):
            staged[path] = scratch / f"new-{index}"
            backups[path] = scratch / f"old-{index}"
            for target, content in ((staged[path], data), (backups[path], original[path])):
                with target.open("xb") as output:
                    output.write(content)
                    output.flush()
                    os.fsync(output.fileno())
                target.chmod(stat.S_IMODE(files[path].st_mode))
        for path in (*replacements, *removed):
            current = _regular_file(path)
            prior = files[path]
            if (current.st_dev, current.st_ino, current.st_size, current.st_mtime_ns) != (
                prior.st_dev, prior.st_ino, prior.st_size, prior.st_mtime_ns
            ) or (path in original and path.read_bytes() != original[path]):
                raise ManifestError("Build output changed while preparing the font prune")
        moved, changed = [], []
        try:
            for index, path in enumerate(removed):
                saved = scratch / f"font-{index}"
                os.replace(path, saved)
                moved.append((path, saved))
            for path, staged_path in staged.items():
                os.replace(staged_path, path)
                changed.append(path)
        except BaseException:
            for path in reversed(changed):
                os.replace(backups[path], path)
            for path, saved in reversed(moved):
                os.replace(saved, path)
            raise


def prune_admin_fonts(build: Path | str, *, local_engine_fallback: bool = False) -> dict:
    """Validate and prune an existing output bundle; return a JSON-safe receipt."""
    root, files = _validate_root(Path(build))
    assets = root / "assets"

    def registered_file(path: Path) -> os.stat_result:
        information = _regular_file(path)
        if path not in files:
            raise ManifestError("Asset path does not match the exact file name in the output bundle")
        return information

    manifest_paths = {name: assets / name for name in MANIFESTS}
    original = {}
    for name, path in manifest_paths.items():
        information = registered_file(path)
        if information.st_size > MAX_MANIFEST_BYTES:
            raise ManifestError(f"{name} is too large")
        original[path] = path.read_bytes()
    fonts, families_removed, declared = _font_manifest(original[manifest_paths["FontManifest.json"]])
    binary = original[manifest_paths["AssetManifest.bin"]]
    wrapper = _load_json(original[manifest_paths["AssetManifest.bin.json"]], "AssetManifest.bin.json")
    if not isinstance(wrapper, str):
        raise ManifestError("AssetManifest.bin.json must be a base64 JSON string")
    try:
        wrapped_binary = base64.b64decode(wrapper, validate=True)
    except (ValueError, binascii.Error) as error:
        raise ManifestError("Malformed web asset manifest base64") from error
    if wrapped_binary != binary or base64.b64encode(binary).decode("ascii") != wrapper:
        raise ManifestError("Binary and web asset manifests disagree")
    manifest = decode_manifest(binary)
    entries = _asset_manifest(manifest)
    excluded = set(declared)
    excluded.update(path for path in entries if _AEONIK_PATH.fullmatch(path))
    excluded.update(path for paths in entries.values() for path in paths if _AEONIK_PATH.fullmatch(path))
    excluded.update(path.relative_to(assets).as_posix() for path in files
                    if path.is_relative_to(assets) and _AEONIK_PATH.fullmatch(path.relative_to(assets).as_posix()))
    for asset, variants in entries.items():
        if asset in excluded:
            if any(path not in excluded for path in variants):
                raise ManifestError("Excluded asset aliases a retained asset variant")
        elif any(path in excluded for path in variants):
            raise ManifestError("Retained asset aliases an excluded Aeonik Pro variant")
        for variant in variants:
            registered_file(assets / variant)
    for font_family in (*fonts, *families_removed):
        for font in font_family["fonts"]:
            registered_file(assets / font["asset"])
    fallback_added = False
    if local_engine_fallback:
        # CanvasKit unconditionally downloads its default Roboto family when
        # that family is absent. Register the existing licensed Inter bytes
        # under the engine's fallback alias; product typography remains Inter.
        # This is generated Admin output only, not a source-font replacement.
        inter = next((family for family in fonts if family["family"] == "Inter"), None)
        if inter is None:
            raise ManifestError("The local engine fallback requires bundled Inter")
        fallback = {"family": "Roboto", "fonts": inter["fonts"]}
        existing = next((family for family in fonts if family["family"] == "Roboto"), None)
        if existing is not None and existing != fallback:
            raise ManifestError("The engine fallback must alias the exact bundled Inter fonts")
        if existing is None:
            fonts.append(fallback)
            fallback_added = True
    for path in declared:
        if path not in entries or path not in entries[path]:
            raise ManifestError("Aeonik Pro font is absent from the asset manifest")
    removed_paths = sorted(excluded)
    removed_files = [assets / path for path in removed_paths]
    for path in removed_files:
        registered_file(path)
    kept_entries = tuple((key, value) for key, value in manifest.value if key.value not in excluded)
    new_binary = encode_manifest(CodecValue(13, kept_entries))
    # A lossless round trip proves this helper understands all original values.
    if encode_manifest(manifest) != binary:
        raise ManifestError("Asset manifest cannot be losslessly re-encoded")
    replacements = {}
    if excluded or families_removed or fallback_added:
        replacements = {
            manifest_paths["FontManifest.json"]: json.dumps(fonts, ensure_ascii=False, separators=(",", ":")).encode("utf-8"),
            manifest_paths["AssetManifest.bin"]: new_binary,
            manifest_paths["AssetManifest.bin.json"]: json.dumps(base64.b64encode(new_binary).decode("ascii")).encode("utf-8"),
        }
        _publish(root, original, replacements, removed_files, files)
    return {
        "build_output": str(root),
        "removed_font_family": FONT_FAMILY if families_removed else None,
        "removed_assets": removed_paths,
        "asset_entries_before": len(entries),
        "asset_entries_after": len(kept_entries),
        "changed": bool(replacements),
        "local_engine_fallback": "Inter" if local_engine_fallback else None,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("build_output", type=Path, help="Existing Admin Flutter web output directory")
    parser.add_argument("--local-engine-fallback", action="store_true",
                        help="Alias bundled Inter for CanvasKit's default fallback without a CDN download")
    arguments = parser.parse_args(argv)
    try:
        receipt = prune_admin_fonts(arguments.build_output, local_engine_fallback=arguments.local_engine_fallback)
    except (ManifestError, OSError) as error:
        print(f"Admin font prune refused: {error}", file=sys.stderr)
        return 1
    print(json.dumps(receipt, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
