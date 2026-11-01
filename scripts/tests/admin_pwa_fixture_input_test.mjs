import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { link, mkdtemp, open, rename, rm, symlink, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { readPinnedAdminMetadata } from './admin_pwa_fixture_input.mjs';

const sha = value => createHash('sha256').update(value).digest('hex');
async function fixture(fn) {
  const dir = await mkdtemp(join(tmpdir(), 'admin-pinned-metadata-'));
  try { await fn(dir); } finally { await rm(dir, { recursive: true, force: true }); }
}

test('validates and parses the same pinned bytes even if the path later changes', () => fixture(async dir => {
  const path = join(dir, 'metadata.json');
  const original = Buffer.from('{"id":"original"}\n');
  await writeFile(path, original);
  const { value, evidence } = await readPinnedAdminMetadata(path, sha(original));
  await writeFile(path, '{"id":"replacement"}\n');
  assert.deepEqual(value, { id: 'original' });
  assert.equal(evidence.sha256, sha(original));
  assert.equal(evidence.bytes, original.length);
}));

test('refuses a path replaced after descriptor read and before final identity check', () => fixture(async dir => {
  const path = join(dir, 'metadata.json'), moved = join(dir, 'metadata-old.json');
  const original = Buffer.from('{"id":"original"}\n');
  await writeFile(path, original);
  let replaced = false;
  const openFile = async (...args) => {
    const inner = await open(...args);
    return {
      stat: (...values) => inner.stat(...values),
      close: () => inner.close(),
      async read(...values) {
        const result = await inner.read(...values);
        if (!replaced) {
          replaced = true;
          await rename(path, moved);
          await writeFile(path, '{"id":"replacement"}\n');
        }
        return result;
      },
    };
  };
  await assert.rejects(readPinnedAdminMetadata(path, sha(original), { openFile }), /changed while reading/);
}));

test('refuses an in-place metadata modification during descriptor read', () => fixture(async dir => {
  const path = join(dir, 'metadata.json'), original = Buffer.from('{"id":"original"}\n');
  await writeFile(path, original);
  let changed = false;
  const openFile = async (...args) => {
    const inner = await open(...args);
    return {
      stat: (...values) => inner.stat(...values),
      close: () => inner.close(),
      async read(...values) {
        const result = await inner.read(...values);
        if (!changed) { changed = true; await writeFile(path, '{"id":"changed-and-longer"}\n'); }
        return result;
      },
    };
  };
  await assert.rejects(readPinnedAdminMetadata(path, sha(original), { openFile }), /changed while reading/);
}));

test('refuses wrong pins, links, invalid UTF-8 and oversized metadata', () => fixture(async dir => {
  const path = join(dir, 'metadata.json');
  const original = Buffer.from('{"ok":true}');
  await writeFile(path, original);
  await assert.rejects(readPinnedAdminMetadata(path, '0'.repeat(64)), /does not match/);
  await assert.rejects(readPinnedAdminMetadata(path, `${sha(original)}\n`), /SHA-256 pin/);
  await assert.rejects(readPinnedAdminMetadata('relative.json', sha(original)), /absolute regular file/);
  const alias = join(dir, 'alias.json');
  await symlink(path, alias);
  await assert.rejects(readPinnedAdminMetadata(alias, sha(original)), /Invalid public fixture metadata file/);
  await rm(alias);
  await link(path, alias);
  await assert.rejects(readPinnedAdminMetadata(path, sha(original)), /Invalid public fixture metadata file/);
  await rm(alias);
  const invalid = Buffer.from([0xff, 0xfe]);
  await writeFile(path, invalid);
  await assert.rejects(readPinnedAdminMetadata(path, sha(invalid)), TypeError);
  const oversized = Buffer.alloc(65537, 0x20);
  await writeFile(path, oversized);
  await assert.rejects(readPinnedAdminMetadata(path, sha(oversized)), /Invalid public fixture metadata file/);
}));
