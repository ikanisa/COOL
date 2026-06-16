#!/usr/bin/env python3
import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageOps


def load_font(draw):
    return None


def draw_sheet(title, items, output, thumb_width=220, columns=4):
    if not items:
        raise SystemExit(f"no images found for {title}")
    padding = 18
    label_height = 44
    title_height = 56
    thumbs = []
    for label, path in items:
        with Image.open(path) as image:
            image = ImageOps.exif_transpose(image).convert("RGB")
            ratio = thumb_width / image.width
            thumb_height = max(1, int(image.height * ratio))
            thumbs.append((label, image.resize((thumb_width, thumb_height)), path))
    max_thumb_height = max(image.height for _, image, _ in thumbs)
    rows = (len(thumbs) + columns - 1) // columns
    width = padding + columns * (thumb_width + padding)
    height = title_height + rows * (max_thumb_height + label_height + padding) + padding
    sheet = Image.new("RGB", (width, height), "#FAF8F5")
    draw = ImageDraw.Draw(sheet)
    draw.text((padding, 18), title, fill="#252044")
    for index, (label, image, _) in enumerate(thumbs):
        col = index % columns
        row = index // columns
        x = padding + col * (thumb_width + padding)
        y = title_height + row * (max_thumb_height + label_height + padding)
        sheet.paste(image, (x, y))
        draw.rectangle((x, y, x + thumb_width - 1, y + image.height - 1), outline="#DED8EA")
        draw.text((x, y + max_thumb_height + 8), label[:34], fill="#252044")
    output.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(output)
    return output


def reference_items(reference_dir):
    paths = sorted(
        [
            *reference_dir.glob("*.PNG"),
            *reference_dir.glob("*.png"),
            *reference_dir.glob("*.JPG"),
            *reference_dir.glob("*.jpg"),
            *reference_dir.glob("*.JPEG"),
            *reference_dir.glob("*.jpeg"),
        ]
    )
    return [(path.name, path) for path in paths if path.is_file()]


def summary_items(directory):
    summary = directory / "summary.json"
    if summary.is_file():
        data = json.loads(summary.read_text())
        captures = data.get("captures") or []
        items = []
        for capture in captures:
            path = directory / capture["path"]
            if path.is_file():
                items.append((capture.get("name") or capture["path"], path))
        if items:
            return items
    return [(path.stem, path) for path in sorted(directory.glob("*.png"))]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--reference-dir", required=True)
    parser.add_argument("--mobile-dir", required=True)
    parser.add_argument("--admin-dir", required=True)
    parser.add_argument("--output-dir", required=True)
    args = parser.parse_args()

    reference_dir = Path(args.reference_dir)
    mobile_dir = Path(args.mobile_dir)
    admin_dir = Path(args.admin_dir)
    output_dir = Path(args.output_dir)

    references = reference_items(reference_dir)
    generated = {
        "reference_contact_sheet": str(
            draw_sheet(
                f"Revolut reference set - {len(references)} screenshots",
                references,
                output_dir / "revolut-reference-contact-sheet.png",
            )
        ),
        "mobile_contact_sheet": str(
            draw_sheet(
                "Collect mobile route evidence",
                summary_items(mobile_dir),
                output_dir / "collect-mobile-route-contact-sheet.png",
                thumb_width=150,
                columns=6,
            )
        ),
        "admin_contact_sheet": str(
            draw_sheet(
                "Collect Admin PWA evidence",
                summary_items(admin_dir),
                output_dir / "collect-admin-contact-sheet.png",
                thumb_width=220,
                columns=3,
            )
        ),
    }
    (output_dir / "contact_sheets.json").write_text(json.dumps(generated, indent=2) + "\n")
    print(json.dumps(generated, indent=2))


if __name__ == "__main__":
    main()
