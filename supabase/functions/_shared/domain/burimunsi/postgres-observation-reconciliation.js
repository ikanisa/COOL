import { BuriError } from './errors.js';
import { exactKeys } from './values.js';
import { readLatestRetainedObservationId } from './postgres-observation-listing.js';
import { PostgresObservationReconcileEvidence } from './postgres-observation-reconcile-evidence.js';
import {
  decodeObservationRecord as row,
  isObservationSenderAllowed,
  mapObservationError as mapped,
  OBSERVATION_HASH as HASH,
  observationContentFingerprint,
  requireObservation as check,
  sameObservationValue as same,
  validateReconcileInput,
} from './observation-evidence.js';

function isItemFailure(error) {
  return error instanceof BuriError &&
    ['observation_item_conflict', 'observation_item_unavailable'].includes(error.code);
}

function batchKeyFailure(error) {
  // SQL gives a definite per-key conflict or an outstanding/invalid reservation.
  if (error?.code === '23505' && error.message === 'burimunsi_observation_source_conflict') {
    return new BuriError('observation_item_conflict', 409);
  }
  if (
    error?.code === '55000' &&
    ['burimunsi_observation_source_pending', 'burimunsi_observation_storage_changed'].includes(error.message)
  ) {
    return new BuriError('observation_item_unavailable', 503);
  }
  return error;
}

function batchWitnessFailure(error) {
  if (error instanceof BuriError && error.code === 'observation_changed') {
    return new BuriError('observation_item_conflict', 409);
  }
  if (['receipt_unavailable', 'receipt_integrity_failed'].includes(error?.code)) {
    return new BuriError('observation_item_unavailable', 503);
  }
  return error;
}

/** Reconcile opaque inbox keys with existing receipts under the current actor.
 * The custody fences and witness checks never commit a receipt or a payment. */
export class PostgresObservationReconciliation {
  #evidence;

  constructor({ authority, context, namespace, ...evidence }) {
    this.authority = authority;
    this.context = context;
    this.namespace = namespace;
    this.groupId = authority.groupId;
    this.#evidence = new PostgresObservationReconcileEvidence({ authority, context, namespace, ...evidence });
  }

