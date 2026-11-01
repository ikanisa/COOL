// A bounded, source-bound metadata read for the local browser fixture. This
// checks bytes consumed by the parser; it does not attest provider or hosting.
import { createHash } from 'node:crypto';
import { constants } from 'node:fs';
import { lstat, open } from 'node:fs/promises';
import { isAbsolute } from 'node:path';

const MAX_BYTES = 65536n;
const stamp = stat => [stat.dev, stat.ino, stat.size, stat.mtimeNs, stat.ctimeNs];
const sameStamp = (left, right) => stamp(left).every((value, i) => value === stamp(right)[i]);

export async function readPinnedAdminMetadata(path, expected, { openFile = open, statPath = lstat } = {}) {
  if (typeof path !== 'string' || !isAbsolute(path) || typeof expected !== 'string' ||
      !/^[a-f0-9]{64}(?![\s\S])/.test(expected)) {
    throw Error('Set ADMIN_PWA_PUBLIC_METADATA_PATH to an absolute regular file and supply its SHA-256 pin');
  }
  const before = await statPath(path, { bigint: true });
  if (!before.isFile() || before.isSymbolicLink() || before.nlink !== 1n ||
      before.size < 1n || before.size > MAX_BYTES) throw Error('Invalid public fixture metadata file');
  const handle = await openFile(path, constants.O_RDONLY | (constants.O_NOFOLLOW || 0) | (constants.O_NONBLOCK || 0));
  let bytes;
  try {
    const opened = await handle.stat({ bigint: true });
    if (!opened.isFile() || !sameStamp(before, opened)) throw Error('Public fixture metadata changed before reading');
    bytes = Buffer.alloc(Number(opened.size));
    for (let offset = 0; offset < bytes.length;) {
      const { bytesRead } = await handle.read(bytes, offset, bytes.length - offset, offset);
      if (!bytesRead) throw Error('Incomplete public fixture metadata');
      offset += bytesRead;
    }
    if (!sameStamp(opened, await handle.stat({ bigint: true })) ||
        !sameStamp(opened, await statPath(path, { bigint: true }))) {
      throw Error('Public fixture metadata changed while reading');
    }
  } finally {
    await handle.close();
  }
  const actual = createHash('sha256').update(bytes).digest('hex');
  if (actual !== expected) throw Error('Public fixture metadata does not match its SHA-256 pin');
  const text = new TextDecoder('utf-8', { fatal: true }).decode(bytes);
  const value = JSON.parse(text);
  return { value, evidence: { path, sha256: actual, bytes: bytes.length } };
}
