import { ApiError, first, id, now, rows } from '../core.js';
import {
  MOMO_PARSER_VERSION,
  MOMO_PROMPT_VERSION,
  MOMO_SCHEMA_VERSION,
} from './extraction.js';

export const MOMO_MODEL = 'unconfigured-supabase-provider';
const LEASE_SECONDS = 180;
const lostLease = (error) =>
  /CHECK constraint|momo_processing_guards/.test(String(error));
// SQLite evaluates unixepoch() per statement. The Postgres adapter translates
// only this marker to its moving wall clock; app.unixepoch() stays unchanged.
const LEASE_CLOCK = 'unixepoch(/*collect_momo_lease_clock*/)';
// These values are durable job checkpoints in the existing unconstrained
// last_error column. They deliberately do not add a schema or enable jobs.
// A dispatch checkpoint is committed before the external call; after an
// uncertain result it must never be treated as permission to send again.
export const MOMO_JOB_CHECKPOINT = Object.freeze({
  preflight: 'momo_v2:preflight',
  dispatch: 'momo_v2:provider_dispatch',
  unknown: 'momo_v2:provider_outcome_unknown',
  retry: 'momo_v2:retry_safe',
  reparse: 'momo_v2:reviewed_reparse',
  preflightExhausted: 'momo_v2:preflight_exhausted',
  responseInvalid: 'momo_v2:response_invalid',
  budget: 'momo_v2:retry_budget_exhausted',
});
export const MOMO_UNCERTAIN_ERRORS = Object.freeze([
  MOMO_JOB_CHECKPOINT.unknown,
  MOMO_JOB_CHECKPOINT.dispatch,
  MOMO_JOB_CHECKPOINT.preflight,
  MOMO_JOB_CHECKPOINT.retry,
  MOMO_JOB_CHECKPOINT.reparse,
  'extraction_temporarily_unavailable',
  'invalid_source_or_output',
  'retry_budget_exhausted',
]);
export function momoOutcomeUnresolved(job) {
  if (!job) return false;
  return MOMO_UNCERTAIN_ERRORS.includes(job.last_error) ||
    job.state === 'needs_review' &&
      job.attempt_count > 0 &&
      (job.last_error === null || job.last_error === undefined);
}
const seconds = () => Math.floor(Date.now() / 1000),
  q = (env, sql, ...values) => env.DB.prepare(sql).bind(...values);
/** Commit this with the immutable raw row, never in a later HTTP request. */
export function processingInsert(
  env,
  rawId,
  {
    bindingId = null,
    bindingVersion = null,
    mode = 'live',
    createdAt = now(),
  } = {},
) {
  if (!['live', 'historical'].includes(mode)) {
    throw new ApiError(
      400,
      'invalid_processing_mode',
      'Use a supported source mode.',
    );
  }
  if (
    (bindingId === null) !== (bindingVersion === null) ||
    bindingId !== null &&
      (!Number.isSafeInteger(bindingVersion) || bindingVersion < 1)
  ) {
    throw new ApiError(
      400,
      'invalid_gateway_binding',
      'Select the enrolled receiving source.',
    );
  }
  return q(
    env,
    `INSERT INTO momo_processing_jobs(raw_sms_id,binding_id,binding_version,receiving_account_id,mode,state,available_at,created_at,updated_at)
 VALUES(?,?,?,(SELECT receiving_account_id FROM momo_gateway_bindings WHERE id=? AND version=?),?,?,unixepoch(),?,?)`,
    rawId,
    bindingId,
    bindingVersion,
    bindingId,
    bindingVersion,
    mode,
    bindingId === null ? 'source_unresolved' : 'pending',
    createdAt,
    createdAt,
  );
}

