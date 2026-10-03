"""Untrusted bytes enter only this disposable, networkless, limited process.

Not a malware scanner. Complete supported codecs/pages are decoded; container
structure, expansion, workbook cell semantics and active content are bounded.
No user text or parser exception is emitted in an error.
"""
from __future__ import annotations

import base64
import ctypes
import errno
import hashlib
import io
import json
import math
import os
import platform
import re
import resource
import sys
import warnings
import zipfile
import zlib

POLICY = "collect-roster-decoder-v1"
MAX_INPUT = 5 * 1024 * 1024
MAX_PIXELS = 16_000_000
MAX_SIDE = 16_000
MAX_FRAMES = 20
MAX_PAGES = 20
MAX_EXPANDED = 32 * 1024 * 1024
TOOLCHAIN = {
    "python": "3.12", "pillow": "12.0.0", "pypdfium2": "5.2.0",
    "pypdf": "6.7.0", "openpyxl": "3.1.5", "defusedxml": "0.7.1",
}


class Rejected(Exception):
    pass


def reject(code="roster_invalid_file"):
    raise Rejected(code)


def isolate():
    if sys.platform != "linux":
        reject("roster_decoder_sandbox_unavailable")
    resource.setrlimit(resource.RLIMIT_AS, (384 * 1024 * 1024,) * 2)
    resource.setrlimit(resource.RLIMIT_CPU, (4, 5))
    resource.setrlimit(resource.RLIMIT_FSIZE, (0, 0))
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    resource.setrlimit(resource.RLIMIT_NOFILE, (32, 32))
    # Classic seccomp: fail closed on an unrecognized architecture. The child
    # cannot create sockets, connect, spawn, execute or use ptrace. Imports and
    # stdin/stdout are available; the whole container filesystem is read-only.
    machine = platform.machine()
    numbers = {
        "x86_64": [41, 42, 43, 49, 50, 53, 56, 57, 58, 59, 101, 288, 322, 435],
        "aarch64": [198, 199, 200, 201, 202, 203, 220, 221, 117, 242, 281, 435],
    }.get(machine)
    if numbers is None:
        reject("roster_decoder_sandbox_unavailable")
    class Filter(ctypes.Structure):
        _fields_ = [("code", ctypes.c_ushort), ("jt", ctypes.c_ubyte),
                    ("jf", ctypes.c_ubyte), ("k", ctypes.c_uint32)]
    class Program(ctypes.Structure):
        _fields_ = [("length", ctypes.c_ushort), ("filters", ctypes.POINTER(Filter))]
    # Check the audit architecture before syscall numbers (reject x32 too).
    arch = 0xc000003e if machine == "x86_64" else 0xc00000b7
    operations = [(0x20, 0, 0, 4), (0x15, 1, 0, arch), (0x06, 0, 0, 0x80000000),
                  (0x20, 0, 0, 0)]
    for number in numbers:
        operations.extend([(0x15, 0, 1, number), (0x06, 0, 0, 0x00050000 | errno.EPERM)])
    if machine == "x86_64":
        operations.extend([(0x35, 0, 1, 0x40000000), (0x06, 0, 0, 0x80000000)])
    operations.append((0x06, 0, 0, 0x7fff0000))
    filters = (Filter * len(operations))(*(Filter(*op) for op in operations))
    program = Program(len(filters), filters)
    libc = ctypes.CDLL(None, use_errno=True)
    if libc.prctl(38, 1, 0, 0, 0) != 0 or libc.prctl(22, 2, ctypes.byref(program), 0, 0) != 0:
        reject("roster_decoder_sandbox_unavailable")


def dimensions(width, height):
    if not all(isinstance(v, (int, float)) and math.isfinite(v) and 0 < v <= MAX_SIDE
               for v in (width, height)) or width * height > MAX_PIXELS:
        reject("roster_image_dimensions_exceeded")


