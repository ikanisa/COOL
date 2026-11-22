import { ApiError, digest, first } from './core.js';
import { decrypt } from './encryption.js';
import {
  matchesProviderSender,
  momoExtractionRequest,
  validateMomoExtraction,
  validateProviderProfile,
} from './momo/extraction.js';
import {
  checkpointMomoDispatch,
  claimMomoJob,
  findMomoJobs,
  finishMomoJob,
  MOMO_JOB_CHECKPOINT,
  MOMO_MODEL,
  momoOutcomeUnresolved,
  prepareMomoSourceReviewWrites,
} from './momo/job_store.js';

export {
  exactMinor,
  MOMO_EXTRACTION_SCHEMA,
  MOMO_PARSER_VERSION,
  MOMO_PROMPT_VERSION,
  MOMO_SCHEMA_VERSION,
  momoExtractionRequest,
  validateMomoExtraction,
  validateProviderProfile,
} from './momo/extraction.js';
export {
  finishStatements,
  MOMO_JOB_CHECKPOINT,
  MOMO_MODEL,
  MOMO_UNCERTAIN_ERRORS,
  momoOutcomeUnresolved,
  processingInsert,
} from './momo/job_store.js';

const issue = (code) => ({ code });
const present = (body, value) =>
  typeof value === 'string' && value.length > 0 && body.includes(value);

async function readSource(env, raw) {
  const object = await env.PRIVATE_MEDIA?.get(raw.object_key);
  if (!object) throw new Error('source_storage_unavailable');
  if (
    !Number.isSafeInteger(object.size) || object.size < 1 ||
    object.size > 262144
  ) throw new Error('source_integrity_failed');
  const bytes = await decrypt(
    env,
    await object.text(),
    `sms:${raw.id}:${raw.object_sha256}`,
  );
  if (
    bytes.length !== raw.size_bytes || await digest(bytes) !== raw.object_sha256
  ) throw new Error('source_integrity_failed');
  const source = JSON.parse(
    new TextDecoder('utf-8', { fatal: true }).decode(bytes),
  );
  if (
    typeof source.raw_body !== 'string' || !source.raw_body.length ||
    source.raw_body.length > 16384 || typeof source.raw_sender !== 'string' ||
    !source.raw_sender.length ||
    await digest(source.raw_body) !== raw.body_sha256
  ) throw new Error('source_integrity_failed');
  return source;
}

