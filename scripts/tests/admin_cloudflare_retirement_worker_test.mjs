import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';

const source = await readFile(new URL('../templates/admin_cloudflare_retirement_worker.js', import.meta.url), 'utf8');
function fixture({ failure = false } = {}) {
  const handlers = new Map(), calls = [];
  const context = vm.createContext({
    self: {
      addEventListener: (name, handler) => handlers.set(name, handler),
      skipWaiting: async () => calls.push('skipWaiting'),
      clients: { claim: async () => calls.push('claim') },
      registration: { unregister: async () => calls.push('unregister') },
    },
    caches: {
      keys: async () => [
        'collect-admin-0123456789abcdef', 'flutter-app-cache', 'flutter-temp-cache',
        'flutter-app-manifest', 'other-application', 'collect-admin-unrelated',
      ],
      delete: async (name) => {
        calls.push(name);
        if (failure) throw new Error('storage unavailable');
      },
    },
  });
  vm.runInContext(source, context);
  const dispatch = async (name) => {
    let pending;
    handlers.get(name)({ waitUntil: (promise) => { pending = promise; } });
    await pending;
  };
  return { handlers, calls, dispatch };
}
test('retirement claims no fetch or account cache authority', () => {
  const f = fixture();
  assert.deepEqual([...f.handlers.keys()], ['install', 'activate']);
  assert.doesNotMatch(source, /caches\.(?:open|put)|fetch\(|addEventListener\(['"]fetch/);
});
test('installed retirement worker replaces the historical waiting worker', async () => {
  const f = fixture();
  await f.dispatch('install');
  assert.deepEqual(f.calls, ['skipWaiting']);
});
test('activation retires only known Admin caches before claim and unregister', async () => {
  const f = fixture();
  await f.dispatch('activate');
  assert.deepEqual(f.calls, [
    'collect-admin-0123456789abcdef', 'flutter-app-cache', 'flutter-temp-cache',
    'flutter-app-manifest', 'claim', 'unregister',
  ]);
});
test('storage refusal cannot be reported as successful cache retirement', async () => {
  const f = fixture({ failure: true });
  await assert.rejects(f.dispatch('activate'), /storage unavailable/);
  assert.ok(!f.calls.includes('claim'));
  assert.ok(!f.calls.includes('unregister'));
});