def image(source, mime):
    from PIL import Image, ImageFile
    Image.MAX_IMAGE_PIXELS = MAX_PIXELS
    ImageFile.LOAD_TRUNCATED_IMAGES = False
    expected = {"image/png": "PNG", "image/jpeg": "JPEG", "image/webp": "WEBP"}[mime]
    with warnings.catch_warnings():
        warnings.simplefilter("error", Image.DecompressionBombWarning)
        # verify() catches PNG CRC/structural failures; load() independently
        # decodes every frame, including entropy and compressed image streams.
        with Image.open(io.BytesIO(source), formats=[expected]) as check:
            dimensions(*check.size)
            check.verify()
        with Image.open(io.BytesIO(source), formats=[expected]) as decoded:
            frames = getattr(decoded, "n_frames", 1)
            if not 1 <= frames <= MAX_FRAMES:
                reject("roster_animation_limit")
            pixels = 0
            for index in range(frames):
                decoded.seek(index)
                dimensions(*decoded.size)
                pixels += decoded.width * decoded.height
                if pixels > MAX_PIXELS:
                    reject("roster_animation_limit")
                decoded.load()
                rgba = decoded.convert("RGBA")
                # Materialize every pixel, not merely dimensions or a thumbnail.
                if len(rgba.tobytes()) != decoded.width * decoded.height * 4:
                    reject()
                rgba.close()
    return {"frames": frames, "pages": 0, "pixels": pixels,
            "expanded_bytes": pixels * 4, "derived_content": None}


def pdf(source):
    from pypdf import PdfReader
    from pypdf.generic import DictionaryObject, ArrayObject, IndirectObject, StreamObject
    import pypdfium2 as pdfium
    reader = PdfReader(io.BytesIO(source), strict=True)
    if reader.is_encrypted:
        reject("roster_pdf_encrypted")
    objects = sum(len(items) for items in reader.xref.values()) + len(reader.xref_objStm)
    if objects > 5000:
        reject("roster_pdf_object_limit")
    if not 1 <= len(reader.pages) <= MAX_PAGES:
        reject("roster_pdf_page_limit")
    visited, streams, expanded, events = set(), 0, 0, 0
    def inspect(value, depth=0):
        nonlocal streams, expanded, events
        events += 1
        if depth > 40 or events > 100_000:
            reject("roster_pdf_object_limit")
        if isinstance(value, IndirectObject):
            key = (value.idnum, value.generation)
            if key in visited:
                return
            visited.add(key)
            value = value.get_object()
        if isinstance(value, DictionaryObject):
            if any(k in value for k in ("/JavaScript", "/JS", "/EmbeddedFiles", "/Launch", "/AA")):
                reject("roster_pdf_active_content")
            if value.get("/S") in ("/JavaScript", "/Launch", "/SubmitForm", "/ImportData"):
                reject("roster_pdf_active_content")
            if isinstance(value, StreamObject):
                streams += 1
                if streams > 2000:
                    reject("roster_pdf_object_limit")
                filters = value.get("/Filter")
                if filters in ("/FlateDecode", "/Fl"):
                    # Independently bound inflation before pypdf interpretation.
                    inflater = zlib.decompressobj()
                    remaining = MAX_EXPANDED - expanded
                    raw = inflater.decompress(value._data, remaining + 1)
                    if len(raw) > remaining or inflater.unconsumed_tail or not inflater.eof:
                        reject("roster_pdf_expansion_limit")
                    expanded += len(raw)
                elif filters not in ("/DCTDecode", "/JPXDecode", "/JBIG2Decode", "/CCITTFaxDecode"):
                    # Other filters/arrays are fully decoded inside the OS cap.
                    raw = value.get_data()
                    expanded += len(raw)
                    if expanded > MAX_EXPANDED:
                        reject("roster_pdf_expansion_limit")
            for key, item in value.items():
                if key != "/Parent":
                    inspect(item, depth + 1)
        elif isinstance(value, ArrayObject):
            for item in value:
                inspect(item, depth + 1)
    # Include unreferenced objects: hidden malformed streams are not ignored.
    for generation, entries in reader.xref.items():
        for number in entries:
            if number:
                inspect(IndirectObject(number, generation, reader))
    for number in reader.xref_objStm:
        inspect(IndirectObject(number, 0, reader))
    pixels = 0
    with pdfium.PdfDocument(source) as document:
        if len(document) != len(reader.pages):
            reject()
        for page in document:
            dimensions(*page.get_size())
            width, height = page.get_size()
            pixels += math.ceil(width * 4 / 3) * math.ceil(height * 4 / 3)
            if pixels > MAX_PIXELS:
                reject("roster_pdf_pixel_limit")
            bitmap = page.render(scale=4 / 3)
            try:
                # PDFium resolves object streams, fonts and image codecs and
                # rasterizes the complete page. Rendering has no JS engine.
                rendered = bitmap.to_pil()
                rendered.load()
                rendered.tobytes()
                rendered.close()
            finally:
                bitmap.close()
            page.close()
    return {"frames": 0, "pages": len(reader.pages), "pixels": pixels,
            "expanded_bytes": expanded, "derived_content": None}


