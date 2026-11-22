import { closeSync, constants, fstatSync, lstatSync, openSync, readSync, realpathSync } from 'node:fs';
import { homedir } from 'node:os';
import { isAbsolute, join, relative, resolve, sep } from 'node:path';
import { DEFAULT_POLICY, DesktopError, policySnapshot } from './contract.mjs';
import { DirectDesktopCore } from './core.mjs';
import { SqliteDesktopJournal } from './journal.mjs';

const repository = resolve(import.meta.dirname, '../../../..');
const maxPolicyBytes = 32_768;

function outsideRepository(path) {
  if (!isAbsolute(path) || path.includes('\0')) return false;
  const relation = relative(repository, resolve(path));
  return relation === '..' || relation.startsWith('..' + sep) || isAbsolute(relation);
}

function samePolicyFile(expected, observed) {
  return observed.isFile() && observed.nlink === 1n &&
    observed.dev === expected.dev && observed.ino === expected.ino && observed.size === expected.size &&
    observed.mtimeNs === expected.mtimeNs && observed.ctimeNs === expected.ctimeNs;
}

function readStablePolicy(path) {
  if (!isAbsolute(path) || realpathSync(path) !== path) throw new Error('policy path');
  const fd = openSync(path, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
  try {
    const original = fstatSync(fd, { bigint: true });
    if (!original.isFile() || original.nlink !== 1n || original.size > BigInt(maxPolicyBytes) ||
        !samePolicyFile(original, lstatSync(path, { bigint: true }))) throw new Error('policy file');
    const bytes = Buffer.alloc(Number(original.size) + 1);
    let read = 0;
    while (read < bytes.length) {
      const count = readSync(fd, bytes, read, bytes.length - read, null);
      if (!count) break;
      read += count;
    }
    if (read !== Number(original.size) || !samePolicyFile(original, fstatSync(fd, { bigint: true })) ||
        !samePolicyFile(original, lstatSync(path, { bigint: true })) || realpathSync(path) !== path) throw new Error('policy changed');
    return JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes.subarray(0, read)));
  } finally {
    closeSync(fd);
  }
}

export function createDesktopRuntime(env = process.env) {
  const path = env.COLLECT_DESKTOP_JOURNAL || join(homedir(), 'Library', 'Application Support', 'Collect Direct Desktop', 'journal.sqlite');
  if (!outsideRepository(path)) {
    throw new DesktopError('invalid_configuration', 'Use an absolute private journal path outside the repository.');
  }
  const policyPath = env.COLLECT_DESKTOP_POLICY;
  function loadPolicy() {
    let value = DEFAULT_POLICY;
    if (policyPath) {
      try {
        value = readStablePolicy(policyPath);
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
