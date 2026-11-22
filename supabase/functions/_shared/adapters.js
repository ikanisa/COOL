import {applicationWork, guardedFetch, noteUnknownEffect} from './application-fence.js';
import {ApiError} from './domain/core.js';
import {emailAdapters} from './email-adapter.js';
import {createFcmSender} from './fcm-notifications.js';
import {createMomoModel} from './momo-model.js';
import {createRosterDecoderBridge} from './roster_decoder_bridge.mjs';
import {createNativeRosterJpegDecoder, NATIVE_JPEG_PROTOCOL} from './roster_native_jpeg_decoder.mjs';

export {SupabaseObjectBucket} from './storage/bucket.js';

function pushAdapter(env) {
  try {
    return createFcmSender(env, {
      fetchImpl: (url, options) => guardedFetch(env, url === 'https://oauth2.googleapis.com/token' ? 'push_oauth' : 'push', url, options),
      track: promise => applicationWork(env).waitUntil(promise),
      onUncertain: label => noteUnknownEffect(env, label),
    });
  } catch {
    return Object.freeze({available: false});
  }
}

function rosterAdapter(env) {
  const protocol = env.ROSTER_DECODER_PROTOCOL;
  const secret = env.ROSTER_DECODER_SECRET;
  const approvedBuildSha256 = env.ROSTER_DECODER_BUILD_SHA256;
  try {
    if (protocol === NATIVE_JPEG_PROTOCOL) {
      return createNativeRosterJpegDecoder({protocol, identity: env.ROSTER_DECODER_URL, secret, approvedBuildSha256});
    }
    return createRosterDecoderBridge({
      protocol, endpoint: env.ROSTER_DECODER_URL, secret, approvedBuildSha256,
      fetchImpl: (input, options) => guardedFetch(env, 'decoder', input, options),
      trackPromise: promise => applicationWork(env).waitUntil(promise),
      onUncertain: () => noteUnknownEffect(env, 'decoder'),
    });
  } catch {
    return Object.freeze({async fetch() {
      throw new ApiError(503, 'decoder_unavailable', 'The configured service is unavailable.');
    }});
  }
}

export function providerAdapters(env) {
  return {
    ...(env.FCM_SERVICE_ACCOUNT_JSON ? {FCM: pushAdapter(env)} : {}),
    ...(env.OPENAI_API_KEY && env.MOMO_AI_MODEL ? {AI: createMomoModel(env)} : {}),
    ROSTER_DECODER: rosterAdapter(env),
    ...emailAdapters(env),
  };
}
