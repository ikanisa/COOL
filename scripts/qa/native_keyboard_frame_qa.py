#!/usr/bin/env python3
"""Check the reproduced Android host-focus frame in real OS captures.

This is a narrow raster regression, not a visual-fidelity score. The preceding
native driver separately checks real IME visibility, field focus and controls.
"""
import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image


def inspect(path):
    with Image.open(path) as original:
        image = original.convert('RGB')
        width, height = image.size
        # The observed frame is approximately RGB(126, 168, 0), 3 pixels wide.
        # Inspect only its top/side footprint; never scan photos or control art.
        points = {(x, y) for y in range(3) for x in range(width)}
        points.update((x, y) for x in [0, 1, 2, width - 3, width - 2, width - 1]
                      for y in range(height))
        pixels = [image.getpixel(point) for point in points]
        count = sum(70 <= r <= 170 and 120 <= g <= 210 and b < 30 and g - r > 20
                    for r, g, b in pixels)
    return {'width': width, 'height': height, 'green_frame_pixels': count,
            'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--before', required=True, type=Path)
    parser.add_argument('--after', required=True, type=Path)
    args = parser.parse_args()
    report = json.loads((args.after / 'report.json').read_text())
    results = []
    for case in report['results']:
        for state in ['focused', 'action']:
            filename = case.get(state + '_capture')
            if filename:
                before = inspect(args.before / filename)
                after = inspect(args.after / filename)
                results.append({'capture': filename, 'before': before, 'after': after,
                                'status': 'pass' if after['green_frame_pixels'] == 0 else 'fail'})
    reproduced = any(row['before']['green_frame_pixels'] > row['before']['width'] / 2
                     for row in results)
    passed = (report['status'] == 'pass' and len(report['results']) == 32 and
              len(results) == 60 and reproduced and
              all(row['status'] == 'pass' for row in results))
    output = {'status': 'pass' if passed else 'fail',
              'scope': 'Android default host-view focus frame; OS screenshot pixels',
              'before': str(args.before), 'after': str(args.after),
              'before_frame_reproduced': reproduced, 'captures': len(results),
              'results': results}
    (args.after / 'focus-frame-comparison.json').write_text(json.dumps(output, indent=2) + '\n')
    print(json.dumps({k: output[k] for k in ['status', 'before_frame_reproduced', 'captures']}))
    raise SystemExit(0 if passed else 1)


if __name__ == '__main__':
    main()