  /** Compare only a phone-supplied, opaque inbox identity and content digest.
   * latestRecordedSourceId is current-actor retention order; it is not proof of
   * phone chronology, and a missing key never starts an upload or financial work. */
  async reconcile(actor, input) {
    const value = validateReconcileInput(input);
    const contentSha = await observationContentFingerprint(value, value.bodySha256);
    const snapshot = async (tx, includeLatest) => {
      const { ctx, profile } = await this.context(tx, actor);
      const { record, candidates } = await this.#readItem(tx, actor, profile, value, contentSha);
      const latestRecordedSourceId = includeLatest ? await readLatestRetainedObservationId(tx) : null;
      return { ctx, record, candidates, latestRecordedSourceId };
    };
    try {
      // Repeatable-read snapshots keep the key and latest retained page in one
      // view. A pending reservation or changed storage raises; neither is absence.
      const initial = await this.authority.read(async (tx) => {
        const first = await snapshot(tx, false);
        return first.record || first.candidates.length
          ? first
          : { ...first, latestRecordedSourceId: await readLatestRetainedObservationId(tx) };
      });
      if (!initial.record && !initial.candidates.length) {
        await this.authority.assertOwned();
        return {
          groupId: this.groupId,
          sourceKey: value.sourceKey,
          state: 'missing',
          sourceId: null,
          latestRecordedSourceId: initial.latestRecordedSourceId,
        };
      }
      // Verify actual retained bytes and custody, not a local "seen" marker.
      const legacy = initial.record
        ? null
        : await this.#evidence.verifyLegacyCandidates(actor, value, initial.ctx, initial.candidates);
      if (initial.record) {
        await this.checkDuplicate(actor, value, contentSha, value.bodySha256, initial.record);
      }
      if (legacy) {
        await this.authority.write(async (tx) => {
          const fenced = await snapshot(tx, false);
          check(
            same(fenced.ctx, initial.ctx) && same(fenced.record, initial.record) &&
              same(fenced.candidates, initial.candidates),
            'observation_changed',
            409,
          );
          check(same(await this.namespace(tx), legacy.namespace), 'observation_changed', 409);
          for (let i = 0; i < initial.candidates.length; i++) {
            const prior = initial.candidates[i],
              journal = await this.#evidence.verifyJournal(tx, prior);
            check(this.#evidence.matchesJournal(journal, legacy.journals[i]), 'observation_changed', 409);
          }
        });
      }
      const final = await this.authority.read((tx) => snapshot(tx, true));
      check(
        same(final.record, initial.record) && same(final.candidates, initial.candidates) &&
          same(final.ctx, initial.ctx),
        'observation_changed',
        409,
      );
      await this.authority.assertOwned();
      const matched = final.record ?? legacy?.match ?? null;
      return {
        groupId: this.groupId,
        sourceKey: value.sourceKey,
        state: matched ? 'matched' : 'missing',
        sourceId: matched?.id ?? null,
        latestRecordedSourceId: final.latestRecordedSourceId,
      };
    } catch (error) {
      throw mapped(error);
    }
  }
  /** Verify a bounded set of phone witnesses. Each result describes the final
   * authorized snapshot; this never writes observations or financial state. */
  async reconcileBatch(actor, input) {
    exactKeys(input, ['items']);
    check(
      Array.isArray(input.items) && input.items.length >= 1 && input.items.length <= 20,
      'invalid_request',
      400,
    );
    const values = input.items.map(validateReconcileInput);
    check(new Set(values.map((v) => v.sourceKey)).size === values.length, 'invalid_request', 400);
    const hashes = await Promise.all(values.map((v) => observationContentFingerprint(v, v.bodySha256)));
    const snapshot = (tx) => this.#readBatchSnapshot(tx, actor, values, hashes);
    let initial;
    const legacy = new Map();
    try {
      initial = await this.authority.read(snapshot);
      check(
        initial.candidates.reduce((n, items) => n + items.length, 0) <= 20,
        'observation_item_unavailable',
        503,
      );
      const indexes = initial.records.map((record, i) => record || initial.candidates[i].length ? i : -1)
        .filter((i) => i >= 0);
      const batch = { actor, values, hashes, initial, indexes, legacy };
      await this.#verifyBatchObjects(batch);
      if (indexes.length) await this.#verifyBatchJournals(batch, snapshot);
      // authority.read is REPEATABLE READ, so the keys and authorization are
      // rechecked together after the network and custody operations.
      const final = await this.authority.read(snapshot);
      check(
        same(final.ctx, initial.ctx) && same(final.records, initial.records) &&
          same(final.candidates, initial.candidates),
        'observation_changed',
        409,
      );
      const matches = final.records.map((r, i) => r ?? legacy.get(i)?.match ?? null),
        ids = matches.filter(Boolean).map((r) => r.id);
      check(new Set(ids).size === ids.length, 'observation_item_conflict', 409);
      await this.authority.assertOwned();
      return {
        groupId: this.groupId,
        items: values.map((v, i) => ({
          sourceKey: v.sourceKey,
          state: matches[i] ? 'matched' : 'missing',
          sourceId: matches[i]?.id ?? null,
        })),
      };
    } catch (error) {
      if (isItemFailure(error)) {
        // The error itself reveals no key or content. Still recheck current
        // authority and context after any asynchronous read before releasing it.
        try {
          const current = await this.authority.read((tx) => this.context(tx, actor));
          if (initial) check(same(current.ctx, initial.ctx), 'observation_changed', 409);
          await this.authority.assertOwned();
        } catch (recheckError) {
          throw mapped(recheckError);
        }
      }
      throw mapped(error);
    } finally {
      for (const proof of legacy.values()) if (proof.binding) this.#evidence.releaseWitness(proof.binding);
    }
  }
  async #readBatchSnapshot(tx, actor, values, hashes) {
    const { ctx, profile } = await this.context(tx, actor);
    const records = [], candidates = [];
    for (let i = 0; i < values.length; i++) {
      const item = await this.#readItem(tx, actor, profile, values[i], hashes[i], batchKeyFailure);
      records.push(item.record);
      candidates.push(item.candidates);
    }
    return { ctx, records, candidates };
  }