// A provider identity cannot silently collapse different balance observations.
// Missing and present values also differ; retaining the original immutable
// fact and flagging the source for reconciliation avoids guessing which value
// reflects the receiving wallet.
const coreFacts = [
  'provider',
  'provider_transaction_id',
  'event_kind',
  'original_transaction_id',
  'amount_minor',
  'currency',
  'currency_scale',
  'payer_name',
  'payer_identifier',
  'transaction_at',
  'fee_minor',
  'wallet_balance_after_minor',
];
export function finishStatements(
  env,
  job,
  account,
  {
    output = null,
    validation,
    outcome,
    state,
    facts = null,
    retry = false,
    jobError,
    modelId = env.MOMO_AI_MODEL ?? MOMO_MODEL,
    promptVersion = MOMO_PROMPT_VERSION,
  },
) {
  const stamp = now(), attemptId = id(), guardId = id(), candidateId = id();
  const args = [job.raw_sms_id, job.lease_token];
  const identity =
      'provider=? AND receiving_account_id=? AND event_kind=? AND provider_transaction_id=?',
    identityArgs = facts
      ? [
        facts.provider,
        job.receiving_account_id,
        facts.event_kind,
        facts.provider_transaction_id,
      ]
      : [];
  const comparisons = coreFacts.map((k) => `${k} IS ?`).join(' AND '),
    v = facts ? coreFacts.map((k) => facts[k] ?? null) : [];
  const outcomeSql = facts
    ? `CASE WHEN EXISTS(SELECT 1 FROM momo_transactions WHERE ${identity} AND NOT (${comparisons})) THEN 'conflict' WHEN EXISTS(SELECT 1 FROM momo_transactions WHERE ${identity}) THEN 'duplicate' ELSE 'accepted' END`
    : '?';
  const attempt = q(
    env,
    `INSERT INTO momo_parse_attempts(id,raw_sms_id,attempt_number,model_id,schema_version,prompt_version,parser_version,profile_version,profile_json,source_body_sha256,output_json,validation_json,outcome,created_at) SELECT ?,?,?,?,?,?,?,?,?,?,?,?,${outcomeSql},?`,
    attemptId,
    job.raw_sms_id,
    job.attempt_count,
    modelId,
    MOMO_SCHEMA_VERSION,
    promptVersion,
    MOMO_PARSER_VERSION,
    account?.profile_version ?? 'unverified',
    account?.profile_json ?? '{}',
    job.body_sha256,
    output === null ? null : JSON.stringify(output),
    JSON.stringify(validation),
    ...(facts ? [...identityArgs, ...v, ...identityArgs] : [outcome]),
    stamp,
  );
  // Lock the matching job row until the whole fact batch commits. An EXISTS
  // check alone can pass before a separate claim/parking transaction changes
  // the lease under READ COMMITTED. A no-op UPDATE is supported by both the
  // Postgres adapter and the existing transactional batch interface.
  const writes = [
    q(
      env,
      `UPDATE momo_processing_jobs SET lease_token=lease_token WHERE raw_sms_id=? AND state='processing' AND lease_token=? AND lease_until>${LEASE_CLOCK}`,
      ...args,
    ),
    q(
      env,
      `INSERT INTO momo_processing_guards(id,passed) SELECT ?,CASE WHEN changes()=1 AND EXISTS(SELECT 1 FROM momo_processing_jobs WHERE raw_sms_id=? AND state='processing' AND lease_token=? AND lease_until>${LEASE_CLOCK}) THEN 1 ELSE 0 END`,
      guardId,
      ...args,
    ),
    attempt,
  ];
  if (account) {
    writes.splice(
      2,
      0,
      q(
        env,
        `INSERT INTO momo_processing_guards(id,passed) SELECT ?,CASE WHEN EXISTS(SELECT 1 FROM momo_receiving_accounts WHERE id=? AND profile_version=? AND profile_json=? AND status=? AND profile_status=?) THEN 1 ELSE 0 END`,
        guardId + ':profile',
        account.id,
        account.profile_version,
        account.profile_json,
        account.status,
        account.profile_status,
      ),
    );
  }
  if (facts) {
    const values = {
      id: candidateId,
      receiving_account_id: job.receiving_account_id,
      ...facts,
      parse_attempt_id: attemptId,
      mode: job.mode,
      created_at: stamp,
      updated_at: stamp,
    };
    const fields = Object.keys(values);
    writes.push(
      q(
        env,
        `INSERT INTO momo_transactions(${fields.join(',')}) VALUES(${
          fields.map(() => '?').join(',')
        }) ON CONFLICT(provider,receiving_account_id,event_kind,provider_transaction_id) DO NOTHING`,
        ...Object.values(values),
      ),
    );
    // Comparison occurs inside the transaction so concurrent first sightings cannot overwrite facts.
    writes.push(
      q(
        env,
        `UPDATE momo_transactions SET has_conflict=1,allocation_state='needs_review',version=version+1,updated_at=? WHERE ${identity} AND NOT (${comparisons})`,
        stamp,
        ...identityArgs,
        ...v,
      ),
    );
    writes.push(
      q(
        env,
        `INSERT INTO momo_transaction_sources(transaction_id,raw_sms_id,parse_attempt_id,relation,created_at) SELECT id,?,?,CASE WHEN NOT (${comparisons}) THEN 'conflict' WHEN id=? THEN 'accepted' ELSE 'duplicate' END,? FROM momo_transactions WHERE ${identity}`,
        job.raw_sms_id,
        attemptId,
        ...v,
        candidateId,
        stamp,
        ...identityArgs,
      ),
    );
    writes.push(
      q(
        env,
        `UPDATE momo_processing_jobs SET state=CASE WHEN EXISTS(SELECT 1 FROM momo_transaction_sources WHERE raw_sms_id=? AND parse_attempt_id=? AND relation='conflict') THEN 'needs_review' ELSE 'completed' END,last_error=CASE WHEN EXISTS(SELECT 1 FROM momo_transaction_sources WHERE raw_sms_id=? AND parse_attempt_id=? AND relation='conflict') THEN 'provider_identity_conflict' ELSE NULL END,lease_token=NULL,lease_until=NULL,updated_at=? WHERE raw_sms_id=? AND state='processing' AND lease_token=? AND lease_until>${LEASE_CLOCK}`,
        job.raw_sms_id,
        attemptId,
        job.raw_sms_id,
        attemptId,
        stamp,
        job.raw_sms_id,
        job.lease_token,
      ),
    );
  } else {writes.push(
      q(
        env,
        `UPDATE momo_processing_jobs SET state=?,last_error=?,available_at=?,lease_token=NULL,lease_until=NULL,updated_at=? WHERE raw_sms_id=? AND state='processing' AND lease_token=? AND lease_until>${LEASE_CLOCK}`,
        state,
        jobError === undefined ? (validation[0]?.code ?? null) : jobError,
        seconds() + (retry ? Math.min(300, 15 * 2 ** job.attempt_count) : 0),
        stamp,
        job.raw_sms_id,
        job.lease_token,
      ),
    );}
  // If the terminal update did not affect exactly this still-owned row, roll
  // back the parse attempt and all candidate facts as one unit.
  writes.push(
    q(
      env,
      `INSERT INTO momo_processing_guards(id,passed) SELECT ?,CASE WHEN changes()=1 THEN 1 ELSE 0 END`,
      guardId + ':finish',
    ),
  );
  // Existing transport publishes invalidation areas only, never source facts.
  // One committed audit row wakes the received-payment/source-exception view.
  writes.push(
    q(
      env,
      `INSERT INTO audit_log(action,entity_type,entity_id,details_json,created_at) VALUES('momo.processing.updated','payment',?,'{}',?)`,
      job.raw_sms_id,
      stamp,
    ),
  );
  writes.push(
    q(
      env,
      'DELETE FROM momo_processing_guards WHERE id IN (?,?,?)',
      guardId,
      guardId + ':profile',
      guardId + ':finish',
    ),
  );
  return { writes, attemptId, state, facts };
}
export async function finishMomoJob(env, job, account, options) {
  const { writes, attemptId, state, facts } = finishStatements(
    env,
    job,
    account,
    options,
  );
  try {
    await env.DB.batch(writes);
  } catch (error) {
    if (lostLease(error)) return { state: 'superseded' };
    throw error;
  }
  if (facts) {
    const link = await first(
      env,
      'SELECT relation,transaction_id FROM momo_transaction_sources WHERE raw_sms_id=? AND parse_attempt_id=?',
      job.raw_sms_id,
      attemptId,
    );
    return {
      state: link.relation === 'conflict' ? 'needs_review' : 'completed',
      ...link,
    };
  }
  return { state };
}

