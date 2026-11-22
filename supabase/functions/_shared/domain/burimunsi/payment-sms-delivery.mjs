import { applicationWork } from '../../application-fence.js';
import { MANAGED_SUPABASE_ORIGIN } from '../../deployment-profile.js';
import { createOpenSmsReceiptTransport, openSmsReceiptConfiguration } from '../../opensms-receipts.js';
import { digest } from '../core.js';
import { renderPaymentSms } from './payment-sms-template.mjs';

const uuid = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/;
const states = new Set(['accepted', 'assigned', 'phone_accepted', 'queued', 'handoff_started',
  'sent', 'delivered', 'delivery_unconfirmed', 'partial', 'failed', 'outcome_unknown', 'cancelled', 'expired']);
const sha256 = /^[a-f0-9]{64}$/;
const keys = {
  claim: 'SELECT private.burimunsi_claim_payment_sms($1::text,$2::timestamptz,$3::text,$4::integer) AS result',
  prepare: 'SELECT private.burimunsi_prepare_payment_sms_v2($1::text,$2::uuid,$3::uuid,$4::text) AS result',
  finish: 'SELECT private.burimunsi_finish_payment_sms($1::text,$2::uuid,$3::uuid,$4::text,$5::text,$6::text) AS result',
};

function check(value) {
  if (!value) throw Error('burimunsi_payment_sms_unconfirmed');
}

function configured(env) {
  if (env.BURIMUNSI_PAYMENT_SMS_ENABLED !== 'true') return null;
  const config = openSmsReceiptConfiguration(env);
  const group = env.BURIMUNSI_PAYMENT_SMS_COLLECTION_ID;
  const enabledAt = env.BURIMUNSI_PAYMENT_SMS_ENABLED_AT;
  check(config?.origin === MANAGED_SUPABASE_ORIGIN + '/functions/v1/collect-sms' &&
    env.SUPABASE_URL === MANAGED_SUPABASE_ORIGIN && env.APP_ENVIRONMENT === 'production' &&
    env.COLLECT_SMS_ENABLED === 'true' && env.COLLECT_SMS_DISPATCH_PAUSED === 'false' &&
    env.COLLECT_SMS_CORE_SOURCE_SHA256 === env.BUILD_SOURCE_ID && uuid.test(group ?? '') &&
    typeof enabledAt === 'string' && Number.isFinite(Date.parse(enabledAt)) &&
    new Date(enabledAt).toISOString() === enabledAt);
  return { config, group, enabledAt };
}

async function command(db, work, sql, args) {
  check(db?.applicationWork === work && work.kind === 'jobs');
  await work.assert();
  return db.transaction(async tx => {
    await db.context(tx);
    const rows = await tx.unsafe(sql, args);
    check(rows.length === 1 && Object.hasOwn(rows[0], 'result'));
    await work.assert();
    return rows[0].result;
  });
}

async function runClaim(job, runtime, command, work, transport) {
  const { group, config } = runtime;
  check(job && ['send', 'inspect'].includes(job.phase) && job.collection_id === group &&
    job.application_id === config.applicationId && uuid.test(job.attempt_id ?? '') && uuid.test(job.claim_token ?? '') &&
    typeof job.message_id === 'string' && job.message_id === config.applicationId + ':' + job.idempotency_key &&
    typeof job.idempotency_key === 'string' && /^[A-Za-z0-9:._-]{1,128}$/.test(job.idempotency_key));
  const identity = [group, job.attempt_id, job.claim_token];
  const save = async (status, providerState = null, evidence = null) => {
    check(await command(keys.finish, [...identity, status, providerState, evidence]) === true);
    return { outcome: status, ...(providerState ? { gateway_state: providerState } : {}) };
  };
  const to = job.destination;
  let text, bodyHash;
  try {
    check(sha256.test(job.destination_sha256 ?? ''));
    if (job.phase === 'send') check(/^\+2507[2389][0-9]{7}$/.test(to ?? '') && await digest(to) === job.destination_sha256);
    text = renderPaymentSms({ amount: job.amount_rwf, memberBalance: job.member_balance_rwf,
      recordedAt: job.posted_at, reference: job.posted_reference });
    bodyHash = await digest(text);
    check(typeof job.not_after === 'string' && Number.isFinite(Date.parse(job.not_after)));
    if (job.phase === 'inspect') check(bodyHash === job.body_sha256);
  } catch {
    return save(job.phase === 'send' ? 'suppressed' : 'unknown');
  }
  const payload = { messageId: job.message_id, text, notAfter: job.not_after };
  if (job.phase === 'send') {
    // A durable, one-use transition rechecks contact, payment and preferences.
    // No external request follows a refusal or an uncertain database result.
    const prepared = await command(keys.prepare, [...identity, bodyHash]);
    check(['prepared', 'suppressed', 'held'].includes(prepared));
    if (prepared !== 'prepared') return { outcome: prepared };
  }
  let result;
  try {
    result = job.phase === 'send'
      ? await work.dispatch('sms_gateway', () => transport.submit({ ...payload, to }))
      : await work.dispatch('sms_gateway_read', () => transport.inspectRecorded({ ...payload, destinationSha256: job.destination_sha256 }));
  } catch {
    // Subsequent work only inspects the original message ID. A lost submit
    // response never gives another worker authority to POST the same receipt.
    return save('unknown');
  }
  if (result?.providerAccepted !== true || !states.has(result.state) || !sha256.test(result.evidenceSha256 ?? '')) {
    return save('unknown');
  }
  return save('accepted', result.state, result.evidenceSha256);
}

export async function drainBuriMunsiPaymentSms(env, { makeTransport = createOpenSmsReceiptTransport } = {}) {
  const runtime = configured(env);
  if (!runtime) return { status: 'disabled', processed: 0 };
  const db = env.DB, work = applicationWork(env);
  const query = (sql, args) => command(db, work, sql, args);
  const jobs = await query(keys.claim, [runtime.group, runtime.enabledAt, runtime.config.applicationId, 1]);
  check(Array.isArray(jobs) && jobs.length <= 1);
  if (jobs.length === 0) return { status: 'complete', processed: 0 };
  const result = await runClaim(jobs[0], runtime, query, work, makeTransport(runtime.config));
  const status = result.outcome === 'held' ? 'held' : result.outcome === 'unknown' ? 'unconfirmed' : 'complete';
  return { status, processed: 1, ...result };
}


export function scheduledPaymentSmsResult(result) {
  if (result?.status === 'complete' && result.processed === 0 && result.outcome === undefined)
    return {status: 'complete', processed: 0};
  if (result?.processed === 1) {
    if (result.status === 'complete' && result.outcome === 'accepted' && states.has(result.gateway_state))
      return {status: 'complete', processed: 1, outcome: 'accepted', gateway_state: result.gateway_state};
    if (result.status === 'complete' && result.outcome === 'suppressed')
      return {status: 'complete', processed: 1, outcome: 'suppressed'};
    if (result.status === 'unconfirmed' && result.outcome === 'unknown')
      return {status: 'unconfirmed', processed: 1, outcome: 'unknown'};
    if (result.status === 'held' && result.outcome === 'held')
      return {status: 'held', processed: 1, outcome: 'held'};
  }
  return {status: 'unconfirmed', processed: 0};
}
