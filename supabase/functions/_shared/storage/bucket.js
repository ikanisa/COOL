import {applicationWork, guardedFetch} from '../application-fence.js';
import {ApiError, digest} from '../domain/core.js';
import {decrypt} from '../domain/encryption.js';
import {compileSql} from '../postgres-compatibility-sql.js';
import {storageApplicationPool} from './application-pool.js';
import {canonical, ProtectedStorageProtocol, sha256, StorageProtocolError} from './protocol.js';
import {PostgresStorageJournal} from './postgres-journal.js';
import {SupabaseNativeTransport} from './supabase-transport.js';

const digestPattern = /^[a-f0-9]{64}$/;
const unavailable = name => new ApiError(503, `${name}_unavailable`, 'The configured service is unavailable.');

async function isPendingErasure(key, intent, meta, deletion) {
  if (!deletion || deletion.state !== 'pending' || deletion.key !== key ||
      deletion.expectedSha256 !== intent.sha256 || !intent.deleteTombstone ||
      intent.activeAttempt || intent.uploadUnresolved) return false;
  if (meta.key !== intent.key || meta.operationId !== intent.operationId ||
      meta.fingerprint !== intent.fingerprint || meta.size !== intent.size || meta.sha256 !== intent.sha256) {
    return false;
  }
  const scope = canonical(intent.scope);
  if (canonical(meta.scope) !== scope || canonical(deletion.scope) !== scope) return false;
  const descriptor = {key, operationId: deletion.operationId, scope: intent.scope, expectedSha256: intent.sha256};
  return deletion.fingerprint === await sha256(canonical(descriptor));
}

async function runGuardStatements(client, statements) {
  for (const statement of statements) {
    const {text, values} = compileSql(statement.sql, statement.values);
    await client.query(text, values);
  }
}

export class SupabaseObjectBucket {
  constructor(env) {
    this.env = env;
    this.bucket = env.COLLECT_PRIVATE_BUCKET ?? 'collect-evidence';
    this.pool = storageApplicationPool(env.DB);
    this.namespace = {origin: new URL(env.SUPABASE_URL).origin, bucket: this.bucket};
    this.journal = new PostgresStorageJournal(this.pool, {namespace: this.namespace});
    this.transport = new SupabaseNativeTransport({
      url: env.SUPABASE_URL,
      secretKey: env.SUPABASE_SECRET_KEY ?? env.SUPABASE_SERVICE_ROLE_KEY,
      bucket: this.bucket,
      authorizeMutation: () => applicationWork(env).assert(),
      fetchImpl: (url, options) => guardedFetch(env, 'storage', url, options),
    });
    this.protocol = new ProtectedStorageProtocol({transport: this.transport, journal: this.journal});
  }

  async checked(run) {
    try {
      return await run();
    } catch (error) {
      if (!(error instanceof StorageProtocolError)) throw error;
      const wrapped = new ApiError(error.status, error.code, 'Protected storage could not be confirmed. Keep the request pending.');
      wrapped.cause = error;
      throw wrapped;
    }
  }

  async put(key, value, options = {}) {
    return this.checked(async () => {
      const {scope, aad, sourceDigest} = options;
      if (typeof value !== 'string' || !scope || typeof aad !== 'string' || !digestPattern.test(sourceDigest ?? '')) {
        throw new ApiError(400, 'storage_identity_required', 'A protected source identity is required.');
      }
      const prior = await this.journal.getPayloadBinding(key);
      let customMetadata = {...(options.customMetadata ?? {})};
      if (prior && Object.hasOwn(customMetadata, 'key_id')) customMetadata.key_id = prior.keyId;
      const plaintextSha256 = customMetadata.sha256 ?? customMetadata.source_sha256;
      if (!digestPattern.test(plaintextSha256 ?? '')) {
        throw new ApiError(400, 'storage_identity_required', 'A protected source digest is required.');
      }
      const httpMetadata = options.httpMetadata ?? {};
      const descriptorFor = custom => ({
        scope, aad, keyId: prior?.keyId ?? this.env.DATA_KEY_ID, plaintextSha256,
        requestDigest: sourceDigest, httpMetadata, customMetadata: custom,
      });
      // Original reservations retain their fingerprint, including an interrupted
      // operation that stopped before creating a put intent.
      if (scope.purpose === 'roster_source' && !Object.hasOwn(customMetadata, 'sha256') &&
          customMetadata.source_sha256 === plaintextSha256) {
        const enriched = {...customMetadata, sha256: plaintextSha256};
        if (!prior || prior.sourceFingerprint === await sha256(canonical(descriptorFor(enriched)))) {
          customMetadata = enriched;
        }
      }

      const reservation = await this.journal.reservePayload(key, descriptorFor(customMetadata), value);
      if (reservation.sealedBody === null) {
        const intent = await this.journal.getPutByKey(key);
        if (!intent || intent.customMetadata.source_fingerprint !== reservation.sourceFingerprint) {
          throw unavailable('storage_reservation');
        }
        return this.protocol.confirmCommitted(intent);
      }
      const retainedPlaintext = await decrypt(this.env, reservation.sealedBody, aad);
      if (await digest(retainedPlaintext) !== plaintextSha256) throw unavailable('storage_plaintext_integrity');
      return this.protocol.put(key, reservation.sealedBody, {
        scope, httpMetadata,
        customMetadata: {...customMetadata, source_fingerprint: reservation.sourceFingerprint},
      });
    });
  }

