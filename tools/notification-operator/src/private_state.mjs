import {mkdir, readdir} from 'node:fs/promises';
import {join} from 'node:path';
import {canonical, keys, need, sanitized, sha, uuid} from './contract.mjs';
import {privateDirectory, privateRead, privateWrite} from './private_files.mjs';

export {privateDirectory, privateRead, privateWrite};

const MAX_ENTRIES = 100;
const STATUS_PHASES = ['unknown', 'rejected', 'resolved', 'not_observed'];
const entryName = sequence => String(sequence).padStart(4, '0') + '.json';

async function readEntry(path, requestId, sequence, previousDigest) {
  const {raw} = await privateRead(path);
  const value = JSON.parse(new TextDecoder('utf8', {fatal: true}).decode(raw));
  const encoded = canonical(value);
  need(raw.equals(Buffer.from(encoded + '\n')) && value.request_id === requestId &&
    value.sequence === sequence && value.previous_sha256 === previousDigest, 'operation_journal_integrity_failed');
  need(encoded === canonical(sanitized(value)), 'persisted_permit_or_plaintext_refused');
  return {value, digest: sha(raw)};
}

export class OperationJournal {
  constructor(root) {
    this.root = root;
  }

  async ready() {
    await privateDirectory(this.root);
    return this;
  }

  async load(id) {
    uuid(id);
    const dir = join(this.root, id);
    try {
      await privateDirectory(dir);
    } catch (error) {
      if (error.code === 'ENOENT') return null;
      throw error;
    }

    const names = (await readdir(dir)).sort();
    need(names.length > 0 && names.length <= MAX_ENTRIES, 'incomplete_operation_journal');
    let digest = null;
    let intent;
    let last;
    for (const [index, name] of names.entries()) {
      const sequence = index + 1;
      need(name === entryName(sequence), 'unexpected_operation_journal_entry');
      const entry = await readEntry(join(dir, name), id, sequence, digest);
      if (sequence === 1) {
        need(entry.value.phase === 'intent', 'original_intent_required');
        intent = entry.value;
      }
      digest = entry.digest;
      last = entry.value;
    }
    return {intent, last, sequence: names.length, last_sha256: digest};
  }

  async begin({action, args, session, authority}) {
    const id = uuid(args.request_id);
    await this.ready();
    const dir = join(this.root, id);
    try {
      await mkdir(dir, {mode: 0o700});
    } catch (error) {
      if (error.code === 'EEXIST') return {created: false, record: await this.load(id)};
      throw error;
    }

    const value = {
      request_id: id,
      sequence: 1,
      previous_sha256: null,
      phase: 'intent',
      action,
      args: sanitized(args),
      args_sha256: sha(canonical(args)),
      operator_session: session,
      authority_sha256: sha(authority),
    };
    const entry = await writeEntry(dir, value);
    return {created: true, record: {intent: entry.value, last: entry.value, sequence: 1, last_sha256: entry.digest}};
  }

  async append(id, status, {expectedLastSha256} = {}) {
    const record = await this.load(id);
    need(record, 'original_intent_required');
    need(expectedLastSha256 === undefined || expectedLastSha256 === record.last_sha256, 'operation_journal_advanced');
    need(record.sequence < MAX_ENTRIES, 'incomplete_operation_journal');
    keys(status, ['phase'], ['receipt', 'error_code']);
    need(STATUS_PHASES.includes(status.phase), 'invalid_operation_phase');

    const sequence = record.sequence + 1;
    const value = sanitized({...status, request_id: id, sequence, previous_sha256: record.last_sha256});
    // The previous digest rejects stale readers. Exclusive creation chooses
    // one writer when multiple callers still hold the same journal head.
    const entry = await writeEntry(join(this.root, id), value);
    return {intent: record.intent, last: entry.value, sequence, last_sha256: entry.digest};
  }
}

async function writeEntry(dir, value) {
  const path = join(dir, entryName(value.sequence));
  const digest = await privateWrite(path, value);
  const entry = await readEntry(path, value.request_id, value.sequence, value.previous_sha256);
  need(entry.digest === digest, 'operation_journal_integrity_failed');
  return entry;
}
