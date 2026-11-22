import {dirname, join} from 'node:path';
import {SqliteDesktopJournal} from './direct-desktop/journal.mjs';
import {SafeError, object} from './config.mjs';
import {
  canonical, digest, hasUnresolvedRetentionOperation, instant,
  isRetentionHash, isRetentionUuid, isUnconfirmedRetentionState,
} from './retention_contract.mjs';

const DISPATCH_LIMIT = 20;
const OBSERVATION_LIMIT = 20;
const RECORD_LIMIT = 1000;
const JOURNAL_MARKER = Object.freeze({contract_version: 1, scope: 'retention_operator_journal'});
const JOURNAL_TABLES = ['tickets', 'jobs', 'attempts', 'observations', 'policies', 'syncs', 'control'];
const STATES = ['prepared', 'dispatching', 'unknown', 'observed', 'cancelled'];
const KINDS = ['plan', 'claim', 'execute', 'reconcile'];

function fail() {
  throw new SafeError('retention_journal_unavailable',
    'The private retention journal could not be verified. Preserve it and the original operation references; no action was replayed.');
}

function validatePreview(preview) {
  if (!object(preview) ||
      Object.keys(preview).sort().join(',') !== 'binding,contract_version,created_at,expected,input,kind,operation_id,scope' ||
      preview.contract_version !== 1 || preview.scope !== 'approved_eligible_data_disposition' ||
      !KINDS.includes(preview.kind) || !isRetentionUuid(preview.operation_id) || !instant(preview.created_at) ||
      !object(preview.binding) || !object(preview.input) || !object(preview.expected)) fail();
  if (preview.kind === 'reconcile' ? Object.hasOwn(preview.input, 'p_operation_id') :
    preview.input.p_operation_id !== preview.operation_id) fail();
}

function validateRecord(record) {
  if (!object(record) ||
      Object.keys(record).sort().join(',') !== 'dispatches,observations,preview,preview_sha256,receipt,state,version' ||
      record.version !== 1 || !STATES.includes(record.state) || !Number.isSafeInteger(record.dispatches) ||
      record.dispatches < 0 || record.dispatches > DISPATCH_LIMIT || !Array.isArray(record.observations) ||
      record.observations.length > OBSERVATION_LIMIT) fail();
  validatePreview(record.preview);
  if (!isRetentionHash(record.preview_sha256) || digest(record.preview) !== record.preview_sha256) fail();
  return record;
}

function storedRecord(tx, hash) {
  if (!isRetentionHash(hash)) fail();
  const record = validateRecord(tx.get('attempts', hash));
  if (record.preview_sha256 !== hash) fail();
  return record;
}

function initializeJournal(tx) {
  const marker = tx.get('control', 'retention');
  if (marker === null) {
    if (JOURNAL_TABLES.some(table => tx.all(table).length)) fail();
    tx.put('control', 'retention', JOURNAL_MARKER);
  } else if (canonical(marker) !== canonical(JOURNAL_MARKER)) {
    fail();
  }
}

export class RetentionJournal {
  #store;

  constructor(config) {
    this.#store = new SqliteDesktopJournal(join(dirname(config.credentialFile), 'retention.sqlite'));
    try {
      this.#store.transaction(initializeJournal);
    } catch (error) {
      this.#store.close();
      throw error;
    }
  }

  close() { this.#store.close(); }
  list() { return this.#store.transaction(tx => tx.all('attempts').map(validateRecord)); }
  get(hash) { return this.#store.transaction(tx => storedRecord(tx, hash)); }

  operation(id) {
    if (!isRetentionUuid(id)) fail();
    const matches = this.list().filter(row => row.preview.operation_id === id);
    if (matches.length !== 1) fail();
    return matches[0];
  }

  save(preview) {
    validatePreview(preview);
    const record = {
      version: 1, preview, preview_sha256: digest(preview), state: 'prepared',
      dispatches: 0, receipt: null, observations: [],
    };
    return this.#store.transaction(tx => {
      const records = tx.all('attempts').map(validateRecord);
      if (records.length >= RECORD_LIMIT || records.some(row => row.preview.operation_id === preview.operation_id)) fail();
      if (hasUnresolvedRetentionOperation(records, preview.kind, preview.input)) {
        throw new SafeError('retention_original_operation_unresolved',
          'An original operation in this scope is still prepared or unconfirmed. Recover or review that operation; no replacement identity was created.');
      }
      tx.put('attempts', record.preview_sha256, record);
      return record;
    });
  }

  #update(hash, change) {
    return this.#store.transaction(tx => {
      const next = change(storedRecord(tx, hash));
      tx.put('attempts', hash, next);
      return next;
    });
  }

  begin(hash, {retry = false, expectedDispatches = 0} = {}) {
    return this.#update(hash, record => {
      if (record.dispatches !== expectedDispatches || record.dispatches >= DISPATCH_LIMIT ||
        (!retry && record.state !== 'prepared') ||
        (retry && (!isUnconfirmedRetentionState(record.state) || record.preview.kind === 'reconcile'))) fail();
      return {...record, state: 'dispatching', dispatches: record.dispatches + 1};
    });
  }

  finish(hash, dispatches, state, receipt) {
    if (state !== 'observed' && state !== 'unknown') fail();
    return this.#update(hash, record => {
      if (record.dispatches !== dispatches || !isUnconfirmedRetentionState(record.state)) fail();
      return {...record, state, receipt};
    });
  }

  observe(hash, observation, {receipt = null, committed = false} = {}) {
    return this.#update(hash, record => {
      if (record.dispatches < 1 || record.state === 'cancelled') fail();
      return {
        ...record,
        state: committed || record.state === 'observed' ? 'observed' : 'unknown',
        receipt: receipt ?? record.receipt,
        observations: [...record.observations.slice(1 - OBSERVATION_LIMIT), observation],
      };
    });
  }

  cancel(hash) {
    return this.#update(hash, record => {
      if (record.state !== 'prepared' || record.dispatches !== 0) fail();
      return {...record, state: 'cancelled'};
    });
  }
}
