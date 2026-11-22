/** Same-origin request orchestration for the Cloudflare Admin frontend. */
import {boundedBytes, fetchWithinDeadline} from './transport-body.js';
import {failure, ProxyFailure, refuse} from './transport-failure.js';
import {admitRequest, FRONTENDS, transportOrigin, upstreamRequest} from './transport-request.js';
import {qualifyResponse} from './transport-response.js';

export {routeCollectTarget, SUPABASE_ORIGIN} from './transport-request.js';

export function createCollectTransport({frontendOrigin, isolateAdminSession = false,
  allowedFrontendOrigins = [...FRONTENDS], fetchImpl = (request, init) => globalThis.fetch(request, init),
  timeoutMs = 30000, maxRequestBytes = 16 * 1024 * 1024, maxResponseBytes = 16 * 1024 * 1024} = {}) {
  const allowedFrontends = new Set(allowedFrontendOrigins.map(origin => transportOrigin(origin)));
  if (!allowedFrontends.has(transportOrigin(frontendOrigin)) || typeof fetchImpl !== 'function' ||
      !Number.isSafeInteger(timeoutMs) || timeoutMs < 1 || timeoutMs > 60000 ||
      !Number.isSafeInteger(maxRequestBytes) || maxRequestBytes < 1 ||
      !Number.isSafeInteger(maxResponseBytes) || maxResponseBytes < 1) throw new TypeError('Invalid static-host proxy configuration');
  // null selects the existing static host. rawTarget is only for hosts that expose the original path.
  return async function handle(request, {rawTarget} = {}) {
    let attempted = false;
    let effectful = false;
    let timer;
    let abortListener;
    const controller = new AbortController();
    try {
      const admission = admitRequest(request, rawTarget, frontendOrigin, isolateAdminSession);
      if (!admission) return null;
      effectful = admission.effectful;

      const declared = request.headers.get('content-length');
      if (declared !== null && (!/^[0-9]+$/.test(declared) || Number(declared) > maxRequestBytes)) {
        refuse(413, 'proxy_request_too_large');
      }
      abortListener = () => controller.abort();
      request.signal.addEventListener('abort', abortListener, {once: true});
      if (request.signal.aborted) controller.abort();
      timer = setTimeout(abortListener, timeoutMs);
      const signal = controller.signal;
      const bytes = await boundedBytes(request.body, maxRequestBytes, signal, 413, 'proxy_request_too_large');
      const outgoing = upstreamRequest(request, admission, bytes, signal, frontendOrigin, isolateAdminSession);
      if (signal.aborted) refuse(504, 'proxy_deadline');
      attempted = true;
      const upstream = await fetchWithinDeadline(outgoing, signal, fetchImpl);
      return await qualifyResponse(upstream, {
        route: admission.route, method: request.method, signal, maxResponseBytes, isolateAdminSession,
        frontendOrigin, allowedFrontends,
      });
    } catch (error) {
      if (!(error instanceof ProxyFailure)) {
        const classification = error instanceof Error && /illegal invocation/i.test(error.message)
          ? 'illegal_invocation' : controller.signal.aborted ? 'aborted' : error instanceof TypeError ? 'type_error' : 'unknown';
        console.error(JSON.stringify({service:'collect_web_transport',event:'proxy_runtime_failure',attempted,classification}));
      }
      const unknown = attempted && effectful;
      if (error instanceof ProxyFailure) {
        controller.abort();
        return failure(error.status, unknown ? 'proxy_outcome_unknown' : error.code, unknown ? error.code : undefined);
      }
      return failure(controller.signal.aborted ? 504 : 502,
        unknown ? 'proxy_outcome_unknown' : 'proxy_unavailable',
        unknown ? controller.signal.aborted ? 'proxy_deadline' : 'proxy_upstream_failure' : undefined);
    } finally {
      clearTimeout(timer);
      if (abortListener) request.signal.removeEventListener('abort', abortListener);
    }
  };
}
