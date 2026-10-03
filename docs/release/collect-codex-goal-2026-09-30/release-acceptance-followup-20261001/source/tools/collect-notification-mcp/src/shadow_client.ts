import {boundedJson, resolvedOperationalEnvironment, withinDeadline} from "./operational_client.ts";
import {validatedSupabaseUrl, type FetchLike, type OperatorEnvironment} from "./operator_client.ts";
import {fence, shadowResult, shadowUuid, type ShadowAction} from "./shadow_contract.ts";

const guardReasons: Record<string, string> = {
  shadow_session_required: "SHADOW_SESSION_REQUIRED", shadow_permission_required: "SHADOW_PERMISSION_REQUIRED",
  shadow_request_invalid: "SHADOW_ARGUMENTS_INVALID", shadow_request_conflict: "SHADOW_REQUEST_CONFLICT",
  shadow_run_unavailable: "SHADOW_RUN_UNAVAILABLE", shadow_fence_lost: "SHADOW_FENCE_LOST",
  shadow_lease_expired: "SHADOW_LEASE_EXPIRED", shadow_sample_required: "SHADOW_SAMPLE_REQUIRED",
  shadow_limit_reached: "SHADOW_LIMIT_REACHED", shadow_integrity_unavailable: "SHADOW_INTEGRITY_UNAVAILABLE",
  shadow_snapshot_retry: "SHADOW_RECONCILIATION_REQUIRED",
  shadow_health_stale: "SHADOW_HEALTH_STALE",
};
const guardStates: Record<string, string> = {
  shadow_session_required: "42501", shadow_permission_required: "42501", shadow_request_invalid: "22023",
  shadow_request_conflict: "40001", shadow_run_unavailable: "42501", shadow_fence_lost: "40001",
  shadow_lease_expired: "55000", shadow_sample_required: "55000", shadow_limit_reached: "55000",
  shadow_integrity_unavailable: "55000", shadow_snapshot_retry: "40001",
  shadow_health_stale: "55000",
};
export const shadowSafeCodes = ["SHADOW_SESSION_REQUIRED", "SHADOW_PERMISSION_REQUIRED", "SHADOW_ARGUMENTS_INVALID",
  "SHADOW_REQUEST_CONFLICT", "SHADOW_RUN_UNAVAILABLE", "SHADOW_FENCE_LOST", "SHADOW_LEASE_EXPIRED",
  "SHADOW_SAMPLE_REQUIRED", "SHADOW_LIMIT_REACHED", "SHADOW_INTEGRITY_UNAVAILABLE", "SHADOW_RECONCILIATION_REQUIRED",
  "SHADOW_HEALTH_STALE", "SHADOW_OUTCOME_UNKNOWN", "SHADOW_READ_UNAVAILABLE"] as const;

export async function callShadowRpc(
  action: ShadowAction,
  input: Record<string, unknown>,
  environment?: OperatorEnvironment,
  fetcher: FetchLike = fetch,
  now: () => number = Date.now,
  timeoutMs = 15_000,
) {
  let args: Record<string, unknown>, rpc: string, expected: Record<string, unknown>;
  try {
    if ((action === "begin" || action === "get") && Object.keys(input).length === 1 && Object.hasOwn(input, "request_id")) {
      const requestId = shadowUuid(input.request_id);
      rpc = action === "begin" ? "begin_collect_shadow_run_v1" : "get_collect_shadow_run_v1";
      args = {p_request_id: requestId}; expected = {request_id: requestId};
    } else if ((action === "sample" || action === "complete") && Object.keys(input).length === 2 &&
      Object.hasOwn(input, "run_id") && Object.hasOwn(input, "fence_version")) {
      const runId = shadowUuid(input.run_id), version = fence(input.fence_version);
      rpc = action === "sample" ? "sample_collect_shadow_run_v1" : "finish_collect_shadow_run_v1";
      args = {p_run_id: runId, p_fence_version: version}; expected = {run_id: runId, fence_version: version};
    } else throw new Error();
    if (!Number.isSafeInteger(timeoutMs) || timeoutMs < 1 || timeoutMs > 15_000) throw new Error();
  } catch {throw new Error("SHADOW_ARGUMENTS_INVALID");}
  let resolved: OperatorEnvironment;
  try {resolved = await resolvedOperationalEnvironment(environment, now());}
  catch {throw new Error("SHADOW_SESSION_REQUIRED");}
  const mutation = action !== "get";
  const deadline = new AbortController(), signal = deadline.signal;
  const timer = setTimeout(() => deadline.abort(), timeoutMs);
  try {
    const response = await withinDeadline(fetcher(`${validatedSupabaseUrl(resolved.supabaseUrl)}/rest/v1/rpc/${rpc}`, {
      method: "POST", redirect: "error", cache: "no-store", signal,
      headers: {Authorization: `Bearer ${resolved.accessToken}`, apikey: resolved.anonKey, "Content-Type": "application/json",
        Accept: "application/json", "Accept-Profile": "public", "Content-Profile": "public"}, body: JSON.stringify(args),
    }), signal);
    if (!response.ok || response.redirected) {
      // Interpret only allowlisted guard codes. Never print raw PostgREST text,
      // details, hints or an unrecognized successful/error payload.
      let raw: unknown;
      try {raw = await boundedJson(response, signal);} catch {raw = null;}
      if (raw && typeof raw === "object" && !Array.isArray(raw)) {
        const row = raw as Record<string, unknown>;
        if (typeof row.message === "string" && Object.hasOwn(guardReasons, row.message) && row.code === guardStates[row.message]) {
          throw new Error(guardReasons[row.message]);
        }
        if (row.code === "40001" || row.code === "40P01") throw new Error("SHADOW_RECONCILIATION_REQUIRED");
      }
      if (response.status === 401 || response.status === 403) throw new Error("SHADOW_PERMISSION_REQUIRED");
      throw new Error(mutation ? "SHADOW_OUTCOME_UNKNOWN" : "SHADOW_READ_UNAVAILABLE");
    }
    return shadowResult(action, await boundedJson(response, signal), expected, now());
  } catch (error) {
    if (error instanceof Error && shadowSafeCodes.includes(error.message as typeof shadowSafeCodes[number])) throw error;
    throw new Error(mutation ? "SHADOW_OUTCOME_UNKNOWN" : "SHADOW_READ_UNAVAILABLE");
  } finally {clearTimeout(timer);}
}
