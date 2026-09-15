import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import { renderGroupCoverCatalog, writeGroupCoverCatalog } from '../assets/group_cover_catalog_source.mjs';

const asset = (id, family) => ({
  id, family, version: 1, labels: { en: "Friends' $20 goal", rw: 'Inshuti' },
  theme: 'savings', collection_types: ['ikimina'], search_terms: ['group'],
  explicit_context: null, general_default: true, editorial_priority: 5,
  focal_point: { x: 0.5, y: 0.47 },
});
const catalog = () => ({
  families: [{ id: 'savings', labels: { en: 'Savings' } }, { id: 'community', labels: { en: 'Community' } }],
  assets: [asset('rw-01', 'savings'), asset('rw-02', 'community'), asset('rw-03', 'savings')],
});

test('interleaved families retain original display order and escaped labels', () => {
  const files = renderGroupCoverCatalog(catalog());
  assert.deepEqual([...files.keys()], ['collect_group_cover_catalog.dart', 'collect_group_cover_catalog_savings.dart', 'collect_group_cover_catalog_community.dart']);
  const order = files.get('collect_group_cover_catalog.dart');
  assert.match(order, /_coverRw01,\n  _coverRw02,\n  _coverRw03,/);
  const savings = files.get('collect_group_cover_catalog_savings.dart');
  assert.match(savings, /Friends\\' \\\$20 goal/);
  assert.match(savings, /focalY: 0\.47/);
  assert.match(savings, /_coverRw03/);
  assert.doesNotMatch(savings, /_coverRw02/);
});

test('invalid catalog identifiers and missing families are rejected', () => {
  for (const mutate of [
    data => { data.assets[0].id = '../escape'; },
    data => { data.assets.push(data.assets[0]); },
    data => { data.assets[0].family = 'missing'; },
    data => { data.assets = []; },
  ]) {
    const data = catalog(); mutate(data);
    assert.throws(() => renderGroupCoverCatalog(data));
  }
});

test('generation updates only owned metadata and is repeatable', async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'collect-cover-source-'));
  try {
    const models = path.join(root, 'lib/shared/models');
    await fs.mkdir(models, { recursive: true });
    const owner = path.join(models, 'collect_group_cover.dart');
    await fs.writeFile(owner, "import 'collect_models.dart';\npart 'collect_group_cover_catalog.dart';\nclass CollectGroupCover {}\n");
    const image = path.join(root, 'original.webp');
    const bytes = Buffer.from([0, 1, 42, 255]);
    await fs.writeFile(image, bytes);
    const generated = await writeGroupCoverCatalog(root, catalog());
    const first = await fs.readFile(owner, 'utf8');
    assert.equal(first.match(/part 'collect_group_cover_catalog.dart';/g).length, 1);
    assert.match(first, /class CollectGroupCover \{\}/);
    await writeGroupCoverCatalog(root, catalog());
    assert.equal(await fs.readFile(owner, 'utf8'), first);
    assert.deepEqual(await fs.readFile(image), bytes);
    assert.deepEqual((await fs.readdir(models)).sort(), [...generated, 'collect_group_cover.dart'].sort());
  } finally {
    await fs.rm(root, { recursive: true, force: true });
  }
});
