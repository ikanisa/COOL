import { verifyRetainedObject } from '../../storage-identity.js';
import { digest } from '../core.js';
import { BuriError } from './errors.js';
import {
  decodeObservationPayload,
  decodeObservationRecord as row,
  mapObservationError as mapped,
  matchesLegacyObservationPayload,
  observationActorIdentity,
  observationContentFingerprint,
  observationStorageTarget as target,
  requireObservation as check,
  sameObservationValue as same,
  verifyObservationJournal,
} from './observation-evidence.js';
import { sha256 } from './values.js';

const keyLookup = 'SELECT private.burimunsi_observation_key_lookup($1,$2,$3) AS result';

/** Verify retained objects and the journal snapshots that authorize their use.
 * This port owns temporary decrypted bytes and staged storage witnesses. */
export class PostgresObservationReconcileEvidence {
  constructor({ authority, env, custody, getStorageWitnesses, current, context, namespace }) {
    Object.assign(this, {
      authority,
      env,
      custody,
      getStorageWitnesses,
      current,
      context,
      namespace,
      groupId: authority.groupId,
    });
  }

  get storageWitnesses() {
    return this.getStorageWitnesses();
  }

  lookupSourceKey(tx, sourceKey, contentSha, bodySha) {
    return tx.unsafe(keyLookup, [sourceKey, contentSha, bodySha]);
  }

  async verifyJournal(tx, record) {
    const journal = await this.custody.journal(tx, record.object_key, target(record));
    await verifyObservationJournal(record, journal);
    return journal;
  }

  matchesJournal(journal, expected) {
    return this.custody.sameJournal(journal, expected);
  }

  releaseWitness(binding) {
    this.storageWitnesses.forget(binding);
  }