// Only new work, an explicitly reviewed reparse, or a checkpoint known to be
// before provider dispatch may be claimed. Existing retry/processing rows from
// an older implementation cannot establish whether it sent a request.
const CLAIMABLE =
  `((state='pending' AND available_at<=unixepoch() AND ((attempt_count=0 AND last_error IS NULL) OR last_error='momo_v2:reviewed_reparse'))
 OR (state='retry' AND available_at<=unixepoch() AND last_error='momo_v2:retry_safe')
 OR (state='processing' AND lease_until<=${LEASE_CLOCK} AND last_error='momo_v2:preflight'))`;
const AMBIGUOUS =
  `((state='processing' AND lease_until<=${LEASE_CLOCK} AND coalesce(last_error,'')<>'momo_v2:preflight')
 OR (state='retry' AND coalesce(last_error,'')<>'momo_v2:retry_safe')
 OR (state='pending' AND NOT ((attempt_count=0 AND last_error IS NULL) OR coalesce(last_error,'')='momo_v2:reviewed_reparse')))`;

export async function claimMomoJob(env, rawId) {
  const token = id(), stamp = now();
  const claimed = await q(
    env,
    `UPDATE momo_processing_jobs SET state='processing',lease_token=?,lease_until=${LEASE_CLOCK}+?,attempt_count=attempt_count+1,last_error=?,updated_at=? WHERE raw_sms_id=? AND attempt_count<max_attempts AND ${CLAIMABLE} RETURNING *`,
    token,
    LEASE_SECONDS,
    MOMO_JOB_CHECKPOINT.preflight,
    stamp,
    rawId,
  ).first();
  return { claimed, token };
}

