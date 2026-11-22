import {applicationWork, guardedFetch, noteUnknownEffect} from './application-fence.js';
import {ApiError} from './domain/core.js';

const MODEL_ENDPOINT = 'https://api.openai.com/v1/chat/completions';
const defaultTimeoutMs = 45_000;
const maximumContentLength = 65_536;
// Leave room for JSON escaping and model metadata within the fixed envelope.
const maximumResponseBytes = 512 * 1024;
const unavailable = kind => new ApiError(503, `${kind}_unavailable`, 'The configured service is unavailable.');

function boundedMomoResponse(env, response) {
  const work = applicationWork(env);
  return work.local(async () => {
    let reader;
    let complete = false;
    try {
      const declared = response.headers.get('content-length');
      if (declared !== null && (!/^\d+$/.test(declared) || Number(declared) > maximumResponseBytes)) {
        throw unavailable('ai_response');
      }
      const chunks = [];
      let size = 0;
      if (response.body) {
        reader = response.body.getReader();
        while (true) {
          const {done, value} = await reader.read();
          if (done) {
            complete = true;
            break;
          }
          if (!(value instanceof Uint8Array) || value.byteLength > maximumResponseBytes - size) {
            throw unavailable('ai_response');
          }
          size += value.byteLength;
          if (value.byteLength) chunks.push(value);
        }
      }
      const bytes = new Uint8Array(size);
      let offset = 0;
      for (const chunk of chunks) {
        bytes.set(chunk, offset);
        offset += chunk.byteLength;
      }
      return JSON.parse(new TextDecoder('utf-8', {fatal: true}).decode(bytes));
    } catch {
      noteUnknownEffect(env, 'ai');
      throw unavailable('ai_response');
    } finally {
      // The original cancellation remains owned by the admission after refusal.
      if (!complete && response.body) {
        try {
          const raw = reader ? reader.cancel() : response.body.cancel();
          work.waitUntil(Promise.resolve(raw).catch(() => noteUnknownEffect(env, 'ai')));
        } catch {
          noteUnknownEffect(env, 'ai');
        }
      }
      try {
        reader?.releaseLock();
      } catch {
        noteUnknownEffect(env, 'ai');
        throw unavailable('ai_response');
      }
    }
  });
}

export function createMomoModel(env) {
  return {async run(_legacy, options) {
    if (env.MOMO_AI_ENABLED !== 'true') throw unavailable('ai');
    const timeout = options.provider_timeout_ms ?? defaultTimeoutMs;
    if (!Number.isSafeInteger(timeout) || (timeout !== defaultTimeoutMs && (timeout < 1000 || timeout > 8000))) {
      throw unavailable('ai');
    }
    const reply = await guardedFetch(env, 'ai', MODEL_ENDPOINT, {
      method: 'POST',
      redirect: 'error',
      signal: AbortSignal.timeout(timeout),
      headers: {'Content-Type': 'application/json', Authorization: `Bearer ${env.OPENAI_API_KEY}`},
      body: JSON.stringify({
        model: env.MOMO_AI_MODEL, messages: options.messages, temperature: 0,
        max_completion_tokens: options.max_tokens, store: false,
        response_format: {
          type: 'json_schema',
          json_schema: {name: 'collect_momo_extraction', strict: true, schema: options.response_format.json_schema},
        },
      }),
    });
    if (!reply.ok) throw unavailable('ai');
    const result = await boundedMomoResponse(env, reply);
    const content = result.choices?.[0]?.message?.content;
    if (typeof content !== 'string' || content.length > maximumContentLength) throw unavailable('ai_response');
    return {response: content};
  }};
}
