"""Tiny synthetic hostile inputs; run only in the bounded Linux decoder image.

The PDF cases exercise the dependency's real text-extraction API. Collect's
production PDF path rasterizes pages; this does not add text extraction to it.
The parent container must additionally deny network and cap memory/CPU/pids.
"""
from __future__ import annotations

import io
from pathlib import Path
import resource
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import decoder


def font_pdf(source: bytes = b"41", destination: bytes = b"0041") -> bytes:
    """One page and one glyph; no compressed streams or generated huge objects."""
    if len(source) + len(destination) > 4096:
        raise ValueError("The security fixture itself must remain small")
    cmap = (
        b"/CIDInit /ProcSet findresource begin\n12 dict begin\nbegincmap\n"
        b"/CIDSystemInfo << /Registry (Collect) /Ordering (Synthetic) /Supplement 0 >> def\n"
        b"/CMapName /CollectSecurityFixture def\n/CMapType 2 def\n"
        b"1 begincodespacerange\n<00> <FF>\nendcodespacerange\n"
        b"1 beginbfchar\n<" + source + b"> <" + destination + b">\n"
        b"endbfchar\nendcmap\nCMapName currentdict /CMap defineresource pop\nend\nend\n"
    )
    content = b"BT /F1 12 Tf 12 24 Td <41> Tj ET"
    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 96 48] "
        b"/Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>",
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica "
        b"/Encoding /WinAnsiEncoding /ToUnicode 6 0 R >>",
        b"<< /Length " + str(len(content)).encode() + b" >>\nstream\n" + content + b"\nendstream",
        b"<< /Length " + str(len(cmap)).encode() + b" >>\nstream\n" + cmap + b"endstream",
    ]
    output = bytearray(b"%PDF-1.7\n")
    offsets = []
    for number, obj in enumerate(objects, 1):
        offsets.append(len(output))
        output.extend(str(number).encode() + b" 0 obj\n" + obj + b"\nendobj\n")
    xref = len(output)
    output.extend(b"xref\n0 7\n0000000000 65535 f \n")
    for offset in offsets:
        output.extend(f"{offset:010d} 00000 n \n".encode())
    output.extend(b"trailer\n<< /Size 7 /Root 1 0 R >>\nstartxref\n")
    output.extend(str(xref).encode() + b"\n%%EOF\n")
    if len(output) > 8192:
        raise ValueError("The complete hostile PDF must stay below 8KiB")
    return bytes(output)


class HostilePdf(unittest.TestCase):
    def extract(self, source=b"41", destination=b"0041"):
        from pypdf import PdfReader
        return PdfReader(io.BytesIO(font_pdf(source, destination)), strict=True).pages[0].extract_text()

    def test_benign_font_mapping_preserved(self):
        self.assertEqual(self.extract(), "A")

    def test_oversized_source_token_rejected_from_actual_pdf(self):
        from pypdf.errors import LimitReachedError
        with self.assertRaisesRegex(LimitReachedError, "/ToUnicode code length exceeded"):
            self.extract(source=b"41" * 10)

    def test_oversized_destination_token_rejected_from_actual_pdf(self):
        from pypdf.errors import LimitReachedError
        with self.assertRaisesRegex(LimitReachedError, "/ToUnicode string length exceeded"):
            self.extract(destination=b"0041" * 300)


class SignedImageCoordinates(unittest.TestCase):
    def test_inverted_signed_box_rejected_without_destination_write(self):
        from PIL import Image
        with Image.new("RGBA", (2, 1), "red") as tile, Image.new("RGBA", (8, 1)) as canvas:
            original = canvas.tobytes()
            with self.assertRaises(ValueError):
                canvas.paste(tile, ((1 << 31) - 2, 0, -(1 << 31), 1))
            self.assertEqual(canvas.tobytes(), original)

    def test_distant_crop_is_transparent_or_rejected(self):
        from PIL import Image
        left = -(1 << 31) + 2
        with Image.new("RGBA", (2, 1), "red") as image:
            try:
                cropped = image.crop((left, 0, left + 2, 1))
            except (ValueError, OverflowError):
                return  # Explicit coordinate rejection is a safe documented boundary.
            with cropped:
                self.assertEqual(cropped.size, (2, 1))
                self.assertEqual(cropped.tobytes(), bytes(8))

    def test_distant_alpha_composite_has_no_visible_write_or_is_rejected(self):
        from PIL import Image
        with Image.new("RGBA", (2, 1), "red") as tile, Image.new("RGBA", (8, 1)) as canvas:
            original = canvas.tobytes()
            try:
                canvas.alpha_composite(tile, dest=(-(1 << 31) + 2, 0))
            except (ValueError, OverflowError):
                pass
            self.assertEqual(canvas.tobytes(), original)


if __name__ == "__main__":
    # Apply the production syscall/address-space/CPU limits before parsing.
    decoder.isolate()
    assert resource.getrlimit(resource.RLIMIT_AS) == (384 * 1024 * 1024,) * 2
    assert resource.getrlimit(resource.RLIMIT_CPU) == (4, 5)
    unittest.main(verbosity=2)