ALIASES = {
    "member_name": {"member", "member name", "display name", "name"},
    "momo_name": {"momo name", "registered momo name", "registered name", "account name"},
    "momo_number": {"momo number", "mobile money number", "mobile number", "phone", "phone number", "telephone"},
}


def workbook(source):
    from defusedxml.ElementTree import fromstring
    from openpyxl import load_workbook
    expanded, events, cells = 0, 0, 0
    names = set()
    canonical = io.BytesIO()
    with zipfile.ZipFile(io.BytesIO(source)) as archive, zipfile.ZipFile(canonical, "w", compression=zipfile.ZIP_STORED) as trusted:
        entries = archive.infolist()
        if not 1 <= len(entries) <= 64:
            reject("roster_xlsx_expansion_limit")
        for entry in entries:
            name = entry.filename
            if name in names or len(name) > 240 or re.search(r"[\\\x00-\x20\x7f:%?#]", name) or name.startswith("/") or any(p in ("", ".", "..") for p in name.rstrip("/").split("/")):
                reject()
            names.add(name)
            if entry.flag_bits & ~0x080e or entry.compress_type not in (0, 8) or (entry.external_attr >> 16) & 0xf000 not in (0, 0x8000, 0x4000):
                reject()
            expanded += entry.file_size
            if entry.file_size > 2 * 1024 * 1024 or expanded > 8 * 1024 * 1024 or entry.file_size > entry.compress_size * 200 + 4096:
                reject("roster_xlsx_expansion_limit")
            # Read cap is independent of ZIP metadata; ZipExtFile verifies CRC.
            with archive.open(entry) as stream:
                content = stream.read(entry.file_size + 1)
                if len(content) != entry.file_size or stream.read(1):
                    reject()
            if name.endswith((".xml", ".rels")):
                root = fromstring(content, forbid_dtd=True, forbid_entities=True, forbid_external=True)
                for element in root.iter():
                    events += 1
                    if events > 100_000:
                        reject("roster_xlsx_expansion_limit")
                    local = element.tag.rsplit("}", 1)[-1]
                    if local in ("f", "definedName", "externalLink", "oleObject", "vbaProject") or (local == "c" and element.attrib.get("t") in ("str", "e")):
                        reject("roster_xlsx_formula")
                    if local == "Relationship":
                        target = element.attrib.get("Target", "")
                        if element.attrib.get("TargetMode") == "External" or re.search(r"[:\\\x00-\x20]", target):
                            reject("roster_xlsx_external_reference")
                    if local == "c":
                        cells += 1
                        if cells > 16_320:
                            reject("roster_xlsx_expansion_limit")
                        address = element.attrib.get("r", "")
                        matched = re.fullmatch(r"([A-Z]{1,2})([1-9][0-9]{0,2})", address)
                        if not matched or int(matched[2]) > 501:
                            reject("roster_xlsx_expansion_limit")
                        column = 0
                        for letter in matched[1]:
                            column = column * 26 + ord(letter) - 64
                        if column > 32:
                            reject("roster_xlsx_expansion_limit")
                    if local == "row" and (not element.attrib.get("r", "").isdigit() or not 1 <= int(element.attrib["r"]) <= 501):
                        reject("roster_xlsx_expansion_limit")
            elif not entry.is_dir():
                # Roster workbooks need OPC XML only; attachments/macros/media
                # are not input to a member table and would add hidden payloads.
                reject("roster_xlsx_active_content")
            trusted.writestr(name, content)
    canonical.seek(0)
    book = load_workbook(canonical, read_only=True, data_only=False, keep_links=False)
    output = ["Member name\tMoMo name\tMoMo number"]
    count = 0
    try:
        if not 1 <= len(book.worksheets) <= 10:
            reject("roster_xlsx_expansion_limit")
        for sheet in book.worksheets:
            if sheet.max_row > 501 or sheet.max_column > 32:
                reject("roster_xlsx_expansion_limit")
            rows = []
            for row in sheet.iter_rows():
                values = []
                for cell in row:
                    if cell.data_type in ("f", "e") or isinstance(cell.value, (bool,)):
                        reject("roster_xlsx_formula")
                    value = cell.value
                    if value is None:
                        text = ""
                    elif isinstance(value, float):
                        if not math.isfinite(value):
                            reject()
                        text = str(int(value)) if value.is_integer() else str(value)
                    elif isinstance(value, (str, int)):
                        text = str(value).strip()
                    else:
                        # Reject date/bool/errors rather than invent phone text.
                        reject("roster_xlsx_cell_type")
                    if len(text) > 480 or "\x00" in text:
                        reject("roster_xlsx_expansion_limit")
                    values.append(text)
                if any(values):
                    rows.append(values)
            if not rows:
                continue
            indices = dict.fromkeys(ALIASES, -1)
            for index, value in enumerate(rows[0]):
                key = re.sub(r"[\s_-]+", " ", value.lower()).strip()
                for field, aliases in ALIASES.items():
                    if key in aliases:
                        indices[field] = index
            header = any(index >= 0 for index in indices.values())
            if header and indices["momo_number"] < 0:
                reject("roster_xlsx_header")
            if not header:
                indices = dict(zip(ALIASES, (0, 1, 2)))
            for row in rows[1:] if header else rows:
                def at(field):
                    index = indices[field]
                    return re.sub(r"[\t\r\n]+", " ", row[index]).strip() if 0 <= index < len(row) else ""
                momo = at("momo_name")
                output.append("\t".join((at("member_name") or momo, momo, at("momo_number"))))
                count += 1
                if count > 500:
                    reject("roster_xlsx_expansion_limit")
    finally:
        book.close()
    if not count:
        reject("roster_xlsx_empty")
    content = "\n".join(output)
    if len(content.encode()) > 512_000:
        reject("roster_xlsx_expansion_limit")
    return {"frames": 0, "pages": 0, "pixels": 0, "expanded_bytes": expanded,
            "derived_content": content}


