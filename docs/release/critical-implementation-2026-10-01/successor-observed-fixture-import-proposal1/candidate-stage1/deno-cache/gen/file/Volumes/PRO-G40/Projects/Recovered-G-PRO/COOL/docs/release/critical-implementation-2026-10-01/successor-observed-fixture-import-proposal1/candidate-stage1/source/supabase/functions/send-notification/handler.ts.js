import { boundedText, objectValue, PublicError, publicFailure, UUID, uuid } from "../_shared/production_contract.ts";
import { corsHeaders, jsonResponse } from "../_shared/cors.ts";
export const notificationRequestTimeoutMs = 8000;
async function notificationPayload(request, signal) {
  if (!/^application\/json(?:\s*;|$)/i.test(request.headers.get("content-type") ?? "")) throw new PublicError("json_required", 415);
  const size = request.headers.get("content-length");
  if (size !== null && (!/^\d+$/.test(size) || Number(size) > 16384)) {
    throw new PublicError("payload_too_large", 413);
  }
  const reader = request.body?.getReader();
  if (!reader) throw new PublicError("invalid_json");
  const cancel = ()=>{
    void reader.cancel().catch(()=>{});
  };
  signal.addEventListener("abort", cancel, {
    once: true
  });
  const chunks = [];
  let length = 0;
  try {
    while(true){
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
    for (const chunk of chunks){
      bytes.set(chunk, offset);
      offset += chunk.length;
    }
    try {
      return objectValue(JSON.parse(new TextDecoder("utf-8", {
        fatal: true
      }).decode(bytes)));
    } catch  {
      throw new PublicError("invalid_json");
    }
  } finally{
    signal.removeEventListener("abort", cancel);
    reader.releaseLock();
  }
}
// Fetch/PostgREST receive the same signal; this also bounds a stalled body or
// dependency that resolves late. Never replay an enqueue with an uncertain ACK.
export async function boundedOperation(operation, parent, milliseconds) {
  const signal = AbortSignal.any([
    parent,
    AbortSignal.timeout(milliseconds)
  ]);
  signal.throwIfAborted();
  let onAbort;
  try {
    return await Promise.race([
      Promise.resolve(operation(signal)),
      new Promise((_resolve, reject)=>{
        onAbort = ()=>reject(signal.reason);
        signal.addEventListener("abort", onAbort, {
          once: true
        });
        if (signal.aborted) onAbort();
      })
    ]);
  } finally{
    if (onAbort) signal.removeEventListener("abort", onAbort);
  }
}
export async function requestDispatch(url, apikey, secret, signal, fetcher = fetch) {
  try {
    const endpoint = new URL("/functions/v1/dispatch-notifications", url);
    // Environment config supplies the origin. Never forward secrets to a
    // redirect, credentials-bearing URL or insecure hosted endpoint.
    if (endpoint.protocol !== "https:" || new URL(url).username || new URL(url).password || !apikey || !secret) return false;
    const response = await fetcher(endpoint, {
      method: "POST",
      signal,
      redirect: "error",
      headers: {
        apikey,
        "Content-Type": "application/json",
        "x-collect-signature": secret
      },
      body: JSON.stringify({
        limit: 100
      })
    });
    // The worker can take up to a minute. Wake-up is best-effort; cron handles
    // durable pending work, including a response lost after provider acceptance.
    void response.body?.cancel().catch(()=>{});
    return response.ok && !response.redirected && response.status < 300;
  } catch  {
    return false;
  }
}
export function createNotificationHandler(dependencies) {
  return async (request)=>{
    if (request.method === "OPTIONS") {
      return new Response("ok", {
        headers: corsHeaders
      });
    }
    if (request.method !== "POST") {
      return jsonResponse({
        error: "Method not allowed"
      }, 405);
    }
    const timeout = dependencies.timeoutMs ?? notificationRequestTimeoutMs;
    try {
      dependencies.authorize(request);
      const payload = await boundedOperation((signal)=>notificationPayload(request, signal), request.signal, timeout);
      const userId = uuid(payload.user_id, "invalid_notification_user");
      const template = payload.template_key == null ? null : boundedText(payload.template_key, "invalid_notification_template", 100);
      const name = template ? "enqueue_notification_template_event" : "enqueue_notification_event";
      const shared = {
        p_user_id: userId,
        p_collection_id: payload.collection_id ?? null,
        p_deep_link: payload.deep_link ?? null
      };
      const parameters = template ? {
        ...shared,
        p_template_key: template,
        p_context: objectValue(payload.context ?? {}),
        p_locale: payload.locale == null ? "en" : boundedText(payload.locale, "invalid_notification_locale", 16)
      } : {
        ...shared,
        p_type: boundedText(payload.type, "invalid_notification_type", 100),
        p_title: boundedText(payload.title, "invalid_notification_title", 500),
        p_body: boundedText(payload.body, "invalid_notification_body", 8000)
      };
      const { data, error } = await boundedOperation((signal)=>dependencies.enqueue(name, parameters, signal), request.signal, timeout);
      if (error) throw error;
      if (data !== null && (typeof data !== "string" || !UUID.test(data))) {
        throw new Error("notification_enqueue_ack_unavailable");
      }
      let dispatchRequested = false;
      if (data !== null) {
        try {
          dispatchRequested = await boundedOperation((signal)=>dependencies.dispatch(signal), request.signal, timeout);
        } catch  {
        /* The durable event remains enqueued. A wake-up never re-enqueues it. */ }
      }
      return jsonResponse({
        ok: data !== null,
        skipped: data === null,
        notification_event_id: data,
        dispatch_requested: dispatchRequested
      });
    } catch (error) {
      void request.body?.cancel().catch(()=>{});
      const failure = publicFailure(error);
      return jsonResponse({
        error: failure.error
      }, failure.status);
    }
  };
}
//# sourceMappingURL=data:application/json;base64,eyJ2ZXJzaW9uIjozLCJzb3VyY2VzIjpbImZpbGU6Ly8vVm9sdW1lcy9QUk8tRzQwL1Byb2plY3RzL1JlY292ZXJlZC1HLVBSTy9DT09ML2RvY3MvcmVsZWFzZS9jcml0aWNhbC1pbXBsZW1lbnRhdGlvbi0yMDI2LTEwLTAxL3N1Y2Nlc3Nvci1vYnNlcnZlZC1maXh0dXJlLWltcG9ydC1wcm9wb3NhbDEvY2FuZGlkYXRlLXN0YWdlMS9zb3VyY2Uvc3VwYWJhc2UvZnVuY3Rpb25zL3NlbmQtbm90aWZpY2F0aW9uL2hhbmRsZXIudHMiXSwic291cmNlc0NvbnRlbnQiOlsiaW1wb3J0IHtcbiAgYm91bmRlZFRleHQsXG4gIG9iamVjdFZhbHVlLFxuICBQdWJsaWNFcnJvcixcbiAgcHVibGljRmFpbHVyZSxcbiAgVVVJRCxcbiAgdXVpZCxcbn0gZnJvbSBcIi4uL19zaGFyZWQvcHJvZHVjdGlvbl9jb250cmFjdC50c1wiO1xuaW1wb3J0IHsgY29yc0hlYWRlcnMsIGpzb25SZXNwb25zZSB9IGZyb20gXCIuLi9fc2hhcmVkL2NvcnMudHNcIjtcblxuZXhwb3J0IGNvbnN0IG5vdGlmaWNhdGlvblJlcXVlc3RUaW1lb3V0TXMgPSA4MDAwO1xuZXhwb3J0IHR5cGUgRW5xdWV1ZVJlc3VsdCA9IHsgZGF0YTogdW5rbm93bjsgZXJyb3I6IHVua25vd24gfTtcbmV4cG9ydCB0eXBlIE5vdGlmaWNhdGlvbkRlcGVuZGVuY2llcyA9IHtcbiAgYXV0aG9yaXplOiAocmVxdWVzdDogUmVxdWVzdCkgPT4gdm9pZDtcbiAgZW5xdWV1ZTogKFxuICAgIG5hbWU6IHN0cmluZyxcbiAgICBwYXJhbWV0ZXJzOiBSZWNvcmQ8c3RyaW5nLCB1bmtub3duPixcbiAgICBzaWduYWw6IEFib3J0U2lnbmFsLFxuICApID0+IFByb21pc2VMaWtlPEVucXVldWVSZXN1bHQ+O1xuICBkaXNwYXRjaDogKHNpZ25hbDogQWJvcnRTaWduYWwpID0+IFByb21pc2U8Ym9vbGVhbj47XG4gIHRpbWVvdXRNcz86IG51bWJlcjtcbn07XG5cbmFzeW5jIGZ1bmN0aW9uIG5vdGlmaWNhdGlvblBheWxvYWQoXG4gIHJlcXVlc3Q6IFJlcXVlc3QsXG4gIHNpZ25hbDogQWJvcnRTaWduYWwsXG4pOiBQcm9taXNlPFJlY29yZDxzdHJpbmcsIHVua25vd24+PiB7XG4gIGlmIChcbiAgICAhL15hcHBsaWNhdGlvblxcL2pzb24oPzpcXHMqO3wkKS9pLnRlc3QoXG4gICAgICByZXF1ZXN0LmhlYWRlcnMuZ2V0KFwiY29udGVudC10eXBlXCIpID8/IFwiXCIsXG4gICAgKVxuICApIHRocm93IG5ldyBQdWJsaWNFcnJvcihcImpzb25fcmVxdWlyZWRcIiwgNDE1KTtcbiAgY29uc3Qgc2l6ZSA9IHJlcXVlc3QuaGVhZGVycy5nZXQoXCJjb250ZW50LWxlbmd0aFwiKTtcbiAgaWYgKHNpemUgIT09IG51bGwgJiYgKCEvXlxcZCskLy50ZXN0KHNpemUpIHx8IE51bWJlcihzaXplKSA+IDE2Mzg0KSkge1xuICAgIHRocm93IG5ldyBQdWJsaWNFcnJvcihcInBheWxvYWRfdG9vX2xhcmdlXCIsIDQxMyk7XG4gIH1cbiAgY29uc3QgcmVhZGVyID0gcmVxdWVzdC5ib2R5Py5nZXRSZWFkZXIoKTtcbiAgaWYgKCFyZWFkZXIpIHRocm93IG5ldyBQdWJsaWNFcnJvcihcImludmFsaWRfanNvblwiKTtcbiAgY29uc3QgY2FuY2VsID0gKCkgPT4ge1xuICAgIHZvaWQgcmVhZGVyLmNhbmNlbCgpLmNhdGNoKCgpID0+IHt9KTtcbiAgfTtcbiAgc2lnbmFsLmFkZEV2ZW50TGlzdGVuZXIoXCJhYm9ydFwiLCBjYW5jZWwsIHsgb25jZTogdHJ1ZSB9KTtcbiAgY29uc3QgY2h1bmtzOiBVaW50OEFycmF5W10gPSBbXTtcbiAgbGV0IGxlbmd0aCA9IDA7XG4gIHRyeSB7XG4gICAgd2hpbGUgKHRydWUpIHtcbiAgICAgIHNpZ25hbC50aHJvd0lmQWJvcnRlZCgpO1xuICAgICAgY29uc3QgbmV4dCA9IGF3YWl0IHJlYWRlci5yZWFkKCk7XG4gICAgICBzaWduYWwudGhyb3dJZkFib3J0ZWQoKTtcbiAgICAgIGlmIChuZXh0LmRvbmUpIGJyZWFrO1xuICAgICAgbGVuZ3RoICs9IG5leHQudmFsdWUuYnl0ZUxlbmd0aDtcbiAgICAgIGlmIChsZW5ndGggPiAxNjM4NCkge1xuICAgICAgICBjYW5jZWwoKTtcbiAgICAgICAgdGhyb3cgbmV3IFB1YmxpY0Vycm9yKFwicGF5bG9hZF90b29fbGFyZ2VcIiwgNDEzKTtcbiAgICAgIH1cbiAgICAgIGNodW5rcy5wdXNoKG5leHQudmFsdWUpO1xuICAgIH1cbiAgICBjb25zdCBieXRlcyA9IG5ldyBVaW50OEFycmF5KGxlbmd0aCk7XG4gICAgbGV0IG9mZnNldCA9IDA7XG4gICAgZm9yIChjb25zdCBjaHVuayBvZiBjaHVua3MpIHtcbiAgICAgIGJ5dGVzLnNldChjaHVuaywgb2Zmc2V0KTtcbiAgICAgIG9mZnNldCArPSBjaHVuay5sZW5ndGg7XG4gICAgfVxuICAgIHRyeSB7XG4gICAgICByZXR1cm4gb2JqZWN0VmFsdWUoXG4gICAgICAgIEpTT04ucGFyc2UobmV3IFRleHREZWNvZGVyKFwidXRmLThcIiwgeyBmYXRhbDogdHJ1ZSB9KS5kZWNvZGUoYnl0ZXMpKSxcbiAgICAgICk7XG4gICAgfSBjYXRjaCB7XG4gICAgICB0aHJvdyBuZXcgUHVibGljRXJyb3IoXCJpbnZhbGlkX2pzb25cIik7XG4gICAgfVxuICB9IGZpbmFsbHkge1xuICAgIHNpZ25hbC5yZW1vdmVFdmVudExpc3RlbmVyKFwiYWJvcnRcIiwgY2FuY2VsKTtcbiAgICByZWFkZXIucmVsZWFzZUxvY2soKTtcbiAgfVxufVxuXG4vLyBGZXRjaC9Qb3N0Z1JFU1QgcmVjZWl2ZSB0aGUgc2FtZSBzaWduYWw7IHRoaXMgYWxzbyBib3VuZHMgYSBzdGFsbGVkIGJvZHkgb3Jcbi8vIGRlcGVuZGVuY3kgdGhhdCByZXNvbHZlcyBsYXRlLiBOZXZlciByZXBsYXkgYW4gZW5xdWV1ZSB3aXRoIGFuIHVuY2VydGFpbiBBQ0suXG5leHBvcnQgYXN5bmMgZnVuY3Rpb24gYm91bmRlZE9wZXJhdGlvbjxUPihcbiAgb3BlcmF0aW9uOiAoc2lnbmFsOiBBYm9ydFNpZ25hbCkgPT4gUHJvbWlzZUxpa2U8VD4sXG4gIHBhcmVudDogQWJvcnRTaWduYWwsXG4gIG1pbGxpc2Vjb25kczogbnVtYmVyLFxuKTogUHJvbWlzZTxUPiB7XG4gIGNvbnN0IHNpZ25hbCA9IEFib3J0U2lnbmFsLmFueShbcGFyZW50LCBBYm9ydFNpZ25hbC50aW1lb3V0KG1pbGxpc2Vjb25kcyldKTtcbiAgc2lnbmFsLnRocm93SWZBYm9ydGVkKCk7XG4gIGxldCBvbkFib3J0OiAoKCkgPT4gdm9pZCkgfCB1bmRlZmluZWQ7XG4gIHRyeSB7XG4gICAgcmV0dXJuIGF3YWl0IFByb21pc2UucmFjZShbXG4gICAgICBQcm9taXNlLnJlc29sdmUob3BlcmF0aW9uKHNpZ25hbCkpLFxuICAgICAgbmV3IFByb21pc2U8bmV2ZXI+KChfcmVzb2x2ZSwgcmVqZWN0KSA9PiB7XG4gICAgICAgIG9uQWJvcnQgPSAoKSA9PiByZWplY3Qoc2lnbmFsLnJlYXNvbik7XG4gICAgICAgIHNpZ25hbC5hZGRFdmVudExpc3RlbmVyKFwiYWJvcnRcIiwgb25BYm9ydCwgeyBvbmNlOiB0cnVlIH0pO1xuICAgICAgICBpZiAoc2lnbmFsLmFib3J0ZWQpIG9uQWJvcnQoKTtcbiAgICAgIH0pLFxuICAgIF0pO1xuICB9IGZpbmFsbHkge1xuICAgIGlmIChvbkFib3J0KSBzaWduYWwucmVtb3ZlRXZlbnRMaXN0ZW5lcihcImFib3J0XCIsIG9uQWJvcnQpO1xuICB9XG59XG5cbmV4cG9ydCBhc3luYyBmdW5jdGlvbiByZXF1ZXN0RGlzcGF0Y2goXG4gIHVybDogc3RyaW5nLFxuICBhcGlrZXk6IHN0cmluZyxcbiAgc2VjcmV0OiBzdHJpbmcsXG4gIHNpZ25hbDogQWJvcnRTaWduYWwsXG4gIGZldGNoZXI6IHR5cGVvZiBmZXRjaCA9IGZldGNoLFxuKTogUHJvbWlzZTxib29sZWFuPiB7XG4gIHRyeSB7XG4gICAgY29uc3QgZW5kcG9pbnQgPSBuZXcgVVJMKFwiL2Z1bmN0aW9ucy92MS9kaXNwYXRjaC1ub3RpZmljYXRpb25zXCIsIHVybCk7XG4gICAgLy8gRW52aXJvbm1lbnQgY29uZmlnIHN1cHBsaWVzIHRoZSBvcmlnaW4uIE5ldmVyIGZvcndhcmQgc2VjcmV0cyB0byBhXG4gICAgLy8gcmVkaXJlY3QsIGNyZWRlbnRpYWxzLWJlYXJpbmcgVVJMIG9yIGluc2VjdXJlIGhvc3RlZCBlbmRwb2ludC5cbiAgICBpZiAoXG4gICAgICBlbmRwb2ludC5wcm90b2NvbCAhPT0gXCJodHRwczpcIiB8fCBuZXcgVVJMKHVybCkudXNlcm5hbWUgfHxcbiAgICAgIG5ldyBVUkwodXJsKS5wYXNzd29yZCB8fCAhYXBpa2V5IHx8ICFzZWNyZXRcbiAgICApIHJldHVybiBmYWxzZTtcbiAgICBjb25zdCByZXNwb25zZSA9IGF3YWl0IGZldGNoZXIoZW5kcG9pbnQsIHtcbiAgICAgIG1ldGhvZDogXCJQT1NUXCIsXG4gICAgICBzaWduYWwsXG4gICAgICByZWRpcmVjdDogXCJlcnJvclwiLFxuICAgICAgaGVhZGVyczoge1xuICAgICAgICBhcGlrZXksXG4gICAgICAgIFwiQ29udGVudC1UeXBlXCI6IFwiYXBwbGljYXRpb24vanNvblwiLFxuICAgICAgICBcIngtY29sbGVjdC1zaWduYXR1cmVcIjogc2VjcmV0LFxuICAgICAgfSxcbiAgICAgIGJvZHk6IEpTT04uc3RyaW5naWZ5KHsgbGltaXQ6IDEwMCB9KSxcbiAgICB9KTtcbiAgICAvLyBUaGUgd29ya2VyIGNhbiB0YWtlIHVwIHRvIGEgbWludXRlLiBXYWtlLXVwIGlzIGJlc3QtZWZmb3J0OyBjcm9uIGhhbmRsZXNcbiAgICAvLyBkdXJhYmxlIHBlbmRpbmcgd29yaywgaW5jbHVkaW5nIGEgcmVzcG9uc2UgbG9zdCBhZnRlciBwcm92aWRlciBhY2NlcHRhbmNlLlxuICAgIHZvaWQgcmVzcG9uc2UuYm9keT8uY2FuY2VsKCkuY2F0Y2goKCkgPT4ge30pO1xuICAgIHJldHVybiByZXNwb25zZS5vayAmJiAhcmVzcG9uc2UucmVkaXJlY3RlZCAmJiByZXNwb25zZS5zdGF0dXMgPCAzMDA7XG4gIH0gY2F0Y2gge1xuICAgIHJldHVybiBmYWxzZTtcbiAgfVxufVxuXG5leHBvcnQgZnVuY3Rpb24gY3JlYXRlTm90aWZpY2F0aW9uSGFuZGxlcihcbiAgZGVwZW5kZW5jaWVzOiBOb3RpZmljYXRpb25EZXBlbmRlbmNpZXMsXG4pIHtcbiAgcmV0dXJuIGFzeW5jIChyZXF1ZXN0OiBSZXF1ZXN0KTogUHJvbWlzZTxSZXNwb25zZT4gPT4ge1xuICAgIGlmIChyZXF1ZXN0Lm1ldGhvZCA9PT0gXCJPUFRJT05TXCIpIHtcbiAgICAgIHJldHVybiBuZXcgUmVzcG9uc2UoXCJva1wiLCB7IGhlYWRlcnM6IGNvcnNIZWFkZXJzIH0pO1xuICAgIH1cbiAgICBpZiAocmVxdWVzdC5tZXRob2QgIT09IFwiUE9TVFwiKSB7XG4gICAgICByZXR1cm4ganNvblJlc3BvbnNlKHsgZXJyb3I6IFwiTWV0aG9kIG5vdCBhbGxvd2VkXCIgfSwgNDA1KTtcbiAgICB9XG4gICAgY29uc3QgdGltZW91dCA9IGRlcGVuZGVuY2llcy50aW1lb3V0TXMgPz8gbm90aWZpY2F0aW9uUmVxdWVzdFRpbWVvdXRNcztcbiAgICB0cnkge1xuICAgICAgZGVwZW5kZW5jaWVzLmF1dGhvcml6ZShyZXF1ZXN0KTtcbiAgICAgIGNvbnN0IHBheWxvYWQgPSBhd2FpdCBib3VuZGVkT3BlcmF0aW9uKFxuICAgICAgICAoc2lnbmFsKSA9PiBub3RpZmljYXRpb25QYXlsb2FkKHJlcXVlc3QsIHNpZ25hbCksXG4gICAgICAgIHJlcXVlc3Quc2lnbmFsLFxuICAgICAgICB0aW1lb3V0LFxuICAgICAgKTtcbiAgICAgIGNvbnN0IHVzZXJJZCA9IHV1aWQocGF5bG9hZC51c2VyX2lkLCBcImludmFsaWRfbm90aWZpY2F0aW9uX3VzZXJcIik7XG4gICAgICBjb25zdCB0ZW1wbGF0ZSA9IHBheWxvYWQudGVtcGxhdGVfa2V5ID09IG51bGwgPyBudWxsIDogYm91bmRlZFRleHQoXG4gICAgICAgIHBheWxvYWQudGVtcGxhdGVfa2V5LFxuICAgICAgICBcImludmFsaWRfbm90aWZpY2F0aW9uX3RlbXBsYXRlXCIsXG4gICAgICAgIDEwMCxcbiAgICAgICk7XG4gICAgICBjb25zdCBuYW1lID0gdGVtcGxhdGVcbiAgICAgICAgPyBcImVucXVldWVfbm90aWZpY2F0aW9uX3RlbXBsYXRlX2V2ZW50XCJcbiAgICAgICAgOiBcImVucXVldWVfbm90aWZpY2F0aW9uX2V2ZW50XCI7XG4gICAgICBjb25zdCBzaGFyZWQgPSB7XG4gICAgICAgIHBfdXNlcl9pZDogdXNlcklkLFxuICAgICAgICBwX2NvbGxlY3Rpb25faWQ6IHBheWxvYWQuY29sbGVjdGlvbl9pZCA/PyBudWxsLFxuICAgICAgICBwX2RlZXBfbGluazogcGF5bG9hZC5kZWVwX2xpbmsgPz8gbnVsbCxcbiAgICAgIH07XG4gICAgICBjb25zdCBwYXJhbWV0ZXJzID0gdGVtcGxhdGVcbiAgICAgICAgPyB7XG4gICAgICAgICAgLi4uc2hhcmVkLFxuICAgICAgICAgIHBfdGVtcGxhdGVfa2V5OiB0ZW1wbGF0ZSxcbiAgICAgICAgICBwX2NvbnRleHQ6IG9iamVjdFZhbHVlKHBheWxvYWQuY29udGV4dCA/PyB7fSksXG4gICAgICAgICAgcF9sb2NhbGU6IHBheWxvYWQubG9jYWxlID09IG51bGxcbiAgICAgICAgICAgID8gXCJlblwiXG4gICAgICAgICAgICA6IGJvdW5kZWRUZXh0KHBheWxvYWQubG9jYWxlLCBcImludmFsaWRfbm90aWZpY2F0aW9uX2xvY2FsZVwiLCAxNiksXG4gICAgICAgIH1cbiAgICAgICAgOiB7XG4gICAgICAgICAgLi4uc2hhcmVkLFxuICAgICAgICAgIHBfdHlwZTogYm91bmRlZFRleHQocGF5bG9hZC50eXBlLCBcImludmFsaWRfbm90aWZpY2F0aW9uX3R5cGVcIiwgMTAwKSxcbiAgICAgICAgICBwX3RpdGxlOiBib3VuZGVkVGV4dChcbiAgICAgICAgICAgIHBheWxvYWQudGl0bGUsXG4gICAgICAgICAgICBcImludmFsaWRfbm90aWZpY2F0aW9uX3RpdGxlXCIsXG4gICAgICAgICAgICA1MDAsXG4gICAgICAgICAgKSxcbiAgICAgICAgICBwX2JvZHk6IGJvdW5kZWRUZXh0KHBheWxvYWQuYm9keSwgXCJpbnZhbGlkX25vdGlmaWNhdGlvbl9ib2R5XCIsIDgwMDApLFxuICAgICAgICB9O1xuICAgICAgY29uc3QgeyBkYXRhLCBlcnJvciB9ID0gYXdhaXQgYm91bmRlZE9wZXJhdGlvbihcbiAgICAgICAgKHNpZ25hbCkgPT4gZGVwZW5kZW5jaWVzLmVucXVldWUobmFtZSwgcGFyYW1ldGVycywgc2lnbmFsKSxcbiAgICAgICAgcmVxdWVzdC5zaWduYWwsXG4gICAgICAgIHRpbWVvdXQsXG4gICAgICApO1xuICAgICAgaWYgKGVycm9yKSB0aHJvdyBlcnJvcjtcbiAgICAgIGlmIChkYXRhICE9PSBudWxsICYmICh0eXBlb2YgZGF0YSAhPT0gXCJzdHJpbmdcIiB8fCAhVVVJRC50ZXN0KGRhdGEpKSkge1xuICAgICAgICB0aHJvdyBuZXcgRXJyb3IoXCJub3RpZmljYXRpb25fZW5xdWV1ZV9hY2tfdW5hdmFpbGFibGVcIik7XG4gICAgICB9XG4gICAgICBsZXQgZGlzcGF0Y2hSZXF1ZXN0ZWQgPSBmYWxzZTtcbiAgICAgIGlmIChkYXRhICE9PSBudWxsKSB7XG4gICAgICAgIHRyeSB7XG4gICAgICAgICAgZGlzcGF0Y2hSZXF1ZXN0ZWQgPSBhd2FpdCBib3VuZGVkT3BlcmF0aW9uKFxuICAgICAgICAgICAgKHNpZ25hbCkgPT4gZGVwZW5kZW5jaWVzLmRpc3BhdGNoKHNpZ25hbCksXG4gICAgICAgICAgICByZXF1ZXN0LnNpZ25hbCxcbiAgICAgICAgICAgIHRpbWVvdXQsXG4gICAgICAgICAgKTtcbiAgICAgICAgfSBjYXRjaCB7XG4gICAgICAgICAgLyogVGhlIGR1cmFibGUgZXZlbnQgcmVtYWlucyBlbnF1ZXVlZC4gQSB3YWtlLXVwIG5ldmVyIHJlLWVucXVldWVzIGl0LiAqL1xuICAgICAgICB9XG4gICAgICB9XG4gICAgICByZXR1cm4ganNvblJlc3BvbnNlKHtcbiAgICAgICAgb2s6IGRhdGEgIT09IG51bGwsXG4gICAgICAgIHNraXBwZWQ6IGRhdGEgPT09IG51bGwsXG4gICAgICAgIG5vdGlmaWNhdGlvbl9ldmVudF9pZDogZGF0YSxcbiAgICAgICAgZGlzcGF0Y2hfcmVxdWVzdGVkOiBkaXNwYXRjaFJlcXVlc3RlZCxcbiAgICAgIH0pO1xuICAgIH0gY2F0Y2ggKGVycm9yKSB7XG4gICAgICB2b2lkIHJlcXVlc3QuYm9keT8uY2FuY2VsKCkuY2F0Y2goKCkgPT4ge30pO1xuICAgICAgY29uc3QgZmFpbHVyZSA9IHB1YmxpY0ZhaWx1cmUoZXJyb3IpO1xuICAgICAgcmV0dXJuIGpzb25SZXNwb25zZSh7IGVycm9yOiBmYWlsdXJlLmVycm9yIH0sIGZhaWx1cmUuc3RhdHVzKTtcbiAgICB9XG4gIH07XG59XG4iXSwibmFtZXMiOltdLCJtYXBwaW5ncyI6IkFBQUEsU0FDRSxXQUFXLEVBQ1gsV0FBVyxFQUNYLFdBQVcsRUFDWCxhQUFhLEVBQ2IsSUFBSSxFQUNKLElBQUksUUFDQyxvQ0FBb0M7QUFDM0MsU0FBUyxXQUFXLEVBQUUsWUFBWSxRQUFRLHFCQUFxQjtBQUUvRCxPQUFPLE1BQU0sK0JBQStCLEtBQUs7QUFhakQsZUFBZSxvQkFDYixPQUFnQixFQUNoQixNQUFtQjtFQUVuQixJQUNFLENBQUMsZ0NBQWdDLElBQUksQ0FDbkMsUUFBUSxPQUFPLENBQUMsR0FBRyxDQUFDLG1CQUFtQixLQUV6QyxNQUFNLElBQUksWUFBWSxpQkFBaUI7RUFDekMsTUFBTSxPQUFPLFFBQVEsT0FBTyxDQUFDLEdBQUcsQ0FBQztFQUNqQyxJQUFJLFNBQVMsUUFBUSxDQUFDLENBQUMsUUFBUSxJQUFJLENBQUMsU0FBUyxPQUFPLFFBQVEsS0FBSyxHQUFHO0lBQ2xFLE1BQU0sSUFBSSxZQUFZLHFCQUFxQjtFQUM3QztFQUNBLE1BQU0sU0FBUyxRQUFRLElBQUksRUFBRTtFQUM3QixJQUFJLENBQUMsUUFBUSxNQUFNLElBQUks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
// denoCacheMetadata=2047544021675092078,6007785554714751825