// Package existing Collect photos for web delivery. Original bytes and frame dimensions are retained.
// Requires sharp 0.35.5 (NODE_PATH may point to a bundled installation).
import fs from 'node:fs/promises';
import path from 'node:path';
import {createRequire} from 'node:module';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';

const sharp = createRequire(import.meta.url)('sharp');
const generator = fileURLToPath(import.meta.url);
const root = path.resolve(path.dirname(generator), '../..');
const photoBank = 'assets/marketing/rwanda';
const deliveryDirectory = 'web/public/photography';
const manifestPath = path.join(root, deliveryDirectory, 'manifest.json');
const hash = bytes => createHash('sha256').update(bytes).digest('hex');

function compareChannels(before, after) {
  let absoluteDifference = 0;
  let squaredDifference = 0;
  let maximumDifference = 0;
  for (let index = 0; index < before.length; index++) {
    const difference = Math.abs(before[index] - after[index]);
    if (index % 4 === 3 && difference !== 0) throw new Error('Photo alpha changed');
    absoluteDifference += difference;
    squaredDifference += difference * difference;
    maximumDifference = Math.max(maximumDifference, difference);
  }
  return {
    mean_absolute_channel_difference: absoluteDifference / before.length,
    root_mean_square_channel_difference: Math.sqrt(squaredDifference / before.length),
    maximum_channel_difference: maximumDifference,
  };
}

async function encodePhoto(input, filename) {
  const original = await sharp(input).metadata();
  if (original.orientation && original.orientation !== 1) {
    throw new Error('Photo orientation needs explicit review: ' + filename);
  }
  const options = {quality: original.hasAlpha ? 95 : 92, alphaQuality: 100, smartSubsample: true, exact: true, effort: 6};
  const bytes = await sharp(input).keepIccProfile().webp(options).toBuffer();
  const encoded = await sharp(bytes).metadata();
  const before = await sharp(input).ensureAlpha().raw().toBuffer();
  const after = await sharp(bytes).ensureAlpha().raw().toBuffer();
  if (original.width !== encoded.width || original.height !== encoded.height || before.length !== after.length) {
    throw new Error('Photo dimensions changed');
  }
  const empty = Buffer.alloc(0);
  if (hash(original.icc || empty) !== hash(encoded.icc || empty)) throw new Error('Photo colour profile changed');
  const evidence = {
    width: original.width, height: original.height, has_alpha: original.hasAlpha, options,
    alpha_unchanged: true, colour_profile_unchanged: true,
    source_decoded_rgba_sha256: hash(before), encoded_decoded_rgba_sha256: hash(after),
    ...compareChannels(before, after),
  };
  return {bytes, evidence};
}

async function verifyOrCreateDelivery(file, bytes, write) {
  const output = path.join(root, file);
  if (write) {
    try {
      await fs.writeFile(output, bytes, {flag: 'wx'});
      return;
    } catch (error) {
      if (error.code !== 'EEXIST') throw error;
    }
  }
  if (!bytes.equals(await fs.readFile(output))) {
    throw new Error('Photo delivery artifact differs from deterministic encoding: ' + file);
  }
}

async function photoRecord(filename, write) {
  if (!/^[a-z0-9-]+\.png$/.test(filename)) throw new Error('Unexpected photo filename');
  const source = photoBank + '/' + filename;
  const original = path.join(root, source);
  const input = await fs.readFile(original);
  const sourceDigest = hash(input);
  const {bytes, evidence} = await encodePhoto(input, filename);
  const digest = hash(bytes);
  const name = filename.replace(/\.png$/, '') + '-' + digest.slice(0, 12) + '.webp';
  const file = deliveryDirectory + '/' + name;
  await verifyOrCreateDelivery(file, bytes, write);
  if (hash(await fs.readFile(original)) !== sourceDigest) throw new Error('Original photo changed during packaging');
  return {
    source, source_sha256: sourceDigest, source_bytes: input.length, file,
    url: '/' + photoBank + '/' + name, sha256: digest, bytes: bytes.length, ...evidence,
  };
}

async function writeManifest(content) {
  const temporary = manifestPath + '.' + process.pid + '.tmp';
  const handle = await fs.open(temporary, 'wx');
  try {
    try {
      await handle.writeFile(content);
    } finally {
      await handle.close();
    }
    await fs.rename(temporary, manifestPath);
  } finally {
    await fs.rm(temporary, {force: true});
  }
}

async function main() {
  const mode = process.argv[2] || '--check';
  if (!['--check', '--write'].includes(mode) || process.argv.length > 3) throw new Error('Use --check or --write');
  if (sharp.versions.sharp !== '0.35.5' || sharp.versions.webp !== '1.6.0') {
    throw new Error('Expected sharp0.35.5 and libwebp1.6.0');
  }
  const write = mode === '--write';
  const manifest = {
    schema_version: 1, generator: 'scripts/assets/build_public_photography.mjs',
    generator_sha256: hash(await fs.readFile(generator)),
    encoder: {sharp: sharp.versions.sharp, webp: sharp.versions.webp},
    operation: 'Full-resolution WebP delivery encoding; opaque photos quality92, alpha photos quality95 with lossless alpha. No resize, crop, redraw or source replacement.',
    acceptance: 'Packaging evidence only; visual review, measured performance and release acceptance remain separate.',
    records: [],
  };
  if (write) await fs.mkdir(path.join(root, deliveryDirectory), {recursive: true});
  const filenames = (await fs.readdir(path.join(root, photoBank))).filter(file => file.endsWith('.png')).sort();
  if (!filenames.length) throw new Error('No original photographs');
  for (const filename of filenames) manifest.records.push(await photoRecord(filename, write));

  manifest.original_bytes = manifest.records.reduce((sum, record) => sum + record.source_bytes, 0);
  manifest.delivery_bytes = manifest.records.reduce((sum, record) => sum + record.bytes, 0);
  const content = JSON.stringify(manifest, null, 2) + '\n';
  if (write) {
    await writeManifest(content);
  } else if (content !== await fs.readFile(manifestPath, 'utf8')) {
    throw new Error('Photo manifest is stale; review and run --write');
  }
  console.log(JSON.stringify({
    status: 'pass', mode, photos: manifest.records.length, original_bytes: manifest.original_bytes,
    delivery_bytes: manifest.delivery_bytes, final_acceptance: false,
  }));
}

await main();
