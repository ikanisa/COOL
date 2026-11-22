#!/usr/bin/env node
import { appendFileSync, readFileSync, writeFileSync } from 'node:fs';
import { basename } from 'node:path';
import { inflateSync } from 'node:zlib';
import pngHeader from './png_dimensions.cjs';

const [path, expectedSize, name, route, url, capturesJson] = process.argv.slice(2);
if (!capturesJson) {
  console.error('usage: png_capture_check.mjs PNG VIEWPORT NAME ROUTE URL CAPTURES_JSONL');
  process.exit(2);
}

const fail = (message) => {
  console.error(message);
  process.exit(1);
};

const [expectedWidth, expectedHeight] = expectedSize.split('x').map((value) => Number(value));
const data = readFileSync(path);
const {width, height} = pngHeader.pngDimensions(data, path);
if (width !== expectedWidth || height !== expectedHeight) fail(`unexpected PNG dimensions ${width}x${height}, expected ${expectedWidth}x${expectedHeight}`);
const size = data.length;
if (size <= 8000) fail(`screenshot too small to prove render: ${size} bytes`);
const bitDepth = data[24];
const colorType = data[25];
const interlace = data[28];
if (bitDepth !== 8) fail(`unsupported PNG bit depth ${bitDepth}`);
if (interlace !== 0) fail('interlaced PNG screenshots are not supported');

let offset = 33;
let ended = false;
const idatChunks = [];
while (offset < data.length) {
  if (offset + 12 > data.length) fail('incomplete PNG chunk header');
  const length = data.readUInt32BE(offset);
  const type = data.subarray(offset + 4, offset + 8).toString('ascii');
  if (length > data.length - offset - 12) fail('incomplete PNG chunk data');
  const chunk = data.subarray(offset + 8, offset + 8 + length);
  offset += 12 + length;

  if (type === 'IDAT') {
    idatChunks.push(chunk);
  } else if (type === 'IEND') {
    ended = length === 0 && offset === data.length;
    break;
  }
}

if (!ended || !idatChunks.length) fail('missing PNG image data or end marker');

const channelMap = new Map([
  [0, 1],
  [2, 3],
  [6, 4],
]);
const channels = channelMap.get(colorType);
if (!channels) fail(`unsupported PNG color type ${colorType}`);

const bytesPerPixel = channels;
const rowBytes = width * channels;
const rasterLength = (rowBytes + 1) * height;
const inflated = inflateSync(Buffer.concat(idatChunks), {maxOutputLength: rasterLength});
if (inflated.length !== rasterLength) fail('decoded PNG raster length differs from its dimensions');
const previous = new Uint8Array(rowBytes);
let readOffset = 0;
const sampleTarget = 20000;
const totalPixels = width * height;
const stride = Math.max(Math.floor(totalPixels / sampleTarget), 1);
const distinctRgb = new Set();
let nonBackgroundPixels = 0;
let sampledPixels = 0;
let pixelIndex = 0;

const paeth = (a, b, c) => {
  const p = a + b - c;
  const pa = Math.abs(p - a);
  const pb = Math.abs(p - b);
  const pc = Math.abs(p - c);
  if (pa <= pb && pa <= pc) return a;
  if (pb <= pc) return b;
  return c;
};

for (let y = 0; y < height; y += 1) {
  const filter = inflated[readOffset];
  readOffset += 1;
  const raw = inflated.subarray(readOffset, readOffset + rowBytes);
  readOffset += rowBytes;
  const row = new Uint8Array(rowBytes);

  for (let i = 0; i < rowBytes; i += 1) {
    const left = i >= bytesPerPixel ? row[i - bytesPerPixel] : 0;
    const up = previous[i];
    const upperLeft = i >= bytesPerPixel ? previous[i - bytesPerPixel] : 0;
    let predictor = 0;
    if (filter === 1) predictor = left;
    else if (filter === 2) predictor = up;
    else if (filter === 3) predictor = Math.floor((left + up) / 2);
    else if (filter === 4) predictor = paeth(left, up, upperLeft);
    else if (filter !== 0) fail(`unsupported PNG filter ${filter}`);
    row[i] = (raw[i] + predictor) & 0xff;
  }

  for (let i = 0; i < rowBytes; i += channels) {
    if (pixelIndex % stride === 0) {
      const r = row[i];
      const g = channels === 1 ? r : row[i + 1];
      const b = channels === 1 ? r : row[i + 2];
      const a = channels === 4 ? row[i + 3] : 255;
      sampledPixels += 1;
      distinctRgb.add(`${r},${g},${b}`);
      if (a > 0 && !(r > 245 && g > 245 && b > 245)) nonBackgroundPixels += 1;
    }
    pixelIndex += 1;
  }

  previous.set(row);
}

if (distinctRgb.size < 8) fail(`screenshot appears blank: ${distinctRgb.size} distinct sampled colors`);
if (nonBackgroundPixels < 100) fail(`screenshot lacks visible foreground pixels: ${nonBackgroundPixels}`);

const result = {
  status: 'pass',
  name,
  route,
  url,
  path: basename(path),
  width,
  height,
  bytes: size,
  sampled_pixels: sampledPixels,
  distinct_rgb: distinctRgb.size,
  non_background_pixels: nonBackgroundPixels,
};

writeFileSync(`${path}.json`, `${JSON.stringify(result, null, 2)}\n`);
appendFileSync(capturesJson, `${JSON.stringify(result)}\n`);