  async verifyKeyedObject(contentSha, bodySha, prior) {
    let bytes;
    try {
      await this.authority.assertOwned();
      bytes = await verifyRetainedObject(this.env, prior);
      await this.authority.assertOwned();
      const p = decodeObservationPayload(bytes);
      check(
        p && p.provenance === 'native_observation_unverified' && p.source_mode === 'catch_up' &&
          p.complete === false &&
          typeof p.raw_body === 'string' && await sha256(p.raw_body) === bodySha &&
          await observationContentFingerprint({
              rawSender: p.raw_sender,
              serviceCentreAt: p.service_centre_at,
              inboxReceivedAt: p.inbox_received_at,
              subscriptionId: p.subscription_id,
            }, bodySha) === contentSha,
        'observation_changed',
        409,
      );
    } finally {
      bytes?.fill(0);
    }
  }
  /** Internal candidate descriptors never leave the Edge runtime. The SQL
   * lookup requires reveal-authorized current Admin and consent, constrains the
   * imported lineage to this account/collection, and caps the complete set. */
  async readLegacyCandidates(tx, actor, bodySha) {
    let found;
    try {
      found = await tx.unsafe('SELECT private.burimunsi_observation_legacy_candidates($1) AS result', [
        bodySha,
      ]);
    } catch (error) {
      if (error?.code === '55000') throw new BuriError('observation_item_unavailable', 503);
      throw error;
    }
    check(found.length === 1 && Array.isArray(found[0].result) && found[0].result.length <= 4);
    const records = found[0].result.map(row);
    check(
      records.every((r) => r.bodySha256 === bodySha && r.sessionId === actor.sessionId) &&
        new Set(records.map((r) => r.id)).size === records.length,
      'observation_changed',
      409,
    );
    return records;
  }
  /** Revalidate only a previously staged, decrypted legacy witness. This runs
   * inside an authority fence; sealed() checks local ciphertext and ownership
   * without fetching from Storage. The caller maps errors at its own boundary. */
  async verifyLegacyFinal(tx, actor, value, expectedCtx, candidates, proof) {
    const { ctx } = await this.context(tx, actor),
      current = await this.readLegacyCandidates(tx, actor, value.bodySha256);
    check(
      same(ctx, expectedCtx) && same(current, candidates) && same(await this.namespace(tx), proof.namespace),
      'observation_changed',
      409,
    );
    for (let i = 0; i < current.length; i++) {
      const record = current[i], journal = await this.verifyJournal(tx, record);
      check(this.custody.sameJournal(journal, proof.journals[i]), 'observation_changed', 409);
      await this.storageWitnesses.sealed(proof.binding, record.object_key, journal);
    }
  }
  /** Decrypt only after proving the committed ciphertext against its journal.
   * Missing metadata, unavailable objects, multiple exact matches and any
   * changed authority/custody remain unresolved; this method creates no data. */
  async verifyLegacyCandidates(actor, value, expectedCtx, candidates, deferValidation = false) {
    let binding, release = true;
    try {
      const initial = await this.authority.write(async (tx) => {
        const { ctx } = await this.context(tx, actor),
          current = await this.readLegacyCandidates(tx, actor, value.bodySha256);
        check(same(ctx, expectedCtx) && same(current, candidates), 'observation_changed', 409);
        const namespace = await this.namespace(tx), journals = [];
        for (const record of current) {
          const journal = await this.verifyJournal(tx, record);
          journals.push(journal);
        }
        binding = {
          kind: 'legacy_reconcile',
          groupId: this.groupId,
          identity: observationActorIdentity(actor),
          sourceKey: value.sourceKey,
          sources: current,
        };
        const plan = await this.storageWitnesses.stage(
          binding,
          current.map((record, i) => ({ key: record.object_key, journal: journals[i] })),
        );
        return { namespace, journals, plan };
      });
      await this.storageWitnesses.prefetch(initial.plan);
      const matches = [];
      for (let i = 0; i < candidates.length; i++) {
        const record = candidates[i];
        let bytes;
        try {
          const sealed = await this.storageWitnesses.sealed(binding, record.object_key, initial.journals[i]);
          bytes = await this.custody.decrypt(sealed, target(record).aad);
          check(
            bytes instanceof Uint8Array && bytes.length === record.size_bytes &&
              await digest(bytes) === record.object_sha256,
            'observation_item_unavailable',
            503,
          );
          if (await matchesLegacyObservationPayload(decodeObservationPayload(bytes), value)) {
            matches.push(record);
          }
        } finally {
          bytes?.fill(0);
        }
      }
      check(matches.length <= 1, 'observation_item_conflict', 409);
      await this.authority.assertOwned();
      // For the singleton batch only, the caller performs these same final
      // authorization, candidate, namespace, journal and sealed-witness checks
      // in its existing batch-wide transaction, then releases the witness.
      if (deferValidation) {
        release = false;
        return {
          match: matches[0] ?? null,
          journals: initial.journals,
          namespace: initial.namespace,
          binding,
        };
      }
      await this.authority.write((tx) =>
        this.verifyLegacyFinal(tx, actor, value, expectedCtx, candidates, { ...initial, binding })
      );
      await this.authority.assertOwned();
      return { match: matches[0] ?? null, journals: initial.journals, namespace: initial.namespace };
    } catch (error) {
      const failure = mapped(error);
      if (failure.status === 403 || failure.status === 409) throw failure;
      throw new BuriError('observation_item_unavailable', 503);
    } finally {
      if (binding && release) this.releaseWitness(binding);
    }
  }
  async checkDuplicate(actor, value, contentSha, bodySha, prior) {
    await this.verifyKeyedObject(contentSha, bodySha, prior);
    await this.authority.write(async (tx) => {
      await this.current(tx, actor);
      const rows = await this.lookupSourceKey(tx, value.sourceKey, contentSha, bodySha);
      check(
        rows.length === 1 && rows[0].result && same(row(rows[0].result), prior),
        'observation_changed',
        409,
      );
      await this.verifyJournal(tx, prior);
    });
    await this.authority.assertOwned();
  }
}