export async function checkpointMomoDispatch(env, rawId, token) {
  // This committed compare-and-set precedes the external effect. If its ACK is
  // lost no provider request starts here; a committed marker is still parked by
  // the next sweep and an uncommitted preflight can safely be reclaimed.
  const dispatchGuard = id();
  try {
    await env.DB.batch([
      q(
        env,
        `UPDATE momo_processing_jobs SET last_error=?,updated_at=? WHERE raw_sms_id=? AND state='processing' AND lease_token=? AND lease_until>${LEASE_CLOCK} AND last_error=?`,
        MOMO_JOB_CHECKPOINT.dispatch,
        now(),
        rawId,
        token,
        MOMO_JOB_CHECKPOINT.preflight,
      ),
      // The UPDATE may wait on a row lock after evaluating its predicate. This
      // separate statement rechecks the moving clock while the row is locked.
      q(
        env,
        `INSERT INTO momo_processing_guards(id,passed) SELECT ?,CASE WHEN changes()=1 AND EXISTS(SELECT 1 FROM momo_processing_jobs WHERE raw_sms_id=? AND state='processing' AND lease_token=? AND last_error=? AND lease_until>${LEASE_CLOCK}) THEN 1 ELSE 0 END`,
        dispatchGuard,
        rawId,
        token,
        MOMO_JOB_CHECKPOINT.dispatch,
      ),
      q(env, 'DELETE FROM momo_processing_guards WHERE id=?', dispatchGuard),
    ]);
  } catch (error) {
    if (lostLease(error)) return false;
    throw error;
  }
  return true;
}

export async function findMomoJobs(env, count) {
  // Bound recovery work separately from the requested processing batch. Old
  // ambiguous attempts and expired dispatched work are parked, not retried.
  await q(
    env,
    `UPDATE momo_processing_jobs SET state='needs_review',last_error=?,lease_token=NULL,lease_until=NULL,updated_at=? WHERE raw_sms_id IN (SELECT raw_sms_id FROM momo_processing_jobs WHERE ${AMBIGUOUS} ORDER BY raw_sms_id LIMIT 100) AND ${AMBIGUOUS}`,
    MOMO_JOB_CHECKPOINT.unknown,
    now(),
  ).run();
  await q(
    env,
    `UPDATE momo_processing_jobs SET state='needs_review',last_error=?,lease_token=NULL,lease_until=NULL,updated_at=? WHERE raw_sms_id IN (SELECT raw_sms_id FROM momo_processing_jobs WHERE ${CLAIMABLE} AND attempt_count>=max_attempts ORDER BY raw_sms_id LIMIT 100) AND ${CLAIMABLE} AND attempt_count>=max_attempts`,
    MOMO_JOB_CHECKPOINT.budget,
    now(),
  ).run();
  return rows(
    env,
    `SELECT raw_sms_id FROM momo_processing_jobs WHERE attempt_count<max_attempts AND ${CLAIMABLE} ORDER BY available_at,raw_sms_id LIMIT ?`,
    count,
  );
}

export function prepareMomoSourceReviewWrites(
  env,
  job,
  account,
  rawId,
  bodySha,
  { expectedState, expectedAttemptCount, review },
) {
  const lease = id(),
    guard = id(),
    stamp = now(),
    guardSql =
      `raw_sms_id=? AND state=? AND attempt_count=? AND last_error IS ? AND receiving_account_id=?
  AND EXISTS(SELECT 1 FROM sms_receipts s WHERE s.id=momo_processing_jobs.raw_sms_id AND s.body_sha256=?)
  AND NOT EXISTS(SELECT 1 FROM momo_transaction_sources s WHERE s.raw_sms_id=momo_processing_jobs.raw_sms_id AND
   (s.relation IN('accepted','duplicate') OR EXISTS(SELECT 1 FROM momo_financial_links f WHERE f.transaction_id=s.transaction_id)))`;
  const reviewed = {
    ...job,
    attempt_count: job.attempt_count + 1,
    lease_token: lease,
    body_sha256: bodySha,
  };
  const { writes, attemptId } = finishStatements(
    env,
    reviewed,
    account,
    review,
  );
  const reviewWrites = [
    q(
      env,
      `UPDATE momo_processing_jobs SET state='processing',lease_token=?,lease_until=${LEASE_CLOCK}+?,attempt_count=attempt_count+1,max_attempts=max(max_attempts,attempt_count+1),updated_at=? WHERE ${guardSql}`,
      lease,
      LEASE_SECONDS,
      stamp,
      rawId,
      expectedState,
      expectedAttemptCount,
      job.last_error ?? null,
      job.receiving_account_id,
      bodySha,
    ),
    q(
      env,
      `INSERT INTO momo_processing_guards(id,passed) SELECT ?,CASE WHEN changes()=1 THEN 1 ELSE 0 END`,
      guard,
    ),
    ...writes,
    q(env, 'DELETE FROM momo_processing_guards WHERE id=?', guard),
  ];
  return { writes: reviewWrites, attemptId };
}
