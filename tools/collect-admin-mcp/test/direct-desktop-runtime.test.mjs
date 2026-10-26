import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, realpathSync, readFileSync, writeFileSync, rmSync, existsSync, symlinkSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createDesktopRuntime } from '../src/direct-desktop/runtime.mjs';
import { DEFAULT_POLICY, DesktopError } from '../src/direct-desktop/contract.mjs';

function paths(t) {
  const root = mkdtempSync(join(realpathSync(tmpdir()), 'collect-desktop-runtime-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  return { root, journal: join(root, 'journal.sqlite'), policy: join(root, 'policy.json') };
}

test('the project-owned JSON example equals the default schema-validated dry-run policy', t => {
  const fixture = paths(t), example = JSON.parse(readFileSync(new URL('../config/operator.example.json', import.meta.url), 'utf8'));
  assert.deepEqual(example, DEFAULT_POLICY);
  writeFileSync(fixture.policy, JSON.stringify(example), { mode: 0o600 });
  const core = createDesktopRuntime({ COLLECT_DESKTOP_JOURNAL: fixture.journal, COLLECT_DESKTOP_POLICY: fixture.policy,
    COLLECT_ADMIN_MCP_ORIGIN: 'https://must-not-be-used.example.test', COLLECT_ADMIN_MCP_SESSION_FILE: '/must-not-be-read' });
  assert.equal(core.health().status, 'ready_dry_run'); assert.equal(core.health().native_adapter, 'unconfigured');
  assert.equal(core.health().live_dispatch_enabled, false); core.close();
});

test('configuration cannot enable live dispatch, inject a mock, or claim a supported native adapter', t => {
  for (const change of [
    policy => { policy.live_dispatch_enabled = true; }, policy => { policy.native_adapter = 'mock'; },
    policy => { policy.native_adapter = 'computer_use'; }, policy => { policy.mode = 'approved_autonomous'; },
    policy => { policy.api_url = 'https://hidden-endpoint.example.test'; },
  ]) {
    const fixture = paths(t), policy = structuredClone(DEFAULT_POLICY); change(policy);
    writeFileSync(fixture.policy, JSON.stringify(policy), { mode: 0o600 });
    assert.throws(() => createDesktopRuntime({ COLLECT_DESKTOP_JOURNAL: fixture.journal, COLLECT_DESKTOP_POLICY: fixture.policy }), DesktopError);
    assert.equal(existsSync(fixture.journal), false);
  }
});

test('runtime rejects repository and relative journal paths and linked policy files before starting', t => {
  const fixture = paths(t);
  for (const path of ['journal.sqlite', new URL('../private-journal.sqlite', import.meta.url).pathname]) {
    assert.throws(() => createDesktopRuntime({ COLLECT_DESKTOP_JOURNAL: path }), DesktopError);
  }
  writeFileSync(fixture.policy, JSON.stringify(DEFAULT_POLICY), { mode: 0o600 });
  const linked = join(fixture.root, 'linked-policy.json'); symlinkSync(fixture.policy, linked);
  assert.throws(() => createDesktopRuntime({ COLLECT_DESKTOP_JOURNAL: fixture.journal, COLLECT_DESKTOP_POLICY: linked }), DesktopError);
  assert.equal(existsSync(fixture.journal), false);
});

test('an edited policy is revalidated without restarting or changing authorization in a tool call', t => {
  const fixture = paths(t);
  writeFileSync(fixture.policy, JSON.stringify(DEFAULT_POLICY), { mode: 0o600 });
  const core = createDesktopRuntime({ COLLECT_DESKTOP_JOURNAL: fixture.journal, COLLECT_DESKTOP_POLICY: fixture.policy });
  assert.equal(core.health().status, 'ready_dry_run');
  writeFileSync(fixture.policy, JSON.stringify({ ...DEFAULT_POLICY, live_dispatch_enabled: true }));
  assert.throws(() => core.health(), error => error.code === 'native_adapter_unavailable'); core.close();
});
