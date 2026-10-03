import { corsHeaders, jsonResponse } from "../_shared/cors.ts";
import { hashPhone, normalizeRwandaPhone, sha256Hex } from "../_shared/hash.ts";
import { verifySmsHook } from "../_shared/signed_sms_hook.ts";
import { boundedBody, objectValue, PublicError, SHA256, UUID } from "../_shared/production_contract.ts";
const states = new Set([
  "reserved",
  "sending",
  "accepted",
  "delivered",
  "not_sent",
  "failed",
  "ambiguous",
  "expired"
]);
const unresolved = ()=>new PublicError("otp_delivery_unresolved", 503);
/** Exact durable identity is required before a hook may send or acknowledge. */ export function otpReceipt(value, id, hash) {
  let r;
  try {
    r = objectValue(value);
  } catch  {
    throw unresolved();
  }
  if (r.contract_version !== 3 || r.hook_id !== id || r.payload_hash !== hash || !SHA256.test(hash) || typeof r.attempt_id !== "string" || !UUID.test(r.attempt_id) || typeof r.state !== "string" || !states.has(r.state) || !Number.isSafeInteger(r.revision) || r.revision < 1 || typeof r.can_send !== "boolean" || r.can_send && r.state !== "reserved") throw unresolved();
  return r;
}
function beforeDeadline(promise, signal) {
  return new Promise((resolve, reject)=>{
    if (signal.aborted) {
      reject(unresolved());
      return;
    }
    const abort = ()=>reject(unresolved());
    signal.addEventListener("abort", abort, {
      once: true
    });
    Promise.resolve(promise).then(resolve, reject).finally(()=>signal.removeEventListener("abort", abort));
  });
}
function hookError(code, status) {
  return jsonResponse({
    error: {
      http_code: status,
      message: code
    }
  }, status);
}
function required(deps, name) {
  const value = deps.env(name)?.trim();
  if (!value) throw new PublicError("otp_configuration_unavailable", 503);
  return value;
}
function terminal(state) {
  if (state === "not_sent") throw new PublicError("otp_not_sent", 502);
  if (state === "failed") throw new PublicError("otp_delivery_failed", 502);
  if (state === "expired") throw new PublicError("otp_expired", 502);
  throw unresolved();
}
export function createOtpHandler(deps) {
  return async (req)=>{
    if (req.method === "OPTIONS") {
      return new Response("ok", {
        headers: corsHeaders
      });
    }
    if (req.method !== "POST") {
      return hookError("method_not_allowed", 405);
    }
    const deadline = AbortSignal.timeout(deps.budgets?.totalMs ?? 4000);
    try {
      const dryRun = deps.env("WHATSAPP_CLOUD_DRY_RUN")?.trim().toLowerCase();
      if (dryRun && dryRun !== "false") {
        throw new PublicError("otp_configuration_unavailable", 503);
      }
      const previous = deps.env("SEND_SMS_HOOK_PREVIOUS_SECRET")?.trim();
      const verified = await beforeDeadline(verifySmsHook(req, [
        required(deps, "SEND_SMS_HOOK_SECRET"),
        ...previous ? [
          previous
        ] : []
      ], Math.floor(deps.now() / 1000)), deadline);
      const phone = normalizeRwandaPhone(objectValue(verified.payload.user).phone);
      const otp = objectValue(verified.payload.sms).otp;
      if (!phone || typeof otp !== "string" || !/^\d{6,10}$/.test(otp)) {
        throw new PublicError("invalid_otp_payload");
      }
      // Complete configuration/message construction before consuming quota.
      const version = required(deps, "WHATSAPP_GRAPH_API_VERSION");
      const phoneId = required(deps, "WHATSAPP_PHONE_NUMBER_ID");
      const button = required(deps, "WHATSAPP_CLOUD_OTP_AUTH_BUTTON");
      const token = required(deps, "WHATSAPP_CLOUD_API_TOKEN");
      const template = required(deps, "WHATSAPP_AUTH_TEMPLATE_NAME");
      const language = required(deps, "WHATSAPP_AUTH_TEMPLATE_LANGUAGE");
      if (!/^v\d{1,3}\.0$/.test(version) || !/^\d{1,32}$/.test(phoneId) || ![
        "true",
        "false"
      ].includes(button) || template.length > 512 || language.length > 32) {
        throw new PublicError("otp_configuration_unavailable", 503);
      }
      const components = [
        {
          type: "body",
          parameters: [
            {
              type: "text",
              text: otp
            }
          ]
        }
      ];
      if (button === "true") {
        components.push({
          type: "button",
          sub_type: "url",
          index: "0",
          parameters: [
            {
              type: "text",
              text: otp
            }
          ]
        });
      }
      const message = JSON.stringify({
        messaging_product: "whatsapp",
        to: phone.slice(1),
        type: "template",
        template: {
          name: template,
          language: {
            code: language
          },
          components
        }
      });
      const service = deps.service();
      const rpc = (name, args)=>{
        if (deadline.aborted) throw unresolved();
        const query = service.rpc(name, args);
        return beforeDeadline(query.abortSignal ? query.abortSignal(deadline) : query, deadline);
      };
      const payloadHash = await sha256Hex(verified.body);
      const identity = {
        p_hook_id: verified.id,
        p_payload_hash: payloadHash
      };
      const reserve = await rpc("reserve_signed_otp_v3", {
        ...identity,
        p_phone_hash: await hashPhone(phone)
      });
      if (reserve.error) {
        throw new PublicError("otp_reservation_unavailable", 503);
      }
      if (reserve.data === "throttled") {
        throw new PublicError("otp_rate_limited", 429);
      }
      const receipt = otpReceipt(reserve.data, verified.id, payloadHash);
      if (receipt.state === "accepted" || receipt.state === "delivered") {
        return jsonResponse({});
      }
      if (!receipt.can_send) terminal(receipt.state);
      const begun = await rpc("begin_signed_otp_v3", {
        ...identity,
        p_attempt_id: receipt.attempt_id,
        p_revision: receipt.revision
      });
      if (begun.error) throw unresolved();
      const start = otpReceipt(begun.data, verified.id, payloadHash);
      const started = objectValue(begun.data).started;
      if (started !== true || start.attempt_id !== receipt.attempt_id || start.state !== "sending" || start.revision !== receipt.revision + 1 || start.can_send) {
        // Another signed invocation may have completed while this one waited.
        if (started === false && start.attempt_id === receipt.attempt_id && (start.state === "accepted" || start.state === "delivered")) return jsonResponse({});
        throw unresolved();
      }
      // Once begin is durable, every transport failure is ambiguous. HTTP errors
      // and AbortSignal are not proof that the provider did not accept a request.
      let outcome = "ambiguous";
      let providerHash = null;
      let evidenceHash = await sha256Hex("transport_outcome_unobserved_v3");
      try {
        const providerDeadline = AbortSignal.any([
          deadline,
          AbortSignal.timeout(deps.budgets?.providerMs ?? 2500)
        ]);
        const response = await beforeDeadline(deps.fetch(`https://graph.facebook.com/${version}/${phoneId}/messages`, {
          method: "POST",
          redirect: "error",
          signal: providerDeadline,
          headers: {
            Authorization: `Bearer ${token}`,
            "Content-Type": "application/json"
          },
          body: message
        }), providerDeadline);
        const raw = await beforeDeadline(boundedBody(response, 65536), providerDeadline);
        evidenceHash = await sha256Hex(`${response.status}\n${raw}`);
        const data = objectValue(JSON.parse(raw));
        if (response.ok && Array.isArray(data.messages) && data.messages.length === 1) {
          const id = objectValue(data.messages[0]).id;
          if (typeof id === "string" && id.length > 0 && id.length <= 512 && !Array.from(id).some((c)=>c.charCodeAt(0) < 32 || c.charCodeAt(0) === 127)) {
            providerHash = await sha256Hex(id);
            outcome = "accepted";
          }
        }
      } catch  {}
      const result = await rpc("record_signed_otp_v3", {
        ...identity,
        p_attempt_id: start.attempt_id,
        p_revision: start.revision,
        p_outcome: outcome,
        p_provider_message_hash: providerHash,
        p_evidence_sha256: evidenceHash
      });
      if (result.error) throw unresolved();
      const completed = otpReceipt(result.data, verified.id, payloadHash);
      if (completed.attempt_id !== start.attempt_id || completed.can_send || completed.revision < start.revision + 1) throw unresolved();
      // A recovery may already have proved delivery; neither path resends.
      if (outcome === "accepted" && (completed.state === "accepted" || completed.state === "delivered")) return jsonResponse({});
      throw new PublicError("otp_delivery_unresolved", 503);
    } catch (error) {
      // Only literal codes from this boundary/shared validators are public.
      // Even a dependency throwing a forged PublicError cannot disclose text.
      const allowed = new Map([
        [
          "invalid_hook_signature",
          401
        ],
        [
          "hook_configuration_unavailable",
          503
        ],
        [
          "payload_too_large",
          413
        ],
        [
          "invalid_utf8",
          400
        ],
        [
          "invalid_hook_payload",
          400
        ],
        [
          "invalid_payload",
          400
        ],
        [
          "invalid_otp_payload",
          400
        ],
        [
          "otp_configuration_unavailable",
          503
        ],
        [
          "otp_reservation_unavailable",
          503
        ],
        [
          "otp_rate_limited",
          429
        ],
        [
          "otp_not_sent",
          502
        ],
        [
          "otp_delivery_failed",
          502
        ],
        [
          "otp_expired",
          502
        ],
        [
          "otp_delivery_unresolved",
          503
        ]
      ]);
      const code = error instanceof PublicError && allowed.has(error.code) ? error.code : "service_unavailable";
      return hookError(code, allowed.get(code) ?? 503);
    }
  };
}
//# sourceMappingURL=data:application/json;base64,eyJ2ZXJzaW9uIjozLCJzb3VyY2VzIjpbImZpbGU6Ly8vVm9sdW1lcy9QUk8tRzQwL1Byb2plY3RzL1JlY292ZXJlZC1HLVBSTy9DT09ML2RvY3MvcmVsZWFzZS9jcml0aWNhbC1pbXBsZW1lbnRhdGlvbi0yMDI2LTEwLTAxL3N1Y2Nlc3Nvci1vYnNlcnZlZC1maXh0dXJlLWltcG9ydC1wcm9wb3NhbDEvY2FuZGlkYXRlLXN0YWdlMS9zb3VyY2Uvc3VwYWJhc2UvZnVuY3Rpb25zL2F1dGgtc2VuZC13aGF0c2FwcC1vdHAvaGFuZGxlci50cyJdLCJzb3VyY2VzQ29udGVudCI6WyJpbXBvcnQgeyBjb3JzSGVhZGVycywganNvblJlc3BvbnNlIH0gZnJvbSBcIi4uL19zaGFyZWQvY29ycy50c1wiO1xuaW1wb3J0IHsgaGFzaFBob25lLCBub3JtYWxpemVSd2FuZGFQaG9uZSwgc2hhMjU2SGV4IH0gZnJvbSBcIi4uL19zaGFyZWQvaGFzaC50c1wiO1xuaW1wb3J0IHsgdmVyaWZ5U21zSG9vayB9IGZyb20gXCIuLi9fc2hhcmVkL3NpZ25lZF9zbXNfaG9vay50c1wiO1xuaW1wb3J0IHtcbiAgYm91bmRlZEJvZHksXG4gIG9iamVjdFZhbHVlLFxuICBQdWJsaWNFcnJvcixcbiAgU0hBMjU2LFxuICBVVUlELFxufSBmcm9tIFwiLi4vX3NoYXJlZC9wcm9kdWN0aW9uX2NvbnRyYWN0LnRzXCI7XG5cbnR5cGUgUnBjUmVzdWx0ID0geyBkYXRhOiB1bmtub3duOyBlcnJvcjogdW5rbm93biB9O1xudHlwZSBScGNRdWVyeSA9IFByb21pc2VMaWtlPFJwY1Jlc3VsdD4gJiB7XG4gIGFib3J0U2lnbmFsPyhzaWduYWw6IEFib3J0U2lnbmFsKTogUHJvbWlzZUxpa2U8UnBjUmVzdWx0Pjtcbn07XG5leHBvcnQgaW50ZXJmYWNlIE90cERlcGVuZGVuY2llcyB7XG4gIGVudihuYW1lOiBzdHJpbmcpOiBzdHJpbmcgfCB1bmRlZmluZWQ7XG4gIHNlcnZpY2UoKToge1xuICAgIHJwYyhuYW1lOiBzdHJpbmcsIGFyZ3M6IFJlY29yZDxzdHJpbmcsIHVua25vd24+KTogUnBjUXVlcnk7XG4gIH07XG4gIGZldGNoKHVybDogc3RyaW5nLCBpbml0OiBSZXF1ZXN0SW5pdCk6IFByb21pc2U8UmVzcG9uc2U+O1xuICBub3coKTogbnVtYmVyO1xuICAvKiogT3B0aW9uYWwgc2hvcnRlciBidWRnZXRzIGZvciBsb2NhbCB0aW1lb3V0IHRlc3RzOyBwcm9kdWN0aW9uIGRlZmF1bHRzIGFyZSBmaXhlZC4gKi9cbiAgYnVkZ2V0cz86IHsgdG90YWxNczogbnVtYmVyOyBwcm92aWRlck1zOiBudW1iZXIgfTtcbn1cbmV4cG9ydCB0eXBlIE90cFN0YXRlID1cbiAgfCBcInJlc2VydmVkXCJcbiAgfCBcInNlbmRpbmdcIlxuICB8IFwiYWNjZXB0ZWRcIlxuICB8IFwiZGVsaXZlcmVkXCJcbiAgfCBcIm5vdF9zZW50XCJcbiAgfCBcImZhaWxlZFwiXG4gIHwgXCJhbWJpZ3VvdXNcIlxuICB8IFwiZXhwaXJlZFwiO1xuZXhwb3J0IHR5cGUgT3RwUmVjZWlwdCA9IHtcbiAgY29udHJhY3RfdmVyc2lvbjogMztcbiAgaG9va19pZDogc3RyaW5nO1xuICBwYXlsb2FkX2hhc2g6IHN0cmluZztcbiAgYXR0ZW1wdF9pZDogc3RyaW5nO1xuICBzdGF0ZTogT3RwU3RhdGU7XG4gIHJldmlzaW9uOiBudW1iZXI7XG4gIGNhbl9zZW5kOiBib29sZWFuO1xufTtcbmNvbnN0IHN0YXRlcyA9IG5ldyBTZXQ8T3RwU3RhdGU+KFtcbiAgXCJyZXNlcnZlZFwiLFxuICBcInNlbmRpbmdcIixcbiAgXCJhY2NlcHRlZFwiLFxuICBcImRlbGl2ZXJlZFwiLFxuICBcIm5vdF9zZW50XCIsXG4gIFwiZmFpbGVkXCIsXG4gIFwiYW1iaWd1b3VzXCIsXG4gIFwiZXhwaXJlZFwiLFxuXSk7XG5jb25zdCB1bnJlc29sdmVkID0gKCkgPT4gbmV3IFB1YmxpY0Vycm9yKFwib3RwX2RlbGl2ZXJ5X3VucmVzb2x2ZWRcIiwgNTAzKTtcblxuLyoqIEV4YWN0IGR1cmFibGUgaWRlbnRpdHkgaXMgcmVxdWlyZWQgYmVmb3JlIGEgaG9vayBtYXkgc2VuZCBvciBhY2tub3dsZWRnZS4gKi9cbmV4cG9ydCBmdW5jdGlvbiBvdHBSZWNlaXB0KFxuICB2YWx1ZTogdW5rbm93bixcbiAgaWQ6IHN0cmluZyxcbiAgaGFzaDogc3RyaW5nLFxuKTogT3RwUmVjZWlwdCB7XG4gIGxldCByOiBSZWNvcmQ8c3RyaW5nLCB1bmtub3duPjtcbiAgdHJ5IHtcbiAgICByID0gb2JqZWN0VmFsdWUodmFsdWUpO1xuICB9IGNhdGNoIHtcbiAgICB0aHJvdyB1bnJlc29sdmVkKCk7XG4gIH1cbiAgaWYgKFxuICAgIHIuY29udHJhY3RfdmVyc2lvbiAhPT0gMyB8fCByLmhvb2tfaWQgIT09IGlkIHx8IHIucGF5bG9hZF9oYXNoICE9PSBoYXNoIHx8XG4gICAgIVNIQTI1Ni50ZXN0KGhhc2gpIHx8IHR5cGVvZiByLmF0dGVtcHRfaWQgIT09IFwic3RyaW5nXCIgfHxcbiAgICAhVVVJRC50ZXN0KHIuYXR0ZW1wdF9pZCkgfHxcbiAgICB0eXBlb2Ygci5zdGF0ZSAhPT0gXCJzdHJpbmdcIiB8fCAhc3RhdGVzLmhhcyhyLnN0YXRlIGFzIE90cFN0YXRlKSB8fFxuICAgICFOdW1iZXIuaXNTYWZlSW50ZWdlcihyLnJldmlzaW9uKSB8fCAoci5yZXZpc2lvbiBhcyBudW1iZXIpIDwgMSB8fFxuICAgIHR5cGVvZiByLmNhbl9zZW5kICE9PSBcImJvb2xlYW5cIiB8fFxuICAgIChyLmNhbl9zZW5kICYmIHIuc3RhdGUgIT09IFwicmVzZXJ2ZWRcIilcbiAgKSB0aHJvdyB1bnJlc29sdmVkKCk7XG4gIHJldHVybiByIGFzIE90cFJlY2VpcHQ7XG59XG5cbmZ1bmN0aW9uIGJlZm9yZURlYWRsaW5lPFQ+KFxuICBwcm9taXNlOiBQcm9taXNlTGlrZTxUPixcbiAgc2lnbmFsOiBBYm9ydFNpZ25hbCxcbik6IFByb21pc2U8VD4ge1xuICByZXR1cm4gbmV3IFByb21pc2UoKHJlc29sdmUsIHJlamVjdCkgPT4ge1xuICAgIGlmIChzaWduYWwuYWJvcnRlZCkge1xuICAgICAgcmVqZWN0KHVucmVzb2x2ZWQoKSk7XG4gICAgICByZXR1cm47XG4gICAgfVxuICAgIGNvbnN0IGFib3J0ID0gKCkgPT4gcmVqZWN0KHVucmVzb2x2ZWQoKSk7XG4gICAgc2lnbmFsLmFkZEV2ZW50TGlzdGVuZXIoXCJhYm9ydFwiLCBhYm9ydCwgeyBvbmNlOiB0cnVlIH0pO1xuICAgIFByb21pc2UucmVzb2x2ZShwcm9taXNlKS50aGVuKHJlc29sdmUsIHJlamVjdCkuZmluYWxseSgoKSA9PlxuICAgICAgc2lnbmFsLnJlbW92ZUV2ZW50TGlzdGVuZXIoXCJhYm9ydFwiLCBhYm9ydClcbiAgICApO1xuICB9KTtcbn1cbmZ1bmN0aW9uIGhvb2tFcnJvcihjb2RlOiBzdHJpbmcsIHN0YXR1czogbnVtYmVyKTogUmVzcG9uc2Uge1xuICByZXR1cm4ganNvblJlc3BvbnNlKHsgZXJyb3I6IHsgaHR0cF9jb2RlOiBzdGF0dXMsIG1lc3NhZ2U6IGNvZGUgfSB9LCBzdGF0dXMpO1xufVxuXG5mdW5jdGlvbiByZXF1aXJlZChkZXBzOiBPdHBEZXBlbmRlbmNpZXMsIG5hbWU6IHN0cmluZyk6IHN0cmluZyB7XG4gIGNvbnN0IHZhbHVlID0gZGVwcy5lbnYobmFtZSk/LnRyaW0oKTtcbiAgaWYgKCF2YWx1ZSkgdGhyb3cgbmV3IFB1YmxpY0Vycm9yKFwib3RwX2NvbmZpZ3VyYXRpb25fdW5hdmFpbGFibGVcIiwgNTAzKTtcbiAgcmV0dXJuIHZhbHVlO1xufVxuZnVuY3Rpb24gdGVybWluYWwoc3RhdGU6IE90cFN0YXRlKTogbmV2ZXIge1xuICBpZiAoc3RhdGUgPT09IFwibm90X3NlbnRcIikgdGhyb3cgbmV3IFB1YmxpY0Vycm9yKFwib3RwX25vdF9zZW50XCIsIDUwMik7XG4gIGlmIChzdGF0ZSA9PT0gXCJmYWlsZWRcIikgdGhyb3cgbmV3IFB1YmxpY0Vycm9yKFwib3RwX2RlbGl2ZXJ5X2ZhaWxlZFwiLCA1MDIpO1xuICBpZiAoc3RhdGUgPT09IFwiZXhwaXJlZFwiKSB0aHJvdyBuZXcgUHVibGljRXJyb3IoXCJvdHBfZXhwaXJlZFwiLCA1MDIpO1xuICB0aHJvdyB1bnJlc29sdmVkKCk7XG59XG5cbmV4cG9ydCBmdW5jdGlvbiBjcmVhdGVPdHBIYW5kbGVyKGRlcHM6IE90cERlcGVuZGVuY2llcykge1xuICByZXR1cm4gYXN5bmMgKHJlcTogUmVxdWVzdCk6IFByb21pc2U8UmVzcG9uc2U+ID0+IHtcbiAgICBpZiAocmVxLm1ldGhvZCA9PT0gXCJPUFRJT05TXCIpIHtcbiAgICAgIHJldHVybiBuZXcgUmVzcG9uc2UoXCJva1wiLCB7IGhlYWRlcnM6IGNvcnNIZWFkZXJzIH0pO1xuICAgIH1cbiAgICBpZiAocmVxLm1ldGhvZCAhPT0gXCJQT1NUXCIpIHtcbiAgICAgIHJldHVybiBob29rRXJyb3IoXCJtZXRob2Rfbm90X2FsbG93ZWRcIiwgNDA1KTtcbiAgICB9XG4gICAgY29uc3QgZGVhZGxpbmUgPSBBYm9ydFNpZ25hbC50aW1lb3V0KGRlcHMuYnVkZ2V0cz8udG90YWxNcyA/PyA0MDAwKTtcbiAgICB0cnkge1xuICAgICAgY29uc3QgZHJ5UnVuID0gZGVwcy5lbnYoXCJXSEFUU0FQUF9DTE9VRF9EUllfUlVOXCIpPy50cmltKCkudG9Mb3dlckNhc2UoKTtcbiAgICAgIGlmIChkcnlSdW4gJiYgZHJ5UnVuICE9PSBcImZhbHNlXCIpIHtcbiAgICAgICAgdGhyb3cgbmV3IFB1YmxpY0Vycm9yKFwib3RwX2NvbmZpZ3VyYXRpb25fdW5hdmFpbGFibGVcIiwgNTAzKTtcbiAgICAgIH1cbiAgICAgIGNvbnN0IHByZXZpb3VzID0gZGVwcy5lbnYoXCJTRU5EX1NNU19IT09LX1BSRVZJT1VTX1NFQ1JFVFwiKT8udHJpbSgpO1xuICAgICAgY29uc3QgdmVyaWZpZWQgPSBhd2FpdCBiZWZvcmVEZWFkbGluZShcbiAgICAgICAgdmVyaWZ5U21zSG9vayhyZXEsIFtcbiAgICAgICAgICByZXF1aXJlZChkZXBzLCBcIlNFTkRfU01TX0hPT0tfU0VDUkVUXCIpLFxuICAgICAgICAgIC4uLihwcmV2aW91cyA/IFtwcmV2aW91c10gOiBbXSksXG4gICAgICAgIF0sIE1hdGguZmxvb3IoZGVwcy5ub3coKSAvIDEwMDApKSxcbiAgICAgICAgZGVhZGxpbmUsXG4gICAgICApO1xuICAgICAgY29uc3QgcGhvbmUgPSBub3JtYWxpemVSd2FuZGFQaG9uZShcbiAgICAgICAgb2JqZWN0VmFsdWUodmVyaWZpZWQucGF5bG9hZC51c2VyKS5waG9uZSBhcyBzdHJpbmcsXG4gICAgICApO1xuICAgICAgY29uc3Qgb3RwID0gb2JqZWN0VmFsdWUodmVyaWZpZWQucGF5bG9hZC5zbXMpLm90cDtcbiAgICAgIGlmICghcGhvbmUgfHwgdHlwZW9mIG90cCAhPT0gXCJzdHJpbmdcIiB8fCAhL15cXGR7NiwxMH0kLy50ZXN0KG90cCkpIHtcbiAgICAgICAgdGhyb3cgbmV3IFB1YmxpY0Vycm9yKFwiaW52YWxpZF9vdHBfcGF5bG9hZFwiKTtcbiAgICAgIH1cbiAgICAgIC8vIENvbXBsZXRlIGNvbmZpZ3VyYXRpb24vbWVzc2FnZSBjb25zdHJ1Y3Rpb24gYmVmb3JlIGNvbnN1bWluZyBxdW90YS5cbiAgICAgIGNvbnN0IHZlcnNpb24gPSByZXF1aXJlZChkZXBzLCBcIldIQVRTQVBQX0dSQVBIX0FQSV9WRVJTSU9OXCIpO1xuICAgICAgY29uc3QgcGhvbmVJZCA9IHJlcXVpcmVkKGRlcHMsIFwiV0hBVFNBUFBfUEhPTkVfTlVNQkVSX0lEXCIpO1xuICAgICAgY29uc3QgYnV0dG9uID0gcmVxdWlyZWQoZGVwcywgXCJXSEFUU0FQUF9DTE9VRF9PVFBfQVVUSF9CVVRUT05cIik7XG4gICAgICBjb25zdCB0b2tlbiA9IHJlcXVpcmVkKGRlcHMsIFwiV0hBVFNBUFBfQ0xPVURfQVBJX1RPS0VOXCIpO1xuICAgICAgY29uc3QgdGVtcGxhdGUgPSByZXF1aXJlZChkZXBzLCBcIldIQVRTQVBQX0FVVEhfVEVNUExBVEVfTkFNRVwiKTtcbiAgICAgIGNvbnN0IGxhbmd1YWdlID0gcmVxdWlyZWQoZGVwcywgXCJXSEFUU0FQUF9BVVRIX1RFTVBMQVRFX0xBTkdVQUdFXCIpO1xuICAgICAgaWYgKFxuICAgICAgICAhL152XFxkezEsM31cXC4wJC8udGVzdCh2ZXJzaW9uKSB8fCAhL15cXGR7MSwzMn0kLy50ZXN0KHBob25lSWQpIHx8XG4gICAgICAgICFbXCJ0cnVlXCIsIFwiZmFsc2VcIl0uaW5jbHVkZXMoYnV0dG9uKSB8fCB0ZW1wbGF0ZS5sZW5ndGggPiA1MTIgfHxcbiAgICAgICAgbGFuZ3VhZ2UubGVuZ3RoID4gMzJcbiAgICAgICkge1xuICAgICAgICB0aHJvdyBuZXcgUHVibGljRXJyb3IoXCJvdHBfY29uZmlndXJhdGlvbl91bmF2YWlsYWJsZVwiLCA1MDMpO1xuICAgICAgfVxuICAgICAgY29uc3QgY29tcG9uZW50czogQXJyYXk8UmVjb3JkPHN0cmluZywgdW5rbm93bj4+ID0gW3tcbiAgICAgICAgdHlwZTogXCJib2R5XCIsXG4gICAgICAgIHBhcmFtZXRlcnM6IFt7IHR5cGU6IFwidGV4dFwiLCB0ZXh0OiBvdHAgfV0sXG4gICAgICB9XTtcbiAgICAgIGlmIChidXR0b24gPT09IFwidHJ1ZVwiKSB7XG4gICAgICAgIGNvbXBvbmVudHMucHVzaCh7XG4gICAgICAgICAgdHlwZTogXCJidXR0b25cIixcbiAgICAgICAgICBzdWJfdHlwZTogXCJ1cmxcIixcbiAgICAgICAgICBpbmRleDogXCIwXCIsXG4gICAgICAgICAgcGFyYW1ldGVyczogW3sgdHlwZTogXCJ0ZXh0XCIsIHRleHQ6IG90cCB9XSxcbiAgICAgICAgfSk7XG4gICAgICB9XG4gICAgICBjb25zdCBtZXNzYWdlID0gSlNPTi5zdHJpbmdpZnkoe1xuICAgICAgICBtZXNzYWdpbmdfcHJvZHVjdDogXCJ3aGF0c2FwcFwiLFxuICAgICAgICB0bzogcGhvbmUuc2xpY2UoMSksXG4gICAgICAgIHR5cGU6IFwidGVtcGxhdGVcIixcbiAgICAgICAgdGVtcGxhdGU6IHsgbmFtZTogdGVtcGxhdGUsIGxhbmd1YWdlOiB7IGNvZGU6IGxhbmd1YWdlIH0sIGNvbXBvbmVudHMgfSxcbiAgICAgIH0pO1xuICAgICAgY29uc3Qgc2VydmljZSA9IGRlcHMuc2VydmljZSgpO1xuICAgICAgY29uc3QgcnBjID0gKG5hbWU6IHN0cmluZywgYXJnczogUmVjb3JkPHN0cmluZywgdW5rbm93bj4pID0+IHtcbiAgICAgICAgaWYgKGRlYWRsaW5lLmFib3J0ZWQpIHRocm93IHVucmVzb2x2ZWQoKTtcbiAgICAgICAgY29uc3QgcXVlcnkgPSBzZXJ2aWNlLnJwYyhuYW1lLCBhcmdzKTtcbiAgICAgICAgcmV0dXJuIGJlZm9yZURlYWRsaW5lKFxuICAgICAgICAgIHF1ZXJ5LmFib3J0U2lnbmFsID8gcXVlcnkuYWJvcnRTaWduYWwoZGVhZGxpbmUpIDogcXVlcnksXG4gICAgICAgICAgZGVhZGxpbmUsXG4gICAgICAgICk7XG4gICAgICB9O1xuICAgICAgY29uc3QgcGF5bG9hZEhhc2ggPSBhd2FpdCBzaGEyNTZIZXgodmVyaWZpZWQuYm9keSk7XG4gICAgICBjb25zdCBpZGVudGl0eSA9IHsgcF9ob29rX2lkOiB2ZXJpZmllZC5pZCwgcF9wYXlsb2FkX2hhc2g6IHBheWxvYWRIYXNoIH07XG4gICAgICBjb25zdCByZXNlcnZlID0gYXdhaXQgcnBjKFwicmVzZXJ2ZV9zaWduZWRfb3RwX3YzXCIsIHtcbiAgICAgICAgLi4uaWRlbnRpdHksXG4gICAgICAgIHBfcGhvbmVfaGFzaDogYXdhaXQgaGFzaFBob25lKHBob25lKSxcbiAgICAgIH0pO1xuICAgICAgaWYgKHJlc2VydmUuZXJyb3IpIHtcbiAgICAgICAgdGhyb3cgbmV3IFB1YmxpY0Vycm9yKFwib3RwX3Jlc2VydmF0aW9uX3VuYXZhaWxhYmxlXCIsIDUwMyk7XG4gICAgICB9XG4gICAgICBpZiAocmVzZXJ2ZS5kYXRhID09PSBcInRocm90dGxlZFwiKSB7XG4gICAgICAgIHRocm93IG5ldyBQdWJsaWNFcnJvcihcIm90cF9yYXRlX2xpbWl0ZWRcIiwgNDI5KTtcbiAgICAgIH1cbiAgICAgIGNvbnN0IHJlY2VpcHQgPSBvdHBSZWNlaXB0KHJlc2VydmUuZGF0YSwgdmVyaWZpZWQuaWQsIHBheWxvYWRIYXNoKTtcbiAgICAgIGlmIChyZWNlaXB0LnN0YXRlID09PSBcImFjY2VwdGVkXCIgfHwgcmVjZWlwdC5zdGF0ZSA9PT0gXCJkZWxpdmVyZWRcIikge1xuICAgICAgICByZXR1cm4ganNvblJlc3BvbnNlKHt9KTtcbiAgICAgIH1cbiAgICAgIGlmICghcmVjZWlwdC5jYW5fc2VuZCkgdGVybWluYWwocmVjZWlwdC5zdGF0ZSk7XG4gICAgICBjb25zdCBiZWd1biA9IGF3YWl0IHJwYyhcImJlZ2luX3NpZ25lZF9vdHBfdjNcIiwge1xuICAgICAgICAuLi5pZGVudGl0eSxcbiAgICAgICAgcF9hdHRlbXB0X2lkOiByZWNlaXB0LmF0dGVtcHRfaWQsXG4gICAgICAgIHBfcmV2aXNpb246IHJlY2VpcHQucmV2aXNpb24sXG4gICAgICB9KTtcbiAgICAgIGlmIChiZWd1bi5lcnJvcikgdGhyb3cgdW5yZXNvbHZlZCgpO1xuICAgICAgY29uc3Qgc3RhcnQgPSBvdHBSZWNlaXB0KGJlZ3VuLmRhdGEsIHZlcmlmaWVkLmlkLCBwYXlsb2FkSGFzaCk7XG4gICAgICBjb25zdCBzdGFydGVkID0gb2JqZWN0VmFsdWUoYmVndW4uZGF0YSkuc3RhcnRlZDtcbiAgICAgIGlmIChcbiAgICAgICAgc3RhcnRlZCAhPT0gdHJ1ZSB8fCBzdGFydC5hdHRlbXB0X2lkICE9PSByZWNlaXB0LmF0dGVtcHRfaWQgfHxcbiAgICAgICAgc3RhcnQuc3RhdGUgIT09IFwic2VuZGluZ1wiIHx8IHN0YXJ0LnJldmlzaW9uICE9PSByZWNlaXB0LnJldmlzaW9uICsgMSB8fFxuICAgICAgICBzdGFydC5jYW5fc2VuZFxuICAgICAgKSB7XG4gICAgICAgIC8vIEFub3RoZXIgc2lnbmVkIGludm9jYXRpb24gbWF5IGhhdmUgY29tcGxldGVkIHdoaWxlIHRoaXMgb25lIHdhaXRlZC5cbiAgICAgICAgaWYgKFxuICAgICAgICAgIHN0YXJ0ZWQgPT09IGZhbHNlICYmIHN0YXJ0LmF0dGVtcHRfaWQgPT09IHJlY2VpcHQuYXR0ZW1wdF9pZCAmJlxuICAgICAgICAgIChzdGFydC5zdGF0ZSA9PT0gXCJhY2NlcHRlZFwiIHx8IHN0YXJ0LnN0YXRlID09PSBcImRlbGl2ZXJlZFwiKVxuICAgICAgICApIHJldHVybiBqc29uUmVzcG9uc2Uoe30pO1xuICAgICAgICB0aHJvdyB1bnJlc29sdmVkKCk7XG4gICAgICB9XG5cbiAgICAgIC8vIE9uY2UgYmVnaW4gaXMgZHVyYWJsZSwgZXZlcnkgdHJhbnNwb3J0IGZhaWx1cmUgaXMgYW1iaWd1b3VzLiBIVFRQIGVycm9yc1xuICAgICAgLy8gYW5kIEFib3J0U2lnbmFsIGFyZSBub3QgcHJvb2YgdGhhdCB0aGUgcHJvdmlkZXIgZGlkIG5vdCBhY2NlcHQgYSByZXF1ZXN0LlxuICAgICAgbGV0IG91dGNvbWU6IFwiYWNjZXB0ZWRcIiB8IFwiYW1iaWd1b3VzXCIgPSBcImFtYmlndW91c1wiO1xuICAgICAgbGV0IHByb3ZpZGVySGFzaDogc3RyaW5nIHwgbnVsbCA9IG51bGw7XG4gICAgICBsZXQgZXZpZGVuY2VIYXNoID0gYXdhaXQgc2hhMjU2SGV4KFwidHJhbnNwb3J0X291dGNvbWVfdW5vYnNlcnZlZF92M1wiKTtcbiAgICAgIHRyeSB7XG4gICAgICAgIGNvbnN0IHByb3ZpZGVyRGVhZGxpbmUgPSBBYm9ydFNpZ25hbC5hbnkoW1xuICAgICAgICAgIGRlYWRsaW5lLFxuICAgICAgICAgIEFib3J0U2lnbmFsLnRpbWVvdXQoZGVwcy5idWRnZXRzPy5wcm92aWRlck1zID8/IDI1MDApLFxuICAgICAgICBdKTtcbiAgICAgICAgY29uc3QgcmVzcG9uc2UgPSBhd2FpdCBiZWZvcmVEZWFkbGluZShcbiAgICAgICAgICBkZXBzLmZldGNoKFxuICAgICAgICAgICAgYGh0dHBzOi8vZ3JhcGguZmFjZWJvb2suY29tLyR7dmVyc2lvbn0vJHtwaG9uZUlkfS9tZXNzYWdlc2AsXG4gICAgICAgICAgICB7XG4gICAgICAgICAgICAgIG1ldGhvZDogXCJQT1NUXCIsXG4gICAgICAgICAgICAgIHJlZGlyZWN0OiBcImVycm9yXCIsXG4gICAgICAgICAgICAgIHNpZ25hbDogcHJvdmlkZXJEZWFkbGluZSxcbiAgICAgICAgICAgICAgaGVhZGVyczoge1xuICAgICAgICAgICAgICAgIEF1dGhvcml6YXRpb246IGBCZWFyZXIgJHt0b2tlbn1gLFxuICAgICAgICAgICAgICAgIFwiQ29udGVudC1UeXBlXCI6IFwiYXBwbGljYXRpb24vanNvblwiLFxuICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICBib2R5OiBtZXNzYWdlLFxuICAgICAgICAgICAgfSxcbiAgICAgICAgICApLFxuICAgICAgICAgIHByb3ZpZGVyRGVhZGxpbmUsXG4gICAgICAgICk7XG4gICAgICAgIGNvbnN0IHJhdyA9IGF3YWl0IGJlZm9yZURlYWRsaW5lKFxuICAgICAgICAgIGJvdW5kZWRCb2R5KHJlc3BvbnNlLCA2NTUzNiksXG4gICAgICAgICAgcHJvdmlkZXJEZWFkbGluZSxcbiAgICAgICAgKTtcbiAgICAgICAgZXZpZGVuY2VIYXNoID0gYXdhaXQgc2hhMjU2SGV4KGAke3Jlc3BvbnNlLnN0YXR1c31cXG4ke3Jhd31gKTtcbiAgICAgICAgY29uc3QgZGF0YSA9IG9iamVjdFZhbHVlKEpTT04ucGFyc2UocmF3KSk7XG4gICAgICAgIGlmIChcbiAgICAgICAgICByZXNwb25zZS5vayAmJiBBcnJheS5pc0FycmF5KGRhdGEubWVzc2FnZXMpICYmXG4gICAgICAgICAgZGF0YS5tZXNzYWdlcy5sZW5ndGggPT09IDFcbiAgICAgICAgKSB7XG4gICAgICAgICAgY29uc3QgaWQgPSBvYmplY3RWYWx1ZShkYXRhLm1lc3NhZ2VzWzBdKS5pZDtcbiAgICAgICAgICBpZiAoXG4gICAgICAgICAgICB0eXBlb2YgaWQgPT09IFwic3RyaW5nXCIgJiYgaWQubGVuZ3RoID4gMCAmJiBpZC5sZW5ndGggPD0gNTEyICYmXG4gICAgICAgICAgICAhQXJyYXkuZnJvbShpZCkuc29tZSgoYykgPT5cbiAgICAgICAgICAgICAgYy5jaGFyQ29kZUF0KDApIDwgMzIgfHwgYy5jaGFyQ29kZUF0KDApID09PSAxMjdcbiAgICAgICAgICAgIClcbiAgICAgICAgICApIHtcbiAgICAgICAgICAgIHByb3ZpZGVySGFzaCA9IGF3YWl0IHNoYTI1NkhleChpZCk7XG4gICAgICAgICAgICBvdXRjb21lID0gXCJhY2NlcHRlZFwiO1xuICAgICAgICAgIH1cbiAgICAgICAgfVxuICAgICAgfSBjYXRjaCB7IC8qIE5vIHByb3ZpZGVyIGJvZHkvZXhjZXB0aW9uIGlzIGV4cG9zZWQgb3IgbG9nZ2VkLiAqLyB9XG4gICAgICBjb25zdCByZXN1bHQgPSBhd2FpdCBycGMoXCJyZWNvcmRfc2lnbmVkX290cF92M1wiLCB7XG4gICAgICAgIC4uLmlkZW50aXR5LFxuICAgICAgICBwX2F0dGVtcHRfaWQ6IHN0YXJ0LmF0dGVtcHRfaWQsXG4gICAgICAgIHBfcmV2aXNpb246IHN0YXJ0LnJldmlzaW9uLFxuICAgICAgICBwX291dGNvbWU6IG91dGNvbWUsXG4gICAgICAgIHBfcHJvdmlkZXJfbWVzc2FnZV9oYXNoOiBwcm92aWRlckhhc2gsXG4gICAgICAgIHBfZXZpZGVuY2Vfc2hhMjU2OiBldmlkZW5jZUhhc2gsXG4gICAgICB9KTtcbiAgICAgIGlmIChyZXN1bHQuZXJyb3IpIHRocm93IHVucmVzb2x2ZWQoKTtcbiAgICAgIGNvbnN0IGNvbXBsZXRlZCA9IG90cFJlY2VpcHQocmVzdWx0LmRhdGEsIHZlcmlmaWVkLmlkLCBwYXlsb2FkSGFzaCk7XG4gICAgICBpZiAoXG4gICAgICAgIGNvbXBsZXRlZC5hdHRlbXB0X2lkICE9PSBzdGFydC5hdHRlbXB0X2lkIHx8IGNvbXBsZXRlZC5jYW5fc2VuZCB8fFxuICAgICAgICBjb21wbGV0ZWQucmV2aXNpb24gPCBzdGFydC5yZXZpc2lvbiArIDFcbiAgICAgICkgdGhyb3cgdW5yZXNvbHZlZCgpO1xuICAgICAgLy8gQSByZWNvdmVyeSBtYXkgYWxyZWFkeSBoYXZlIHByb3ZlZCBkZWxpdmVyeTsgbmVpdGhlciBwYXRoIHJlc2VuZHMuXG4gICAgICBpZiAoXG4gICAgICAgIG91dGNvbWUgPT09IFwiYWNjZXB0ZWRcIiAmJlxuICAgICAgICAoY29tcGxldGVkLnN0YXRlID09PSBcImFjY2VwdGVkXCIgfHwgY29tcGxldGVkLnN0YXRlID09PSBcImRlbGl2ZXJlZFwiKVxuICAgICAgKSByZXR1cm4ganNvblJlc3BvbnNlKHt9KTtcbiAgICAgIHRocm93IG5ldyBQdWJsaWNFcnJvcihcIm90cF9kZWxpdmVyeV91bnJlc29sdmVkXCIsIDUwMyk7XG4gICAgfSBjYXRjaCAoZXJyb3IpIHtcbiAgICAgIC8vIE9ubHkgbGl0ZXJhbCBjb2RlcyBmcm9tIHRoaXMgYm91bmRhcnkvc2hhcmVkIHZhbGlkYXRvcnMgYXJlIHB1YmxpYy5cbiAgICAgIC8vIEV2ZW4gYSBkZXBlbmRlbmN5IHRocm93aW5nIGEgZm9yZ2VkIFB1YmxpY0Vycm9yIGNhbm5vdCBkaXNjbG9zZSB0ZXh0LlxuICAgICAgY29uc3QgYWxsb3dlZCA9IG5ldyBNYXA8c3RyaW5nLCBudW1iZXI+KFtcbiAgICAgICAgW1wiaW52YWxpZF9ob29rX3NpZ25hdHVyZVwiLCA0MDFdLFxuICAgICAgICBbXCJob29rX2NvbmZpZ3VyYXRpb25fdW5hdmFpbGFibGVcIiwgNTAzXSxcbiAgICAgICAgW1wicGF5bG9hZF90b29fbGFyZ2VcIiwgNDEzXSxcbiAgICAgICAgW1wiaW52YWxpZF91dGY4XCIsIDQwMF0sXG4gICAgICAgIFtcImludmFsaWRfaG9va19wYXlsb2FkXCIsIDQwMF0sXG4gICAgICAgIFtcImludmFsaWRfcGF5bG9hZFwiLCA0MDBdLFxuICAgICAgICBbXCJpbnZhbGlkX290cF9wYXlsb2FkXCIsIDQwMF0sXG4gICAgICAgIFtcIm90cF9jb25maWd1cmF0aW9uX3VuYXZhaWxhYmxlXCIsIDUwM10sXG4gICAgICAgIFtcIm90cF9yZXNlcnZhdGlvbl91bmF2YWlsYWJsZVwiLCA1MDNdLFxuICAgICAgICBbXCJvdHBfcmF0ZV9saW1pdGVkXCIsIDQyOV0sXG4gICAgICAgIFtcIm90cF9ub3Rfc2VudFwiLCA1MDJdLFxuICAgICAgICBbXCJvdHBfZGVsaXZlcnlfZmFpbGVkXCIsIDUwMl0sXG4gICAgICAgIFtcIm90cF9leHBpcmVkXCIsIDUwMl0sXG4gICAgICAgIFtcIm90cF9kZWxpdmVyeV91bnJlc29sdmVkXCIsIDUwM10sXG4gICAgICBdKTtcbiAgICAgIGNvbnN0IGNvZGUgPSBlcnJvciBpbnN0YW5jZW9mIFB1YmxpY0Vycm9yICYmIGFsbG93ZWQuaGFzKGVycm9yLmNvZGUpXG4gICAgICAgID8gZXJyb3IuY29kZVxuICAgICAgICA6IFwic2VydmljZV91bmF2YWlsYWJsZVwiO1xuICAgICAgcmV0dXJuIGhvb2tFcnJvcihjb2RlLCBhbGxvd2VkLmdldChjb2RlKSA/PyA1MDMpO1xuICAgIH1cbiAgfTtcbn1cbiJdLCJuYW1lcyI6W10sIm1hcHBpbmdzIjoiQUFBQSxTQUFTLFdBQVcsRUFBRSxZQUFZLFFBQVEscUJBQXFCO0FBQy9ELFNBQVMsU0FBUyxFQUFFLG9CQUFvQixFQUFFLFNBQVMsUUFBUSxxQkFBcUI7QUFDaEYsU0FBUyxhQUFhLFFBQVEsZ0NBQWdDO0FBQzlELFNBQ0UsV0FBVyxFQUNYLFdBQVcsRUFDWCxXQUFXLEVBQ1gsTUFBTSxFQUNOLElBQUksUUFDQyxvQ0FBb0M7QUFrQzNDLE1BQU0sU0FBUyxJQUFJLElBQWM7RUFDL0I7RUFDQTtFQUNBO0VBQ0E7RUFDQTtFQUNBO0VBQ0E7RUFDQTtDQUNEO0FBQ0QsTUFBTSxhQUFhLElBQU0sSUFBSSxZQUFZLDJCQUEyQjtBQUVwRSw4RUFBOEUsR0FDOUUsT0FBTyxTQUFTLFdBQ2QsS0FBYyxFQUNkLEVBQVUsRUFDVixJQUFZO0VBRVosSUFBSTtFQUNKLElBQUk7SUFDRixJQUFJLFlBQVk7RUFDbEIsRUFBRSxPQUFNO0lBQ04sTUFBTTtFQUNSO0VBQ0EsSUFDRSxFQUFFLGdCQUFnQixLQUFLLEtBQUssRUFBRSxPQUFPLEtBQUssTUFBTSxFQUFF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
// denoCacheMetadata=3717890637540055424,13116527188605071860