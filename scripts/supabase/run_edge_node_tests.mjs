// Keep Node's node:test suites in Node. Deno owns the .test.ts suites in the
// same directory. Discovery is exhaustive, sorted, and rejects symbolic links
// so a new nested suite cannot silently disappear from the maintained gate.
import {readdir, realpath} from 'node:fs/promises';
import {resolve, relative, sep} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawn} from 'node:child_process';

export async function discoverNodeTests(directory) {
  const root = await realpath(directory);
  const files = [];
  async function visit(current) {
    for (const entry of await readdir(current, {withFileTypes: true})) {
      if (entry.name.startsWith('._')) continue;
      const path = resolve(current, entry.name);
      if (entry.isSymbolicLink()) throw Error('EDGE_TEST_SYMLINK_REFUSED');
      if (entry.isDirectory()) await visit(path);
      else if (entry.isFile() && entry.name.endsWith('.test.mjs')) files.push(path);
      else if (entry.isFile() && /(?:^test|[._]test)\.(?:js|cjs|mts|cts|jsx|tsx)$/.test(entry.name)) {
        throw Error('EDGE_TEST_RUNTIME_OWNERSHIP_REQUIRED: ' + relative(root, path));
      }
    }
  }
  await visit(root);
  if (files.length === 0) throw Error('EDGE_NODE_TESTS_REQUIRED');
  return files.sort();
}

export function runNodeTests(files, {cwd, env = process.env, spawnImpl = spawn} = {}) {
  if (!Array.isArray(files) || !files.length || files.some(path => !path.endsWith('.test.mjs'))) {
    throw Error('EXPLICIT_EDGE_NODE_TEST_FILES_REQUIRED');
  }
  const source = resolve(cwd, 'supabase/functions/_shared');
  const child = spawnImpl(process.execPath, ['--test', '--test-concurrency=1', ...files], {
    cwd, shell: false, stdio: 'inherit',
    env: {...env, COLLECT_AUTH_SOURCE_ROOT: env.COLLECT_AUTH_SOURCE_ROOT ?? source},
  });
  return new Promise((resolveExit, reject) => {
    child.once('error', reject);
    child.once('exit', (code, signal) => resolveExit(signal ? 1 : code ?? 1));
  });
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const root = fileURLToPath(new URL('../../', import.meta.url));
    const files = await discoverNodeTests(resolve(root, 'supabase/functions/_shared/tests'));
    if (process.argv.length === 3 && process.argv[2] === '--list-json') {
      console.log(JSON.stringify({runner: 'node:test', files: files.map(path => relative(root, path).split(sep).join('/'))}, null, 2));
    } else if (process.argv.length === 2) {
      process.exitCode = await runNodeTests(files, {cwd: root});
    } else throw Error('USE_NO_ARGUMENTS_OR_LIST_JSON');
  } catch (error) {
    console.error(error?.message ?? 'EDGE_NODE_TEST_RUN_FAILED');
    process.exitCode = 1;
  }
}