/** Compose with the existing admin mutation receipt/authority batch. */
export async function prepareMomoSourceReview(
  env,
  actor,
  rawId,
  body,
  requestId,
  { nonPayment = false } = {},
) {
  const job = await first(
      env,
      'SELECT * FROM momo_processing_jobs WHERE raw_sms_id=?',
      rawId,
    ),
    raw = await first(env, 'SELECT * FROM sms_receipts WHERE id=?', rawId);
  if (!job || !raw || !job.receiving_account_id) {
    throw new ApiError(
      409,
      'source_unresolved',
      'Resolve the receiving source before reviewing extraction.',
    );
  }
  if (momoOutcomeUnresolved(job)) {
    throw new ApiError(
      409,
      'provider_outcome_unresolved',
      'The previous extraction outcome must be reconciled before this source can be changed.',
    );
  }
  if (
    !['needs_review', 'completed'].includes(body.expected_state) ||
    job.state !== body.expected_state ||
    job.attempt_count !== body.expected_attempt_count ||
    raw.body_sha256 !== body.expected_body_sha256
  ) {
    throw new ApiError(
      409,
      'source_changed',
      'Refresh the current source and attempt history before reviewing it.',
    );
  }
  const linked = await first(
    env,
    `SELECT 1 AS found FROM momo_transaction_sources s WHERE s.raw_sms_id=? AND
  (s.relation IN('accepted','duplicate') OR EXISTS(SELECT 1 FROM momo_financial_links f WHERE f.transaction_id=s.transaction_id))`,
    rawId,
  );
  if (linked) {
    throw new ApiError(
      409,
      'canonical_source_linked',
      'Canonical payment facts cannot be replaced through source review.',
    );
  }
  const account = await first(
      env,
      'SELECT * FROM momo_receiving_accounts WHERE id=?',
      job.receiving_account_id,
    ),
    profile = account && validateProviderProfile(account);
  if (!profile) {
    throw new ApiError(
      409,
      'provider_profile_unverified',
      'Review the active provider source profile before correcting extraction.',
    );
  }
  const source = await readSource(env, raw),
    validation = validateMomoExtraction(
      body.extraction,
      source,
      account,
      profile,
    );
  if (nonPayment) {
    if (
      !validation.nonPayment || validation.errors.some((error) =>
        error.code !== 'not_successful_incoming'
      ) || !present(source.raw_body, body.classification_evidence) ||
      !Object.values(body.extraction.evidence).some((value) =>
        value === body.classification_evidence
      )
    ) {
      throw new ApiError(
        400,
        'non_payment_unproven',
        'Use exact source evidence of a supported outgoing, failed or pending message.',
      );
    }
  } else if (!validation.accepted) {
    throw new ApiError(
      400,
      'extraction_unproven',
      'The corrected fields must pass the normal source and provider validation.',
    );
  }
  const result = prepareMomoSourceReviewWrites(
    env,
    job,
    account,
    rawId,
    raw.body_sha256,
    {
      expectedState: body.expected_state,
      expectedAttemptCount: body.expected_attempt_count,
      review: {
        output: body.extraction,
        validation: [{
          code: 'operator_reviewed',
          action: nonPayment ? 'classify_non_payment' : 'correct_extraction',
          actor_user_id: actor.userId,
          request_id: requestId,
          evidence_reference: body.evidence_reference,
          reason: body.reason,
        }],
        outcome: nonPayment ? 'non_payment' : 'accepted',
        state: 'completed',
        facts: nonPayment ? null : validation.facts,
        modelId: 'operator_review',
        promptVersion: 'operator-evidence.v1',
      },
    },
  );
  return {
    writes: result.writes,
    value: {
      raw_sms_id: rawId,
      parse_attempt_id: result.attemptId,
      status: 'review_recorded',
      financial_effects: 0,
    },
  };
}

