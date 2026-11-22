import {verifyDeploymentProfile} from './deployment-profile.js';
import {normalizeRuntimeEnv} from './runtime-env.js';
import {openApplicationWork} from './application-fence.js';
import {cleanupExpiredGoogleFlows} from './auth-cleanup.js';
import {parseScheduledDispatch} from './scheduled-processing.js';
import {
  claimManagedJobDispatch, completeManagedJobDispatch, nativeSmsAdmission, verifyManagedJobSignature,
} from './managed-jobs-dispatch-auth.mjs';
import {scheduledNativeFinancialWork} from './scheduled-native-financial-work.js';
import {EdgeRuntimeWork, isFenceFailure, observeFailure} from './edge-runtime.js';
import {runEdgeJobCycle} from './edge-job-cycle.js';
import {json, readJson} from './domain/core.js';
import {recordPlatformHealth} from './domain/observability.js';
import {cleanupClientDiagnostics} from './domain/client_diagnostics.js';
import {drainMomoJobs} from './domain/momo_pipeline.js';
import {drainNotificationDeliveries} from './domain/notification_delivery.js';
import {runCollectNativeScheduledCycle} from './domain/burimunsi/collect-runtime.js';
import {drainNativeAutoTransactions} from './domain/burimunsi/postgres-native-auto-worker.js';
import {drainNativeSmsLedger} from './domain/burimunsi/postgres-native-sms-ledger.js';
import {drainBuriMunsiPaymentSms} from './domain/burimunsi/payment-sms-delivery.mjs';

const cloudJobDispatch = Object.freeze({
  verify: verifyManagedJobSignature,
  claim: claimManagedJobDispatch,
  complete: completeManagedJobDispatch,
  admitNativeSms: nativeSmsAdmission,
});

const unauthenticated = () => json({code: 'unauthorized'}, 401);

/** @param {()=>Record<string, unknown>} [envReader] */
export function createScheduledHandler(
  envReader = () => Deno.env.toObject(), cleanup = cleanupExpiredGoogleFlows, processReceipts = drainMomoJobs, {
    openWork = openApplicationWork,
    reportHealth = recordPlatformHealth,
    cleanupDiagnostics = cleanupClientDiagnostics,
    processNotifications = drainNotificationDeliveries,
    processNativeAuto = drainNativeAutoTransactions,
    processNativeSmsLedger = drainNativeSmsLedger,
    processPaymentSms = drainBuriMunsiPaymentSms,
    processCanonical = runCollectNativeScheduledCycle,
    processNativeFinancialWork = scheduledNativeFinancialWork,
    jobDispatch = cloudJobDispatch,
  } = {},
) {
  const workers = {
    cleanup, processReceipts, processNotifications, processNativeAuto, processNativeSmsLedger,
    processPaymentSms, processCanonical, processNativeFinancialWork, cleanupDiagnostics,
  };
  return async request => {
    const started = performance.now();
    const runtime = new EdgeRuntimeWork();
    let env;
    let dispatch = {dispatchId: null, processing: null, notifications: null};
    try {
      const input = envReader();
      env = input;
      const token = request.headers.get('Authorization');
      if (input.COLLECT_JOB_AUTH_MODE !== 'supabase_dispatch_hmac_v1' || !token) return unauthenticated();
      if (request.method !== 'POST') return json({code: 'method_not_allowed'}, 405);
      if (!/^\/(?:functions\/v1\/)?collect-jobs\/?$/.test(new URL(request.url).pathname)) {
        return json({code: 'not_found'}, 404);
      }

      let payload = null;
      if (request.body !== null) {
        try {
          payload = await readJson(request, 2048);
          dispatch = parseScheduledDispatch(payload);
        } catch (error) {
          return json({code: 'invalid_job_dispatch'}, [400, 413, 415].includes(error.status) ? error.status : 400);
        }
      }
      if (!await jobDispatch.verify(input, payload, token)) return unauthenticated();

      runtime.stage = 'normalization';
      await verifyDeploymentProfile(input);
      env = normalizeRuntimeEnv(input);
      env.MOMO_PROCESSING_PAUSED ??= 'true';
      await runtime.initializeDatabase(env);
      await runtime.admit(env, openWork, 'jobs');
      if (!await jobDispatch.claim(env.DB, input, payload, token)) return unauthenticated();

      runtime.initializeAdapters(env);
      const nativeGate = jobDispatch.admitNativeSms(env, payload);
      if (!nativeGate.allowed) return json({code: 'native_sms_admission_changed'}, 503);

      runtime.stage = 'dispatch';
      const {status, body} = await runEdgeJobCycle(env, payload, dispatch, nativeGate, workers);
      const {dispatchId} = dispatch;
      if (status === 503) {
        observeFailure(reportHealth, {
          status, component: 'operations', requestId: null, dispatchId,
          sourceId: env.BUILD_SOURCE_ID, elapsedMs: performance.now() - started,
        });
      }
      const response = json(body, status);
      if (status === 200 && !await jobDispatch.complete(env.DB, input, dispatchId, response)) {
        return json({code: 'job_completion_unconfirmed'}, 503);
      }
      return response;
    } catch (error) {
      const fenced = isFenceFailure(error);
      observeFailure(reportHealth, {
        status: 503, component: 'operations', requestId: null, dispatchId: dispatch.dispatchId,
        sourceId: env?.BUILD_SOURCE_ID, elapsedMs: performance.now() - started,
        ...(fenced ? {} : {runtimeFailure: {error, stage: runtime.stage, env}}),
      });
      if (fenced) return json({code: error.code, message: error.message}, 503);
      return json({code: 'backend_unavailable', message: 'The backend is unavailable.'}, 503);
    } finally {
      runtime.finish();
    }
  };
}

export const scheduledHandler = createScheduledHandler();
