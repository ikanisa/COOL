import {publishMemberRealtime} from './member-realtime-publisher.js';
import {scheduledProcessingAdmission, scheduledProcessingResult, scheduledNotificationResult} from './scheduled-processing.js';
import {withNativeProviderBudget} from './native-provider-budget.mjs';
import {nativeAutoProcessingResult} from './scheduled-native-auto.js';
import {nativeSmsLedgerResult} from './scheduled-native-sms-ledger.js';
import {scheduledPaymentSmsResult} from './domain/burimunsi/payment-sms-delivery.mjs';
import {scheduledCanonicalDrain} from './scheduled-canonical.js';

async function maintainAuth(env, cleanup) {
  try {
    return await cleanup(env, {limit: 100});
  } catch {
    return {status: 'unconfirmed', code: 'auth_cleanup_unconfirmed'};
  }
}

async function runReceipts(env, admission, processReceipts) {
  if (!admission.allowed) {
    return {
      status: 'unconfirmed', code: admission.code, processed: 0, results: [],
      paused: env.MOMO_PROCESSING_PAUSED === 'true',
    };
  }
  try {
    const options = admission.processing ? {limit: admission.processing.batch_limit} : undefined;
    const result = await processReceipts(env, options);
    return admission.processing ? scheduledProcessingResult(result) : result;
  } catch {
    return {status: 'unconfirmed', code: 'receipt_processing_unconfirmed'};
  }
}

async function runNotifications(env, admission, processNotifications) {
  if (!admission.allowed || !admission.notifications) {
    return {status: 'disabled', paused: true, processed: 0, results: [], recovered_unknown: 0};
  }
  try {
    return scheduledNotificationResult(await processNotifications(env, {
      limit: admission.notifications.batch_limit, admission: admission.notifications,
    }));
  } catch {
    return {status: 'unconfirmed', code: 'notification_delivery_unconfirmed', processed: 0, results: []};
  }
}

async function runNativeAuto(env, nativeEnv, admission, processNativeAuto, processNativeSmsLedger) {
  if (env.BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED !== 'true') {
    return {nativeAuto: null, nativeLedger: null};
  }
  if (!admission.allowed) {
    return {
      nativeAuto: {status: 'unconfirmed', code: 'native_auto_admission_unavailable'},
      nativeLedger: {status: 'unconfirmed', code: 'native_sms_ledger_admission_unavailable'},
    };
  }

  let nativeAuto;
  try {
    nativeAuto = nativeAutoProcessingResult(await processNativeAuto(nativeEnv, {limit: 1}));
  } catch {
    nativeAuto = {status: 'unconfirmed', code: 'native_auto_processing_unconfirmed'};
  }

  // The same native SMS cycle posts matched receipts into the Collect ledger.
  if (env.BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED !== 'true') return {nativeAuto, nativeLedger: null};
  let nativeLedger;
  try {
    nativeLedger = nativeSmsLedgerResult(await processNativeSmsLedger(nativeEnv, {limit: 1}));
  } catch {
    nativeLedger = {status: 'unconfirmed', code: 'native_sms_ledger_unconfirmed'};
  }
  return {nativeAuto, nativeLedger};
}

async function runPaymentSms(env, enabled, admitted, processPaymentSms) {
  if (!enabled) return null;
  if (!admitted) return {status: 'held', processed: 0};
  try {
    return scheduledPaymentSmsResult(await processPaymentSms(env));
  } catch {
    return {status: 'unconfirmed', processed: 0};
  }
}

async function maintainDiagnostics(env, cleanupDiagnostics) {
  const limit = 1000;
  try {
    const result = await cleanupDiagnostics(env, {limit});
    if (result?.status !== 'complete' || !Number.isSafeInteger(result.removed) ||
        result.removed < 0 || result.removed > limit) {
      throw new Error('diagnostics_cleanup_unconfirmed');
    }
    return result;
  } catch {
    try {
      console.error(JSON.stringify({service: 'collect_platform_api', event: 'diagnostics_cleanup_unconfirmed'}));
    } catch {
      // Diagnostics cannot change the outcome of completed business work.
    }
    return {status: 'unconfirmed'};
  }
}

export async function runEdgeJobCycle(env, payload, dispatch, nativeGate, {
  cleanup, processReceipts, processNotifications, processNativeAuto, processNativeSmsLedger,
  processPaymentSms, processCanonical, processNativeFinancialWork, cleanupDiagnostics,
}) {
  // Credential cleanup and Realtime hints keep their original budgets and run
  // even while receipt processing is paused.
  const maintenance = await maintainAuth(env, cleanup);
  const realtime = await publishMemberRealtime(env);
  const admission = scheduledProcessingAdmission(env, dispatch);
  const processing = await runReceipts(env, admission, processReceipts);
  const notifications = await runNotifications(env, admission, processNotifications);

  // The native provider budget and managed processing admission are independent.
  const nativeEnv = nativeGate.enabled ? withNativeProviderBudget(env, payload) : env;
  const {nativeAuto, nativeLedger} = await runNativeAuto(env, nativeEnv, admission, processNativeAuto, processNativeSmsLedger);
  const paymentSmsEnabled = env.BURIMUNSI_PAYMENT_SMS_ENABLED === 'true';
  const paymentSmsAdmitted = paymentSmsEnabled && nativeGate.enabled && admission.allowed;
  const paymentSms = await runPaymentSms(env, paymentSmsEnabled, paymentSmsAdmitted, processPaymentSms);

  const canonical = await scheduledCanonicalDrain(env, admission, {runCycle: processCanonical});
  const nativeFinancial = await processNativeFinancialWork(env, admission);
  const diagnostics = await maintainDiagnostics(env, cleanupDiagnostics);

  const complete = maintenance.status === 'complete' &&
    processing.status !== 'unconfirmed' && notifications.status !== 'unconfirmed' &&
    [nativeAuto, nativeLedger, canonical, nativeFinancial].every(result => result?.status !== 'unconfirmed') &&
    (!paymentSmsAdmitted || paymentSms?.status === 'complete');
  const {dispatchId} = dispatch;
  // The dispatch stores a digest of these response bytes. Preserve field order.
  return {
    status: complete ? 200 : 503,
    body: {
      ...(dispatchId ? {dispatch_id: dispatchId} : {}),
      ...(nativeGate.enabled ? {native_sms_admission: nativeGate.admission} : {}),
      ...(admission.processing ? {processing_admission: admission.processing} : {}),
      ...(admission.notifications ? {notification_admission: admission.notifications} : {}),
      maintenance, processing, notifications,
      ...(nativeAuto ? {native_auto_processing: nativeAuto} : {}),
      ...(nativeLedger ? {native_sms_ledger: nativeLedger} : {}),
      ...(paymentSms ? {payment_receipt_sms: paymentSms} : {}),
      ...(canonical ? {canonical_processing: canonical} : {}),
      ...(nativeFinancial ? {native_financial_work: nativeFinancial} : {}),
      realtime, diagnostics,
    },
  };
}
