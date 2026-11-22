import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { defs as nativeDefs } from '../../../supabase/functions/_shared/domain/burimunsi/wire/burimunsi.generated.mjs';
import {
  isUtf8JsonMediaType, parseWire, validateQuery, validateSchema,
} from '../../../supabase/functions/_shared/domain/burimunsi/wire/runtime.mjs';
import { HELD_V2_MIGRATION_SHA } from './catalog.mjs';

const contract = JSON.parse(readFileSync(new URL('./contract.json', import.meta.url), 'utf8'));
const defs = { binding: nativeDefs.binding, ...contract.$defs };
const ports = Object.freeze({
  observationRecoveryV2Capability: 'recoveryV2Capability',
  observationRecoveryV2Hold: 'recoverHeldV2',
  observationRecoveryV2Ack: 'recoverHeldV2Ack',
});

class CandidateError extends Error {
  constructor(status) {
    super(`Held recovery candidate returned ${status}`);
    this.status = status;
  }
}

function requireCondition(condition, status) {
  if (!condition) throw new CandidateError(status);
}

function validate(status, check) {
  try {
    return check();
  } catch {
    throw new CandidateError(status);
  }
}

/** Fixture entry point. No HTTP listener, real service ports or runtime flags. */
export function createHeldRecoveryV2Candidate({
  enabled = false, sourceSha256, groupId, observations,
} = {}) {
  return async function run({
    operation, actor, binding, headers, rawQuery = '', readBody,
  }) {
    requireCondition(enabled === true && Object.hasOwn(ports, operation), 404);
    requireCondition(typeof sourceSha256 === 'string' && /^[a-f0-9]{64}(?![\s\S])/.test(sourceSha256), 503);
    validate(400, () => validateSchema(defs, 'binding', binding));
    requireCondition(actor?.id === binding.actorId && actor.groupId === groupId &&
      binding.groupId === groupId && actor.installationId === binding.installationId &&
      actor.generation === binding.generation, 403);
    requireCondition(headers?.get('x-burimunsi-held-source-sha256') === sourceSha256 &&
      headers.get('x-burimunsi-held-migration-sha256') === HELD_V2_MIGRATION_SHA, 403);

    const release = Object.freeze({ sourceSha256, migrationSha256: HELD_V2_MIGRATION_SHA });
    const query = validate(400, () => validateQuery(defs, operation, rawQuery));
    const port = ports[operation];
    requireCondition(typeof observations?.[port] === 'function', 503);

    let data;
    if (operation === 'observationRecoveryV2Capability') {
      const consentGeneration = Number(query.expectedConsentGeneration);
      requireCondition(Number.isSafeInteger(consentGeneration), 400);
      data = await observations[port](actor, consentGeneration, release);
      requireCondition(data?.groupId === groupId && data.sourceSha256 === release.sourceSha256 &&
        data.migrationSha256 === release.migrationSha256 && data.consentGeneration === consentGeneration, 503);
    } else {
      requireCondition(isUtf8JsonMediaType(headers.get('content-type')) && typeof readBody === 'function', 400);
      const rawBody = await readBody();
      const input = validate(400, () => validateSchema(defs, operation + '.request', parseWire(rawBody)));
      requireCondition(input.requestId === binding.requestId, 400);
      data = await observations[port](actor, input, release);
      requireCondition(data?.requestId === input.requestId &&
        data.bodySha256 === createHash('sha256').update(input.rawBody, 'utf8').digest('hex') &&
        data.expectedConsentGeneration === input.expectedConsentGeneration, 503);
      if (operation === 'observationRecoveryV2Ack') {
        const acknowledged = data.state === 'acknowledged';
        requireCondition(data.sourceKey === input.sourceKey &&
          acknowledged === (data.sourceId !== null) &&
          data.autoProcessing === (acknowledged ? 'held' : 'unknown'), 503);
      }
    }

    const body = { contractVersion: contract.contractVersion, ok: true, binding, data };
    validate(503, () => validateSchema(defs, operation + '.response', body));
    return { body, headers: { 'cache-control': 'no-store' } };
  };
}
