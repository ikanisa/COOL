import { corsHeaders, jsonResponse } from "../_shared/cors.ts";
import { hashPhone, normalizeRwandaPhone, sha256Hex } from "../_shared/hash.ts";
import { verifySmsHook } from "../_shared/signed_sms_hook.ts";
import {
  boundedBody,
  objectValue,
  PublicError,
  SHA256,
  UUID,
} from "../_shared/production_contract.ts";

type RpcResult = { data: unknown; error: unknown };
type RpcQuery = PromiseLike<RpcResult> & {
  abortSignal?(signal: AbortSignal): PromiseLike<RpcResult>;
};
export interface OtpDependencies {
  env(name: string): string | undefined;
  service(): {
    rpc(name: string, args: Record<string, unknown>): RpcQuery;
  };
  fetch(url: string, init: RequestInit): Promise<Response>;
  now(): number;
  /** Optional shorter budgets for local timeout tests; production defaults are fixed. */
  budgets?: { totalMs: number; providerMs: number };
}
export type OtpState =
  | "reserved"
  | "sending"
  | "accepted"
  | "delivered"
  | "not_sent"
  | "failed"
  | "ambiguous"
  | "expired";
export type OtpReceipt = {
  contract_version: 3;
  hook_id: string;
  payload_hash: string;
  attempt_id: string;
  state: OtpState;
  revision: number;
  can_send: boolean;
};
const states = new Set<OtpState>([
  "reserved",
  "sending",
  "accepted",
  "delivered",
  "not_sent",
  "failed",
  "ambiguous",
  "expired",
]);
const unresolved = () => new PublicError("otp_delivery_unresolved", 503);

/** Exact durable identity is required before a hook may send or acknowledge. */
export function otpReceipt(
  value: unknown,
  id: string,
  hash: string,
): OtpReceipt {
  let r: Record<string, unknown>;
  try {
    r = objectValue(value);
  } catch {
    throw unresolved();
  }
  if (
    r.contract_version !== 3 || r.hook_id !== id || r.payload_hash !== hash ||
    !SHA256.test(hash) || typeof r.attempt_id !== "string" ||
    !UUID.test(r.attempt_id) ||
    typeof r.state !== "string" || !states.has(r.state as OtpState) ||
    !Number.isSafeInteger(r.revision) || (r.revision as number) < 1 ||
    typeof r.can_send !== "boolean" ||
    (r.can_send && r.state !== "reserved")
  ) throw unresolved();
  return r as OtpReceipt;
}

function beforeDeadline<T>(
  promise: PromiseLike<T>,
  signal: AbortSignal,
): Promise<T> {
  return new Promise((resolve, reject) => {
    if (signal.aborted) {
      reject(unresolved());
      return;
    }
    const abort = () => reject(unresolved());
    signal.addEventListener("abort", abort, { once: true });
    Promise.resolve(promise).then(resolve, reject).finally(() =>
      signal.removeEventListener("abort", abort)
    );
  });
}
function hookError(code: string, status: number): Response {
  return jsonResponse({ error: { http_code: status, message: code } }, status);
}

function required(deps: OtpDependencies, name: string): string {
  const value = deps.env(name)?.trim();
  if (!value) throw new PublicError("otp_configuration_unavailable", 503);
  return value;
}
function terminal(state: OtpState): never {
  if (state === "not_sent") throw new PublicError("otp_not_sent", 502);
  if (state === "failed") throw new PublicError("otp_delivery_failed", 502);
  if (state === "expired") throw new PublicError("otp_expired", 502);
  throw unresolved();
}