def decode(request):
    source = base64.b64decode(request["content_base64"], validate=True)
    if not 1 <= len(source) <= MAX_INPUT or hashlib.sha256(source).hexdigest() != request["source_sha256"]:
        reject("roster_decoder_source_mismatch")
    if request["kind"] == "image":
        summary = image(source, request["mime"])
    elif request["kind"] == "pdf" and request["mime"] == "application/pdf":
        summary = pdf(source)
    elif request["kind"] == "xlsx" and request["mime"] == "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet":
        summary = workbook(source)
    else:
        reject("roster_type_mismatch")
    content = summary["derived_content"]
    return {"ok": True, "policy_version": POLICY, "toolchain": TOOLCHAIN,
            "source_sha256": request["source_sha256"], "source_size": len(source),
            "derived_sha256": hashlib.sha256(content.encode()).hexdigest() if content is not None else None,
            **summary}


if __name__ == "__main__":
    try:
        isolate()
        request = json.loads(sys.stdin.buffer.read(8 * 1024 * 1024 + 1))
        result = decode(request)
    except Rejected as error:
        result = {"ok": False, "error": str(error)}
    except BaseException:
        result = {"ok": False, "error": "roster_invalid_file"}
    sys.stdout.write(json.dumps(result, ensure_ascii=False, separators=(",", ":")))