  async read(key) {
    return this.checked(async () => {
      const intent = await this.journal.getPutByKey(key);
      const meta = await this.journal.getObject(key);
      if (!meta) {
        const probe = await this.transport.probe(key);
        if (this.protocol.provesAbsent(probe) && (!intent || intent.state === 'erased')) return null;
        throw unavailable('storage_untracked');
      }
      if (!intent || intent.state !== 'committed') throw unavailable('storage_metadata');
      return {meta, observed: await this.protocol.readAndVerify(intent)};
    });
  }

  describe({meta, observed}) {
    const version = observed.etag ?? meta.sha256;
    return {
      key: meta.key, size: meta.size, version, etag: version, sha256: meta.sha256,
      httpMetadata: meta.httpMetadata, customMetadata: meta.customMetadata,
    };
  }

  describeContent(read) {
    const bytes = read.observed.bytes;
    return {
      ...this.describe(read), body: new Blob([bytes]).stream(),
      text: async () => new TextDecoder().decode(bytes), arrayBuffer: async () => bytes.buffer,
    };
  }

  async head(key) {
    const read = await this.read(key);
    return read ? this.describe(read) : null;
  }

  async get(key) {
    const read = await this.read(key);
    return read ? this.describeContent(read) : null;
  }

  async observeRetention(key) {
    return this.checked(async () => {
      const intent = await this.journal.getPutByKey(key);
      const meta = await this.journal.getObject(key);
      if (!meta) {
        const object = await this.get(key);
        return {kind: object ? 'present' : 'absence_verified', object};
      }
      if (!intent || intent.state !== 'committed') throw unavailable('storage_metadata');
      const observed = await this.protocol.readAndVerify(intent, {allowMissing: true});
      if (observed) return {kind: 'present', object: this.describeContent({meta, observed})};

      // Only retention can observe the original pending delete identity.
      const deletion = await this.journal.getDeleteByKey(key);
      if (!await isPendingErasure(key, intent, meta, deletion)) throw unavailable('storage_pending_erasure_identity');
      return {kind: 'pending_erasure_absence', object: null, operationId: deletion.operationId, sourceSha256: intent.sha256};
    });
  }

  async delete(key, options = {}) {
    return this.checked(async () => {
      if (typeof options.guards !== 'function') {
        throw new ApiError(403, 'delete_authority_required', 'Current retention authority is required.');
      }
      const intent = await this.journal.getPutByKey(key);
      if (!intent) throw unavailable('storage_delete_identity');
      const journal = new PostgresStorageJournal(this.pool, {
        namespace: this.namespace,
        deleteGuards: async (client, current) => {
          const statements = await options.guards(current);
          await runGuardStatements(client, statements.slice(0, -2));
          return () => runGuardStatements(client, statements.slice(-2));
        },
      });
      const protocol = new ProtectedStorageProtocol({transport: this.transport, journal});
      return protocol.delete(key, {
        operationId: options.operationId ?? await sha256(`collect.storage.retention.v1\n${key}`),
        scope: intent.scope,
        expectedSha256: intent.sha256,
        requireAbsent: options.reconcileOnly === true,
        authorize: () => this.pool.transaction(async client => {
          await runGuardStatements(client, await options.guards(intent));
          return true;
        }),
      });
    });
  }

  async list({prefix = '', cursor = '', limit = 1000} = {}) {
    return this.checked(async () => {
      const inventory = await this.protocol.inventory();
      if (!inventory.complete) throw unavailable('storage_inventory');
      const all = inventory.objects.filter(object => object.key.startsWith(prefix) && object.key > cursor)
        .sort((a, b) => a.key.localeCompare(b.key));
      const items = all.slice(0, Math.min(limit, 1000));
      const metadataByKey = new Map(inventory.metadata.map(metadata => [metadata.key, metadata]));
      const truncated = all.length > items.length;
      return {
        objects: items.map(({key, size, classification}) => {
          const metadata = metadataByKey.get(key);
          return {key, size, customMetadata: metadata?.customMetadata ?? {}, httpMetadata: metadata?.httpMetadata ?? {}, classification};
        }),
        truncated,
        cursor: truncated ? items.at(-1)?.key : undefined,
        pending: inventory.puts.filter(intent => intent.state === 'pending'),
        anomalies: inventory.anomalies,
      };
    });
  }
}