export function createOtpHandler(deps: OtpDependencies) {
  return async (req: Request): Promise<Response> => {
    if (req.method === "OPTIONS") {
      return new Response("ok", { headers: corsHeaders });
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
      const verified = await beforeDeadline(
        verifySmsHook(req, [
          required(deps, "SEND_SMS_HOOK_SECRET"),
          ...(previous ? [previous] : []),
        ], Math.floor(deps.now() / 1000)),
        deadline,
      );
      const phone = normalizeRwandaPhone(
        objectValue(verified.payload.user).phone as string,
      );
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
      if (
        !/^v\d{1,3}\.0$/.test(version) || !/^\d{1,32}$/.test(phoneId) ||
        !["true", "false"].includes(button) || template.length > 512 ||
        language.length > 32
      ) {
        throw new PublicError("otp_configuration_unavailable", 503);
      }
      const components: Array<Record<string, unknown>> = [{
        type: "body",
        parameters: [{ type: "text", text: otp }],
      }];
      if (button === "true") {
        components.push({
          type: "button",
          sub_type: "url",
          index: "0",
          parameters: [{ type: "text", text: otp }],
        });
      }
      const message = JSON.stringify({
        messaging_product: "whatsapp",
        to: phone.slice(1),
        type: "template",
        template: { name: template, language: { code: language }, components },
      });
      const service = deps.service();
      const rpc = (name: string, args: Record<string, unknown>) => {
        if (deadline.aborted) throw unresolved();
        const query = service.rpc(name, args);
        return beforeDeadline(
          query.abortSignal ? query.abortSignal(deadline) : query,
          deadline,
        );
      };
      const payloadHash = await sha256Hex(verified.body);
      const identity = { p_hook_id: verified.id, p_payload_hash: payloadHash };
      const reserve = await rpc("reserve_signed_otp_v3", {
        ...identity,
        p_phone_hash: await hashPhone(phone),
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
        p_revision: receipt.revision,
      });
      if (begun.error) throw unresolved();
      const start = otpReceipt(begun.data, verified.id, payloadHash);
      const started = objectValue(begun.data).started;
      if (
        started !== true || start.attempt_id !== receipt.attempt_id ||
        start.state !== "sending" || start.revision !== receipt.revision + 1 ||
        start.can_send
      ) {
        // Another signed invocation may have completed while this one waited.
        if (
          started === false && start.attempt_id === receipt.attempt_id &&
          (start.state === "accepted" || start.state === "delivered")
        ) return jsonResponse({});
        throw unresolved();
      }

      // Once begin is durable, every transport failure is ambiguous. HTTP errors
      // and AbortSignal are not proof that the provider did not accept a request.
      let outcome: "accepted" | "ambiguous" = "ambiguous";
      let providerHash: string | null = null;
      let evidenceHash = await sha256Hex("transport_outcome_unobserved_v3");
      try {
        const providerDeadline = AbortSignal.any([
          deadline,
          AbortSignal.timeout(deps.budgets?.providerMs ?? 2500),
        ]);
        const response = await beforeDeadline(
          deps.fetch(
            `https://graph.facebook.com/${version}/${phoneId}/messages`,
            {
              method: "POST",
              redirect: "error",
              signal: providerDeadline,
              headers: {
                Authorization: `Bearer ${token}`,
                "Content-Type": "application/json",
              },
              body: message,
            },
          ),
          providerDeadline,
        );
        const raw = await beforeDeadline(
          boundedBody(response, 65536),
          providerDeadline,
        );
        evidenceHash = await sha256Hex(`${response.status}\n${raw}`);
        const data = objectValue(JSON.parse(raw));
        if (
          response.ok && Array.isArray(data.messages) &&
          data.messages.length === 1
        ) {
          const id = objectValue(data.messages[0]).id;
          if (
            typeof id === "string" && id.length > 0 && id.length <= 512 &&
            !Array.from(id).some((c) =>
              c.charCodeAt(0) < 32 || c.charCodeAt(0) === 127
            )
          ) {
            providerHash = await sha256Hex(id);
            outcome = "accepted";
          }
        }
      } catch { /* No provider body/exception is exposed or logged. */ }
      const result = await rpc("record_signed_otp_v3", {
        ...identity,
        p_attempt_id: start.attempt_id,
        p_revision: start.revision,
        p_outcome: outcome,
        p_provider_message_hash: providerHash,
        p_evidence_sha256: evidenceHash,
      });
      if (result.error) throw unresolved();
      const completed = otpReceipt(result.data, verified.id, payloadHash);
      if (
        completed.attempt_id !== start.attempt_id || completed.can_send ||
        completed.revision < start.revision + 1
      ) throw unresolved();
      // A recovery may already have proved delivery; neither path resends.
      if (
        outcome === "accepted" &&
        (completed.state === "accepted" || completed.state === "delivered")
      ) return jsonResponse({});
      throw new PublicError("otp_delivery_unresolved", 503);
    } catch (error) {
      // Only literal codes from this boundary/shared validators are public.
      // Even a dependency throwing a forged PublicError cannot disclose text.
      const allowed = new Map<string, number>([
        ["invalid_hook_signature", 401],
        ["hook_configuration_unavailable", 503],
        ["payload_too_large", 413],
        ["invalid_utf8", 400],
        ["invalid_hook_payload", 400],
        ["invalid_payload", 400],
        ["invalid_otp_payload", 400],
        ["otp_configuration_unavailable", 503],
        ["otp_reservation_unavailable", 503],
        ["otp_rate_limited", 429],
        ["otp_not_sent", 502],
        ["otp_delivery_failed", 502],
        ["otp_expired", 502],
        ["otp_delivery_unresolved", 503],
      ]);
      const code = error instanceof PublicError && allowed.has(error.code)
        ? error.code
        : "service_unavailable";
      return hookError(code, allowed.get(code) ?? 503);
    }
  };
}
