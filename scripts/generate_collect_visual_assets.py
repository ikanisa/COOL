#!/usr/bin/env python3
"""Generate Collect-owned product visuals for premium mobile surfaces."""

from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "brand" / "collect_runtime" / "media"

INK = (37, 32, 68)
PAPER = (250, 248, 245)
PERIWINKLE = (136, 133, 240)
MINT = (60, 208, 112)
ROSE = (211, 139, 150)
ORANGE = (255, 94, 67)
WHITE = (255, 253, 251)


def blend(a, b, t):
    return tuple(round(a[i] * (1 - t) + b[i] * t) for i in range(3))


def gradient(size, stops):
    width, height = size
    img = Image.new("RGB", size)
    px = img.load()
    for y in range(height):
        for x in range(width):
            t = (x / max(width - 1, 1)) * 0.45 + (y / max(height - 1, 1)) * 0.55
            for index in range(len(stops) - 1):
                left_t, left = stops[index]
                right_t, right = stops[index + 1]
                if left_t <= t <= right_t:
                    local = (t - left_t) / max(right_t - left_t, 0.001)
                    px[x, y] = blend(left, right, local)
                    break
            else:
                px[x, y] = stops[-1][1]
    return img


def rounded_mask(size, radius):
    mask = Image.new("L", size, 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius=radius, fill=255)
    return mask


def paste_round(base, layer, box, radius):
    layer = layer.convert("RGBA")
    mask = rounded_mask(layer.size, radius)
    base.paste(layer, box, mask)


def shadow(base, box, radius, alpha=70, blur=28):
    x0, y0, x1, y1 = box
    layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    draw.rounded_rectangle(box, radius=radius, fill=(37, 32, 68, alpha))
    layer = layer.filter(ImageFilter.GaussianBlur(blur))
    base.alpha_composite(layer)


def make_momo_signal():
    base = gradient(
        (960, 640),
        [
            (0.0, blend(MINT, PAPER, 0.20)),
            (0.35, blend(PERIWINKLE, PAPER, 0.18)),
            (0.72, blend(ORANGE, PAPER, 0.20)),
            (1.0, PAPER),
        ],
    ).convert("RGBA")
    draw = ImageDraw.Draw(base, "RGBA")
    shadow(base, (120, 92, 840, 550), 72, alpha=52, blur=36)
    draw.rounded_rectangle((120, 92, 840, 550), radius=72, fill=(*WHITE, 218), outline=(*PERIWINKLE, 135), width=3)
    draw.rounded_rectangle((205, 145, 460, 500), radius=42, fill=(*INK, 238))
    draw.rounded_rectangle((235, 185, 430, 395), radius=28, fill=(*PAPER, 245))
    draw.ellipse((305, 417, 360, 472), fill=(*MINT, 255))
    for idx, color in enumerate([MINT, PERIWINKLE, ROSE, ORANGE]):
        y = 170 + idx * 74
        draw.rounded_rectangle((525, y, 765, y + 44), radius=22, fill=(*color, 210))
        draw.rounded_rectangle((548, y + 15, 710, y + 23), radius=4, fill=(*INK, 70))
    draw.arc((500, 110, 825, 435), start=200, end=320, fill=(*INK, 190), width=16)
    draw.arc((545, 158, 780, 390), start=205, end=318, fill=(*INK, 120), width=12)
    return base


def make_group_momentum():
    base = gradient(
        (960, 640),
        [
            (0.0, blend(PERIWINKLE, PAPER, 0.08)),
            (0.45, blend(ROSE, PAPER, 0.10)),
            (1.0, blend(MINT, PAPER, 0.24)),
        ],
    ).convert("RGBA")
    draw = ImageDraw.Draw(base, "RGBA")
    cards = [
        (122, 122, 442, 470, ORANGE),
        (320, 70, 668, 526, PERIWINKLE),
        (550, 132, 836, 486, MINT),
    ]
    for box in cards:
        x0, y0, x1, y1, color = box
        shadow(base, (x0, y0, x1, y1), 52, alpha=46, blur=24)
        draw.rounded_rectangle((x0, y0, x1, y1), radius=52, fill=(*WHITE, 220), outline=(*color, 170), width=4)
        draw.rounded_rectangle((x0 + 36, y0 + 38, x1 - 36, y0 + 112), radius=28, fill=(*color, 220))
        for row in range(3):
            y = y0 + 150 + row * 58
            draw.ellipse((x0 + 42, y, x0 + 78, y + 36), fill=(*color, 180))
            draw.rounded_rectangle((x0 + 92, y + 8, x1 - 58, y + 18), radius=5, fill=(*INK, 62))
            draw.rounded_rectangle((x0 + 92, y + 26, x1 - 120, y + 34), radius=4, fill=(*INK, 40))
    return base


def make_qr_share():
    base = gradient(
        (960, 640),
        [
            (0.0, blend(ORANGE, PAPER, 0.20)),
            (0.45, blend(ROSE, PAPER, 0.10)),
            (1.0, blend(PERIWINKLE, PAPER, 0.18)),
        ],
    ).convert("RGBA")
    draw = ImageDraw.Draw(base, "RGBA")
    shadow(base, (205, 78, 755, 540), 74, alpha=54, blur=34)
    draw.rounded_rectangle((205, 78, 755, 540), radius=74, fill=(*WHITE, 230), outline=(*ROSE, 155), width=4)
    draw.rounded_rectangle((312, 145, 648, 481), radius=42, fill=(*PAPER, 255), outline=(*PERIWINKLE, 160), width=4)
    cell = 26
    pattern = [
        "11101110101",
        "10001000100",
        "10111011101",
        "00000100010",
        "11101010111",
        "00101000100",
        "10111110101",
        "10000010100",
        "11101110111",
        "00100000100",
        "10111101101",
    ]
    ox, oy = 338, 171
    for y, line in enumerate(pattern):
        for x, value in enumerate(line):
            if value == "1":
                color = [INK, PERIWINKLE, MINT, ORANGE][(x + y) % 4]
                draw.rounded_rectangle((ox + x * cell, oy + y * cell, ox + x * cell + 18, oy + y * cell + 18), radius=5, fill=(*color, 235))
    draw.rounded_rectangle((380, 414, 580, 452), radius=19, fill=(*INK, 235))
    draw.rounded_rectangle((410, 428, 550, 436), radius=4, fill=(*PAPER, 210))
    return base


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    assets = {
        "mobile-money-ussd-signal.png": make_momo_signal(),
        "group-momentum.png": make_group_momentum(),
        "qr-share.png": make_qr_share(),
    }
    for name, image in assets.items():
        image.convert("RGB").save(OUT / name, optimize=True)
        print(OUT / name)


if __name__ == "__main__":
    main()