  async #readItem(tx, actor, profile, value, contentSha, mapKeyError) {
    check(isObservationSenderAllowed(value.rawSender, profile), 'unsupported_receipt', 422);
    let found;
    try {
      found = await this.#evidence.lookupSourceKey(tx, value.sourceKey, contentSha, value.bodySha256);
    } catch (error) {
      throw mapKeyError ? mapKeyError(error) : error;
    }
    check(found.length === 1);
    const record = found[0].result === null ? null : row(found[0].result);
    if (record) {
      check(
        record.bodySha256 === value.bodySha256 && record.sessionId === actor.sessionId,
        'observation_changed',
        409,
      );
    }
    const candidates = record ? [] : await this.#evidence.readLegacyCandidates(tx, actor, value.bodySha256);
    return { record, candidates };
  }

  async #verifyBatchObjects({ actor, values, hashes, initial, indexes, legacy }) {
    // Both the custody checks and Storage's journal reads acquire the same
    // database mutation lock. Serialize complete item checks within this batch
    // so its own workers cannot exhaust the lock timeout against each other.
    // No transaction or mutation lock is held during network operations.
    let next = 0, failure = null;
    let verificationTail = Promise.resolve();
    const serialize = (fn) => {
      const task = verificationTail.then(fn);
      // Drain already-started workers even if one item fails; that prevents an
      // item-specific conflict from hiding an independently observed outage.
      verificationTail = task.then(() => {}, () => {});
      return task;
    };
    const worker = async () => {
      while (!failure && next < indexes.length) {
        const i = indexes[next++];
        try {
          if (initial.records[i]) {
            await serialize(() =>
              this.#evidence.verifyKeyedObject(hashes[i], values[i].bodySha256, initial.records[i])
            );
          } else {
            const proof = await serialize(() =>
              this.#evidence.verifyLegacyCandidates(
                actor,
                values[i],
                initial.ctx,
                initial.candidates[i],
                values.length === 1,
              )
            );
            legacy.set(i, proof);
          }
        } catch (error) {
          const itemError = batchWitnessFailure(error);
          // Do not let an item issue mask an independently observed outage or
          // revoked request while other bounded reads are still settling.
          if (!failure || isItemFailure(failure) && !isItemFailure(itemError)) failure = itemError;
        }
      }
    };
    await Promise.all(Array.from({ length: Math.min(3, indexes.length) }, worker));
    if (failure) throw failure;
  }

  async #verifyBatchJournals({ actor, values, initial, indexes, legacy }, snapshot) {
    // The normal custody fence serializes journal verification with storage
    // mutation; it does not itself write an observation or financial record.
    const singleton = legacy.get(indexes[0]);
    let itemFinalPending = Boolean(singleton?.binding);
    try {
      await this.authority.write(async (tx) => {
        if (itemFinalPending) {
          // Keep the original item validation and its error boundary ahead of the
          // batch-wide checks. Storage bytes are already prefetched outside SQL.
          await this.#evidence.verifyLegacyFinal(
            tx,
            actor,
            values[0],
            initial.ctx,
            initial.candidates[0],
            singleton,
          );
          itemFinalPending = false;
        }
        const fenced = await snapshot(tx);
        check(
          same(fenced.ctx, initial.ctx) && same(fenced.records, initial.records) &&
            same(fenced.candidates, initial.candidates),
          'observation_changed',
          409,
        );
        if (legacy.size) {
          const namespace = await this.namespace(tx);
          for (const proof of legacy.values()) {
            check(same(namespace, proof.namespace), 'observation_changed', 409);
          }
        }
        for (const i of indexes) {
          const records = initial.records[i] ? [initial.records[i]] : initial.candidates[i];
          for (let j = 0; j < records.length; j++) {
            const prior = records[j],
              journal = await this.#evidence.verifyJournal(tx, prior);
            if (!initial.records[i]) {
              check(
                this.#evidence.matchesJournal(journal, legacy.get(i).journals[j]),
                'observation_changed',
                409,
              );
            }
          }
        }
      });
    } catch (error) {
      if (itemFinalPending) {
        const failure = mapped(error);
        if (failure.code === 'observation_changed') throw new BuriError('observation_item_conflict', 409);
        if (failure.status === 403 || failure.status === 409) throw failure;
        throw new BuriError('observation_item_unavailable', 503);
      }
      throw error;
    }
    if (singleton?.binding) await this.authority.assertOwned();
  }

  /** Collection-wide metadata only; actor and consent are current in the same
   * repeatable-read transaction as the underlying reservation snapshot. */
  reconcileStatus(actor) {
    return this.#statusSnapshot(actor, false);
  }
  async reconcileVerifiedStatus(actor) {
    return { ...await this.#statusSnapshot(actor, true), scope: 'verified_collection' };
  }
  async #statusSnapshot(actor, verified) {
    try {
      const result = await this.authority.read(async (tx) => {
        await this.context(tx, actor);
        const rows = await tx.unsafe(
          verified
            ? 'SELECT private.burimunsi_observation_reconcile_verified_status() AS result'
            : 'SELECT private.burimunsi_observation_reconcile_status() AS result',
        );
        check(rows.length === 1);
        const value = rows[0].result;
        check(
          value && value.groupId === this.groupId && typeof value.hasPending === 'boolean' &&
            typeof value.hasRecorded === 'boolean' && typeof value.hasUnmatchedCanonical === 'boolean' &&
            Number.isSafeInteger(value.recordedCount) && value.recordedCount >= 0 &&
            value.recordedCount <= 100000 &&
            value.hasRecorded === (value.recordedCount > 0) && HASH.test(value.revision ?? ''),
        );
        return {
          groupId: this.groupId,
          hasPending: value.hasPending,
          hasRecorded: value.hasRecorded,
          recordedCount: value.recordedCount,
          hasUnmatchedCanonical: value.hasUnmatchedCanonical,
          revision: value.revision,
        };
      });
      await this.authority.assertOwned();
      return result;
    } catch (error) {
      throw mapped(error);
    }
  }
  checkDuplicate(actor, value, contentSha, bodySha, prior) {
    return this.#evidence.checkDuplicate(actor, value, contentSha, bodySha, prior);
  }
}
