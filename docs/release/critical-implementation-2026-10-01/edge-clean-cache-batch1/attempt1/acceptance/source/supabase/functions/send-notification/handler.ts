import {
  boundedText,
  objectValue,
  PublicError,
  publicFailure,
  UUID,
  uuid,
} from "../_shared/production_contract.ts";
import { corsHeaders, jsonResponse } from "../_shared/cors.ts";

export const notificationRequestTimeoutMs = 8000;
export type EnqueueResult = { data: unknown; error: unknown };
export type NotificationDependencies = {
  authorize: (request: Request) => void;
  enqueue: (
    name: string,
    parameters: Record<string, unknown>,
    signal: AbortSignal,
  ) => PromiseLike<EnqueueResult>;
  dispatch: (signal: AbortSignal) => Promise<boolean>;
  timeoutMs?: number;
};

async function notificationPayload(
  request: Request,
  signal: AbortSignal,
): Promise<Record<string, unknown>> {
  if (
    !/^application\/json(?:\s*;|$)/i.test(
      request.headers.get("content-type") ?? "",
    )
  ) throw new PublicError("json_required", 415);
  const size = request.headers.get("content-length");
  if (size !== null && (!/^\d+$/.test(size) || Number(size) > 16384)) {
    throw new PublicError("payload_too_large", 413);
  }
  const reader = request.body?.getReader();
  if (!reader) throw new PublicError("invalid_json");
  const cancel = () => {
    void reader.cancel().catch(() => {});
  };
  signal.addEventListener("abort", cancel, { once: true });
  const chunks: Uint8Array[] = [];
  let length = 0;
  try {
    while (true) {
      signal.throwIfAborted();
      const next = await reader.read();
      signal.throwIfAborted();
      if (next.done) break;
      length += next.value.byteLength;
      if (length > 16384) {
        cancel();
        throw new PublicError("payload_too_large", 413);
      }
      chunks.push(next.value);
    }
    const bytes = new Uint8Array(length);
    let offset = 0;
    for (const chunk of chunks) {
      bytes.set(chunk, offset);
      offset += chunk.length;
    }
    try {
      return objectValue(
        JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes)),
      );
    } catch {
      throw new PublicError("invalid_json");
    }
  } finally {
    signal.removeEventListener("abort", cancel);
    reader.releaseLock();
  }
}

// Fetch/PostgREST receive the same signal; this also bounds a stalled body or
// dependency that resolves late. Never replay an enqueue with an uncertain ACK.
export async function boundedOperation<T>(
  operation: (signal: AbortSignal) => PromiseLike<T>,
  parent: AbortSignal,
  milliseconds: number,
): Promise<T> {
  const signal = AbortSignal.any([parent, AbortSignal.timeout(milliseconds)]);
  signal.throwIfAborted();
  let onAbort: (() => void) | undefined;
  try {
    return await Promise.race([
      Promise.resolve(operation(signal)),
      new Promise<never>((_resolve, reject) => {
        onAbort = () => reject(signal.reason);
        signal.addEventListener("abort", onAbort, { once: true });
        if (signal.aborted) onAbort();
      }),
    ]);
  } finally {
    if (onAbort) signal.removeEventListener("abort", onAbort);
  }
}

export async function requestDispatch(
  url: string,
  apikey: string,
  secret: string,
  signal: AbortSignal,
  fetcher: typeof fetch = fetch,
): Promise<boolean> {
  try {
    const endpoint = new URL("/functions/v1/dispatch-notifications", url);
    // Environment config supplies the origin. Never forward secrets to a
    // redirect, credentials-bearing URL or insecure hosted endpoint.
    if (
      endpoint.protocol !== "https:" || new URL(url).username ||
      new URL(url).password || !apikey || !secret
    ) return false;
    const response = await fetcher(endpoint, {
      method: "POST",
      signal,
      redirect: "error",
      headers: {
        apikey,
        "Content-Type": "application/json",
        "x-collect-signature": secret,
      },
      body: JSON.stringify({ limit: 100 }),
    });
    // The worker can take up to a minute. Wake-up is best-effort; cron handles
    // durable pending work, including a response lost after provider acceptance.
    void response.body?.cancel().catch(() => {});
    return response.ok && !response.redirected && response.status < 300;
  } catch {
    return false;
  }
}

export function createNotificationHandler(
  dependencies: NotificationDependencies,
) {
  return async (request: Request): Promise<Response> => {
    if (request.method === "OPTIONS") {
      return new Response("ok", { headers: corsHeaders });
    }
    if (request.method !== "POST") {
      return jsonResponse({ error: "Method not allowed" }, 405);
    }
    const timeout = dependencies.timeoutMs ?? notificationRequestTimeoutMs;
    try {
      dependencies.authorize(request);
      const payload = await boundedOperation(
        (signal) => notificationPayload(request, signal),
        request.signal,
        timeout,
      );
      const userId = uuid(payload.user_id, "invalid_notification_user");
      const template = payload.template_key == null ? null : boundedText(
        payload.template_key,
        "invalid_notification_template",
        100,
      );
      const name = template
        ? "enqueue_notification_template_event"
        : "enqueue_notification_event";
      const shared = {
        p_user_id: userId,
        p_collection_id: payload.collection_id ?? null,
        p_deep_link: payload.deep_link ?? null,
      };
      const parameters = template
        ? {
          ...shared,
          p_template_key: template,
          p_context: objectValue(payload.context ?? {}),
          p_locale: payload.locale == null
            ? "en"
            : boundedText(payload.locale, "invalid_notification_locale", 16),
        }
        : {
          ...shared,
          p_type: boundedText(payload.type, "invalid_notification_type", 100),
          p_title: boundedText(
            payload.title,
            "invalid_notification_title",
            500,
          ),
          p_body: boundedText(payload.body, "invalid_notification_body", 8000),
        };
      const { data, error } = await boundedOperation(
        (signal) => dependencies.enqueue(name, parameters, signal),
        request.signal,
        timeout,
      );
      if (error) throw error;
      if (data !== null && (typeof data !== "string" || !UUID.test(data))) {
        throw new Error("notification_enqueue_ack_unavailable");
      }
      let dispatchRequested = false;
      if (data !== null) {
        try {
          dispatchRequested = await boundedOperation(
            (signal) => dependencies.dispatch(signal),
            request.signal,
            timeout,
          );
        } catch {
          /* The durable event remains enqueued. A wake-up never re-enqueues it. */
        }
      }
      return jsonResponse({
        ok: data !== null,
        skipped: data === null,
        notification_event_id: data,
        dispatch_requested: dispatchRequested,
      });
    } catch (error) {
      void request.body?.cancel().catch(() => {});
      const failure = publicFailure(error);
      return jsonResponse({ error: failure.error }, failure.status);
    }
  };
}
