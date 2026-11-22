import {AdminRequestError, type JsonObject} from './contracts';
import {boundedResponseBody} from './responses';

interface RequestLimits {
  signal?: AbortSignal;
  mutation: boolean;
  readUnauthorizedBody: boolean;
  timeoutMs: number;
  maxResponseBytes: number;
}

/** Return the HTTP status even when the response body cannot be read. */
export async function fetchAdminResponse(fetchImpl: typeof fetch, target: string, {method, headers, body}: {method: string; headers: HeadersInit; body?: JsonObject}, limits: RequestLimits) {
  const controller = new AbortController();
  const abort = () => controller.abort();
  const timeout = setTimeout(abort, limits.timeoutMs);
  limits.signal?.addEventListener('abort', abort, {once: true});
  if (limits.signal?.aborted) abort();

  try {
    let response: Response;
    try {
      response = await fetchImpl(target, {
        method, headers, body: body === undefined ? undefined : JSON.stringify(body),
        credentials: 'same-origin', redirect: 'error', cache: 'no-store', signal: controller.signal,
      });
    } catch {
      const message = limits.mutation
        ? 'The result is unknown. Check the original request before continuing.'
        : 'The workspace could not be reached. Check your session before trying again.';
      throw new AdminRequestError(message, {outcomeUnknown: true});
    }

    let raw: string | undefined;
    if (response.status === 401 && !limits.readUnauthorizedBody) abort();
    else {
      try { raw = await boundedResponseBody(response, limits.maxResponseBytes); }
      catch { abort(); }
    }
    return {response, raw};
  } finally {
    clearTimeout(timeout);
    limits.signal?.removeEventListener('abort', abort);
  }
}
