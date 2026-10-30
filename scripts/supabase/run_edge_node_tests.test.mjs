import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, mkdir, writeFile, symlink, rm, readFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join, resolve} from 'node:path';
import {EventEmitter} from 'node:events';
import {discoverNodeTests, runNodeTests} from './run_edge_node_tests.mjs';

test('nested Node suites run exactly once and Deno suites remain separately owned', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'collect-test-discovery-'));
  try {
    await mkdir(join(directory, 'nested'));
    for (const name of ['b.test.mjs', 'a.test.ts', 'nested/a.test.mjs', 'helper.mjs', '._ignored.test.mjs']) {
      await writeFile(join(directory, name), '');
    }
    assert.deepEqual(await discoverNodeTests(directory), [join(directory, 'b.test.mjs'), join(directory, 'nested/a.test.mjs')]);
    await symlink(join(directory, 'b.test.mjs'), join(directory, 'linked.test.mjs'));
    await assert.rejects(discoverNodeTests(directory), /SYMLINK_REFUSED/);
  } finally { await rm(directory, {recursive: true, force: true}); }
});

test('an empty selection or unassigned test extension fails the gate', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'collect-test-discovery-'));
  try {
    await assert.rejects(discoverNodeTests(directory), /NODE_TESTS_REQUIRED/);
    await writeFile(join(directory, 'new.test.js'), '');
    await assert.rejects(discoverNodeTests(directory), /RUNTIME_OWNERSHIP_REQUIRED/);
  } finally { await rm(directory, {recursive: true, force: true}); }
});

test('the child exit failure is preserved; source is explicit and no shell expands filenames', async () => {
  const cwd = resolve('/synthetic/collect');
  const files = [join(cwd, 'example; literal.test.mjs')];
  let observed;
  const result = runNodeTests(files, {cwd, env: {PATH: 'synthetic'}, spawnImpl(binary, args, options) {
    observed = {binary, args, options};
    const child = new EventEmitter();
    queueMicrotask(() => child.emit('exit', 7, null));
    return child;
  }});
  assert.equal(await result, 7);
  assert.equal(observed.binary, process.execPath);
  assert.deepEqual(observed.args, ['--test', '--test-concurrency=1', ...files]);
  assert.equal(observed.options.shell, false);
  assert.equal(observed.options.env.COLLECT_AUTH_SOURCE_ROOT, join(cwd, 'supabase/functions/_shared'));
  assert.throws(() => runNodeTests([], {cwd}), /EXPLICIT_EDGE_NODE_TEST_FILES_REQUIRED/);
});

test('the maintained gate runs both runtimes and keeps frozen Deno dependencies', async () => {
  const root = new URL('../../', import.meta.url);
  const config = JSON.parse(await readFile(new URL('supabase/functions/deno.json', root), 'utf8'));
  const tooling = JSON.parse(await readFile(new URL('scripts/supabase/package.json', root), 'utf8'));
  const version = (await readFile(new URL('.dvmrc', root), 'utf8')).trim();
  assert.equal(version, tooling.devDependencies.deno);
  assert.equal(config.tasks.test, 'deno task test:node && deno task test:deno');
  assert.match(config.tasks['test:node'], /run_edge_node_tests\.mjs$/);
  assert.match(config.tasks['test:deno'], /^deno test --frozen /);
  assert.deepEqual(config.test.exclude, ['_shared/tests/**/*.test.mjs']);
  assert.match(config.tasks.check, /--frozen/);
});
