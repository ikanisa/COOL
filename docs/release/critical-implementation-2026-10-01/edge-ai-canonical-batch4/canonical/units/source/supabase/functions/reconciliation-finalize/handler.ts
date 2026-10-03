import { corsHeaders, jsonResponse } from "../_shared/cors.ts";
import {
  boundedJson,
  objectValue,
  PublicError,
  publicFailure,
  uuid,
} from "../_shared/production_contract.ts";

export type RpcResult = {
  data: unknown;
  error: { code?: string; message?: string } | null;
};
export type ReconciliationDependencies = {
  authorize: (authorization: string, reviewId: string) => Promise<RpcResult>;
  finalize: (reviewId: string) => Promise<RpcResult>;
};

function checked(result: RpcResult): unknown {
  if (!result.error) return result.data;
  if (["PGRST301", "PGRST302", "PGRST303"].includes(result.error.code ?? "")) {
    throw new PublicError("authentication_required", 401);
  }
  if (result.error.code === "42501") {
    if (
      [
        "reconciliation_step_up_required",
        "reconciliation_actor_unavailable",
        "reconciliation_approver_required",
      ].includes(result.error.message ?? "")
    ) {
      throw new PublicError(result.error.message!, 403);
    }
    throw new PublicError("reconciliation_permission_required", 403);
  }
  if (result.error.code === "22023") {
    throw new PublicError("reconciliation_conflict", 409);
  }
  throw new PublicError("reconciliation_unavailable", 503);
}

/** The caller must be the same live AAL2 checker session that approved the
 * review. The service RPC independently rechecks both recorded actors/sessions
 * under locks; this authorization read alone never permits financial posting. */
export function reconciliationHandler(deps: ReconciliationDependencies) {
  return async (request: Request): Promise<Response> => {
    if (request.method === "OPTIONS") {
      return new Response("ok", { headers: corsHeaders });
    }
    if (request.method !== "POST") {
      return jsonResponse({ error: "method_not_allowed" }, 405);
    }
    try {
      const authorization = request.headers.get("authorization") ?? "";
      if (!/^Bearer \S+$/i.test(authorization) || authorization.length > 8192) {
        throw new PublicError("authentication_required", 401);
      }
      const payload = await boundedJson(request, 2048);
      if (Object.keys(payload).length !== 1 || !("review_id" in payload)) {
        throw new PublicError("invalid_reconciliation_request");
      }
      const reviewId = uuid(payload.review_id, "invalid_review_id");
      if (checked(await deps.authorize(authorization, reviewId)) !== true) {
        throw new PublicError("reconciliation_permission_required", 403);
      }
      const data = checked(await deps.finalize(reviewId));
      let result: Record<string, unknown>;
      try {
        result = objectValue(data);
      } catch {
        throw new PublicError("reconciliation_unavailable", 503);
      }
      if (
        result.review_id !== reviewId || typeof result.replayed !== "boolean" ||
        result.evidence_level !== "independently_reconciled" ||
        !["posted", "reversed"].includes(String(result.payment_status)) ||
        (result.replayed === false && result.payment_status !== "posted")
      ) {
        throw new PublicError("reconciliation_unavailable", 503);
      }
      let paymentId: string;
      try {
        paymentId = uuid(result.payment_id, "invalid_payment_id");
      } catch {
        throw new PublicError("reconciliation_unavailable", 503);
      }
      return jsonResponse({
        review_id: reviewId,
        payment_id: paymentId,
        payment_status: result.payment_status,
        replayed: result.replayed,
        evidence_level: result.evidence_level,
      });
    } catch (error) {
      const failure = publicFailure(error);
      return jsonResponse({ error: failure.error }, failure.status);
    }
  };
}
