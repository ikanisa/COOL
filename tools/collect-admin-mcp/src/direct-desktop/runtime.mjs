import { readFileSync, lstatSync, realpathSync } from 'node:fs';
import { homedir } from 'node:os';
import { isAbsolute, join, relative, resolve } from 'node:path';
import { DEFAULT_POLICY, DesktopError, policySnapshot } from './contract.mjs';
import { DirectDesktopCore } from './core.mjs';
import { SqliteDesktopJournal } from './journal.mjs';

const repository = resolve(import.meta.dirname, '../../../..');
export function createDesktopRuntime(env = process.env) {
  const path = env.COLLECT_DESKTOP_JOURNAL || join(homedir(), 'Library', 'Application Support', 'Collect Direct Desktop', 'journal.sqlite');
  const relation = relative(repository, resolve(path));
  if (!isAbsolute(path) || path.includes('\0') || !relation || !relation.startsWith('../') && relation !== '..' && !isAbsolute(relation)) {
    throw new DesktopError('invalid_configuration', 'Use an absolute private journal path outside the repository.');
  }
  const policyPath = env.COLLECT_DESKTOP_POLICY;
  function loadPolicy() {
    let value = DEFAULT_POLICY;
    if (policyPath) {
      try {
        if (!isAbsolute(policyPath) || realpathSync(policyPath) !== policyPath) throw new Error('path');
        const stat = lstatSync(policyPath);
        if (!stat.isFile() || stat.nlink !== 1 || stat.size > 32_768) throw new Error('file');
        value = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(readFileSync(policyPath)));
      } catch { throw new DesktopError('invalid_policy', 'The project desktop policy file could not be verified.'); }
    }
    const { policy } = policySnapshot(value);
    // Only synthetic tests inject adapters. Configuration cannot manufacture native support.
    if (policy.mode !== 'dry_run' || policy.live_dispatch_enabled || policy.native_adapter !== 'unconfigured') {
      throw new DesktopError('native_adapter_unavailable', 'This host runtime supports dry run only. A reviewed native adapter has not been verified.');
    }
    return policy;
  }
  loadPolicy();
  const journal = new SqliteDesktopJournal(path);
  try { return new DirectDesktopCore({ journal, policyProvider: loadPolicy }); }
  catch (error) { journal.close(); throw error; }
}