export async function processMomoJob(env, rawId) {
  // The direct entrypoint obeys the same fail-closed pause as the queue drain.
  // This prevents a direct caller from claiming work while processing is paused;
  // it cannot recall or terminate a worker that already passed this boundary.
  if (env.MOMO_PROCESSING_PAUSED !== 'false') return { state: 'paused' };
  // Start with an authoritative read session when replicas are configured.
  env = {
    ...env,
    DB: env.DB.withSession ? env.DB.withSession('first-primary') : env.DB,
  };
  const { claimed, token } = await claimMomoJob(env, rawId);
  // A database guard can park the row while the claim is applied.
  if (claimed?.state !== 'processing' || claimed.lease_token !== token) {
    return { state: 'not_claimed' };
  }
  const raw = await first(env, 'SELECT * FROM sms_receipts WHERE id=?', rawId),
    job = { ...claimed, body_sha256: raw.body_sha256 };
  const account = await first(
      env,
      'SELECT * FROM momo_receiving_accounts WHERE id=?',
      job.receiving_account_id,
    ),
    profile = account && validateProviderProfile(account);
  if (!profile) {
    return finishMomoJob(env, job, account, {
      validation: [issue('provider_profile_unverified')],
      outcome: 'needs_review',
      state: 'needs_review',
    });
  }
  let source, output;
  try {
    source = await readSource(env, raw);
    // A post-binding inbox observation can be extracted for review, but the
    // canonical validator still rejects incomplete evidence and no facts are
    // passed to the transaction writer. Never label it PDU-complete.
    if (
      source.completeness && source.completeness !== 'complete' &&
      !(source.completeness === 'incomplete' &&
        source.source_mode === 'catch_up')
    ) {
      return finishMomoJob(env, job, account, {
        validation: [issue('incomplete_source')],
        outcome: 'needs_review',
        state: 'needs_review',
      });
    }
    if (!matchesProviderSender(profile, source.raw_sender)) {
      return finishMomoJob(env, job, account, {
        validation: [issue('provider_sender_unrecognised')],
        outcome: 'needs_review',
        state: 'needs_review',
      });
    }
    if (!env.AI?.run) throw new Error('ai_binding_unavailable');
  } catch (error) {
    const code = /integrity|JSON|Syntax/.test(String(error))
        ? 'invalid_source_or_output'
        : 'extraction_temporarily_unavailable',
      retry = job.attempt_count < job.max_attempts;
    return finishMomoJob(env, job, account, {
      output: null,
      validation: [issue(code)],
      outcome: retry ? 'retry' : 'needs_review',
      state: retry ? 'retry' : 'needs_review',
      retry,
      jobError: retry
        ? MOMO_JOB_CHECKPOINT.retry
        : MOMO_JOB_CHECKPOINT.preflightExhausted,
    });
  }
  if (!await checkpointMomoDispatch(env, rawId, token)) {
    return { state: 'superseded' };
  }
  let result;
  try {
    result = await env.AI.run(MOMO_MODEL, momoExtractionRequest(source));
  } catch {
    return finishMomoJob(env, job, account, {
      validation: [issue('provider_outcome_unknown')],
      outcome: 'needs_review',
      state: 'needs_review',
      jobError: MOMO_JOB_CHECKPOINT.unknown,
    });
  }
  try {
    output = result?.response;
    if (typeof output === 'string') output = JSON.parse(output);
  } catch {
    // The provider returned a complete response to the adapter, so a bounded
    // retry of malformed output is distinct from a lost/unknown response.
    const retry = job.attempt_count < job.max_attempts;
    return finishMomoJob(env, job, account, {
      validation: [issue('invalid_provider_response')],
      outcome: retry ? 'retry' : 'needs_review',
      state: retry ? 'retry' : 'needs_review',
      retry,
      jobError: retry
        ? MOMO_JOB_CHECKPOINT.retry
        : MOMO_JOB_CHECKPOINT.responseInvalid,
    });
  }
  const validation = validateMomoExtraction(output, source, account, profile);
  if (validation.accepted) {
    return finishMomoJob(env, job, account, {
      output,
      validation: [],
      outcome: 'accepted',
      state: 'completed',
      facts: validation.facts,
    });
  }
  const retry = !validation.nonPayment &&
    validation.errors.every((e) =>
      ['invalid_schema', 'model_reported_issues'].includes(e.code)
    ) && job.attempt_count <= job.max_attempts - 3;
  return finishMomoJob(env, job, account, {
    output: output ?? null,
    validation: validation.errors,
    outcome: validation.nonPayment
      ? 'non_payment'
      : retry
      ? 'retry'
      : 'needs_review',
    state: validation.nonPayment
      ? 'completed'
      : retry
      ? 'retry'
      : 'needs_review',
    retry,
    ...(retry ? { jobError: MOMO_JOB_CHECKPOINT.retry } : {}),
  });
}

/** Bounded database outbox recovery; no publication/database dual-write gap. */
export async function drainMomoJobs(env, { limit = 5 } = {}) {
  if (env.MOMO_PROCESSING_PAUSED !== 'false') {
    return { processed: 0, results: [], paused: true };
  }
  const count = Number.isSafeInteger(limit)
    ? Math.max(1, Math.min(limit, 20))
    : 5;
  const jobs = await findMomoJobs(env, count);
  // A thrown worker may have committed the dispatch checkpoint before losing
  // its acknowledgement. Lease expiry may lead to quarantine, not a retry.
  const results = [];
  for (const job of jobs) {
    try {
      results.push(await processMomoJob(env, job.raw_sms_id));
    } catch {
      results.push({ state: 'awaiting_lease_reconciliation' });
    }
  }
  return { processed: jobs.length, results };
}
