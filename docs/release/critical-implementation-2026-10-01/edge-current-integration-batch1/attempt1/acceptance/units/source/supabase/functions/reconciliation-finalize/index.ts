import { serviceClient, userClient } from "../_shared/supabase.ts";
import { reconciliationHandler } from "./handler.ts";

Deno.serve(reconciliationHandler({
  authorize: async (authorization, reviewId) => {
    // PostgREST verifies the caller JWT; the RPC checks its current Auth
    // session, AAL2, approved identity, role and exact recorded checker.
    return await userClient(authorization).rpc(
      "authorize_reconciliation_finalization_v2",
      { p_review_id: reviewId },
    ).abortSignal(AbortSignal.timeout(8000));
  },
  finalize: async (reviewId) => {
    return await serviceClient().rpc("finalize_approved_reconciliation_v2", {
      p_review_id: reviewId,
    }).abortSignal(AbortSignal.timeout(8000));
  },
}));
