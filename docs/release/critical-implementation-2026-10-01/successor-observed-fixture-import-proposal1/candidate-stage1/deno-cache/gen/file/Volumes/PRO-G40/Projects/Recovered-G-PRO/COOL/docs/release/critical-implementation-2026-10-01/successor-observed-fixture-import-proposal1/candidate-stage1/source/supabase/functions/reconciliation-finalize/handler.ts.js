import { corsHeaders, jsonResponse } from "../_shared/cors.ts";
import { boundedJson, objectValue, PublicError, publicFailure, uuid } from "../_shared/production_contract.ts";
function checked(result) {
  if (!result.error) return result.data;
  if ([
    "PGRST301",
    "PGRST302",
    "PGRST303"
  ].includes(result.error.code ?? "")) {
    throw new PublicError("authentication_required", 401);
  }
  if (result.error.code === "42501") {
    if ([
      "reconciliation_step_up_required",
      "reconciliation_actor_unavailable",
      "reconciliation_approver_required"
    ].includes(result.error.message ?? "")) {
      throw new PublicError(result.error.message, 403);
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
 * under locks; this authorization read alone never permits financial posting. */ export function reconciliationHandler(deps) {
  return async (request)=>{
    if (request.method === "OPTIONS") {
      return new Response("ok", {
        headers: corsHeaders
      });
    }
    if (request.method !== "POST") {
      return jsonResponse({
        error: "method_not_allowed"
      }, 405);
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
      let result;
      try {
        result = objectValue(data);
      } catch  {
        throw new PublicError("reconciliation_unavailable", 503);
      }
      if (result.review_id !== reviewId || typeof result.replayed !== "boolean" || result.evidence_level !== "independently_reconciled" || ![
        "posted",
        "reversed"
      ].includes(String(result.payment_status)) || result.replayed === false && result.payment_status !== "posted") {
        throw new PublicError("reconciliation_unavailable", 503);
      }
      let paymentId;
      try {
        paymentId = uuid(result.payment_id, "invalid_payment_id");
      } catch  {
        throw new PublicError("reconciliation_unavailable", 503);
      }
      return jsonResponse({
        review_id: reviewId,
        payment_id: paymentId,
        payment_status: result.payment_status,
        replayed: result.replayed,
        evidence_level: result.evidence_level
      });
    } catch (error) {
      const failure = publicFailure(error);
      return jsonResponse({
        error: failure.error
      }, failure.status);
    }
  };
}
//# sourceMappingURL=data:application/json;base64,eyJ2ZXJzaW9uIjozLCJzb3VyY2VzIjpbImZpbGU6Ly8vVm9sdW1lcy9QUk8tRzQwL1Byb2plY3RzL1JlY292ZXJlZC1HLVBSTy9DT09ML2RvY3MvcmVsZWFzZS9jcml0aWNhbC1pbXBsZW1lbnRhdGlvbi0yMDI2LTEwLTAxL3N1Y2Nlc3Nvci1vYnNlcnZlZC1maXh0dXJlLWltcG9ydC1wcm9wb3NhbDEvY2FuZGlkYXRlLXN0YWdlMS9zb3VyY2Uvc3VwYWJhc2UvZnVuY3Rpb25zL3JlY29uY2lsaWF0aW9uLWZpbmFsaXplL2hhbmRsZXIudHMiXSwic291cmNlc0NvbnRlbnQiOlsiaW1wb3J0IHsgY29yc0hlYWRlcnMsIGpzb25SZXNwb25zZSB9IGZyb20gXCIuLi9fc2hhcmVkL2NvcnMudHNcIjtcbmltcG9ydCB7XG4gIGJvdW5kZWRKc29uLFxuICBvYmplY3RWYWx1ZSxcbiAgUHVibGljRXJyb3IsXG4gIHB1YmxpY0ZhaWx1cmUsXG4gIHV1aWQsXG59IGZyb20gXCIuLi9fc2hhcmVkL3Byb2R1Y3Rpb25fY29udHJhY3QudHNcIjtcblxuZXhwb3J0IHR5cGUgUnBjUmVzdWx0ID0ge1xuICBkYXRhOiB1bmtub3duO1xuICBlcnJvcjogeyBjb2RlPzogc3RyaW5nOyBtZXNzYWdlPzogc3RyaW5nIH0gfCBudWxsO1xufTtcbmV4cG9ydCB0eXBlIFJlY29uY2lsaWF0aW9uRGVwZW5kZW5jaWVzID0ge1xuICBhdXRob3JpemU6IChhdXRob3JpemF0aW9uOiBzdHJpbmcsIHJldmlld0lkOiBzdHJpbmcpID0+IFByb21pc2U8UnBjUmVzdWx0PjtcbiAgZmluYWxpemU6IChyZXZpZXdJZDogc3RyaW5nKSA9PiBQcm9taXNlPFJwY1Jlc3VsdD47XG59O1xuXG5mdW5jdGlvbiBjaGVja2VkKHJlc3VsdDogUnBjUmVzdWx0KTogdW5rbm93biB7XG4gIGlmICghcmVzdWx0LmVycm9yKSByZXR1cm4gcmVzdWx0LmRhdGE7XG4gIGlmIChbXCJQR1JTVDMwMVwiLCBcIlBHUlNUMzAyXCIsIFwiUEdSU1QzMDNcIl0uaW5jbHVkZXMocmVzdWx0LmVycm9yLmNvZGUgPz8gXCJcIikpIHtcbiAgICB0aHJvdyBuZXcgUHVibGljRXJyb3IoXCJhdXRoZW50aWNhdGlvbl9yZXF1aXJlZFwiLCA0MDEpO1xuICB9XG4gIGlmIChyZXN1bHQuZXJyb3IuY29kZSA9PT0gXCI0MjUwMVwiKSB7XG4gICAgaWYgKFxuICAgICAgW1xuICAgICAgICBcInJlY29uY2lsaWF0aW9uX3N0ZXBfdXBfcmVxdWlyZWRcIixcbiAgICAgICAgXCJyZWNvbmNpbGlhdGlvbl9hY3Rvcl91bmF2YWlsYWJsZVwiLFxuICAgICAgICBcInJlY29uY2lsaWF0aW9uX2FwcHJvdmVyX3JlcXVpcmVkXCIsXG4gICAgICBdLmluY2x1ZGVzKHJlc3VsdC5lcnJvci5tZXNzYWdlID8/IFwiXCIpXG4gICAgKSB7XG4gICAgICB0aHJvdyBuZXcgUHVibGljRXJyb3IocmVzdWx0LmVycm9yLm1lc3NhZ2UhLCA0MDMpO1xuICAgIH1cbiAgICB0aHJvdyBuZXcgUHVibGljRXJyb3IoXCJyZWNvbmNpbGlhdGlvbl9wZXJtaXNzaW9uX3JlcXVpcmVkXCIsIDQwMyk7XG4gIH1cbiAgaWYgKHJlc3VsdC5lcnJvci5jb2RlID09PSBcIjIyMDIzXCIpIHtcbiAgICB0aHJvdyBuZXcgUHVibGljRXJyb3IoXCJyZWNvbmNpbGlhdGlvbl9jb25mbGljdFwiLCA0MDkpO1xuICB9XG4gIHRocm93IG5ldyBQdWJsaWNFcnJvcihcInJlY29uY2lsaWF0aW9uX3VuYXZhaWxhYmxlXCIsIDUwMyk7XG59XG5cbi8qKiBUaGUgY2FsbGVyIG11c3QgYmUgdGhlIHNhbWUgbGl2ZSBBQUwyIGNoZWNrZXIgc2Vzc2lvbiB0aGF0IGFwcHJvdmVkIHRoZVxuICogcmV2aWV3LiBUaGUgc2VydmljZSBSUEMgaW5kZXBlbmRlbnRseSByZWNoZWNrcyBib3RoIHJlY29yZGVkIGFjdG9ycy9zZXNzaW9uc1xuICogdW5kZXIgbG9ja3M7IHRoaXMgYXV0aG9yaXphdGlvbiByZWFkIGFsb25lIG5ldmVyIHBlcm1pdHMgZmluYW5jaWFsIHBvc3RpbmcuICovXG5leHBvcnQgZnVuY3Rpb24gcmVjb25jaWxpYXRpb25IYW5kbGVyKGRlcHM6IFJlY29uY2lsaWF0aW9uRGVwZW5kZW5jaWVzKSB7XG4gIHJldHVybiBhc3luYyAocmVxdWVzdDogUmVxdWVzdCk6IFByb21pc2U8UmVzcG9uc2U+ID0+IHtcbiAgICBpZiAocmVxdWVzdC5tZXRob2QgPT09IFwiT1BUSU9OU1wiKSB7XG4gICAgICByZXR1cm4gbmV3IFJlc3BvbnNlKFwib2tcIiwgeyBoZWFkZXJzOiBjb3JzSGVhZGVycyB9KTtcbiAgICB9XG4gICAgaWYgKHJlcXVlc3QubWV0aG9kICE9PSBcIlBPU1RcIikge1xuICAgICAgcmV0dXJuIGpzb25SZXNwb25zZSh7IGVycm9yOiBcIm1ldGhvZF9ub3RfYWxsb3dlZFwiIH0sIDQwNSk7XG4gICAgfVxuICAgIHRyeSB7XG4gICAgICBjb25zdCBhdXRob3JpemF0aW9uID0gcmVxdWVzdC5oZWFkZXJzLmdldChcImF1dGhvcml6YXRpb25cIikgPz8gXCJcIjtcbiAgICAgIGlmICghL15CZWFyZXIgXFxTKyQvaS50ZXN0KGF1dGhvcml6YXRpb24pIHx8IGF1dGhvcml6YXRpb24ubGVuZ3RoID4gODE5Mikge1xuICAgICAgICB0aHJvdyBuZXcgUHVibGljRXJyb3IoXCJhdXRoZW50aWNhdGlvbl9yZXF1aXJlZFwiLCA0MDEpO1xuICAgICAgfVxuICAgICAgY29uc3QgcGF5bG9hZCA9IGF3YWl0IGJvdW5kZWRKc29uKHJlcXVlc3QsIDIwNDgpO1xuICAgICAgaWYgKE9iamVjdC5rZXlzKHBheWxvYWQpLmxlbmd0aCAhPT0gMSB8fCAhKFwicmV2aWV3X2lkXCIgaW4gcGF5bG9hZCkpIHtcbiAgICAgICAgdGhyb3cgbmV3IFB1YmxpY0Vycm9yKFwiaW52YWxpZF9yZWNvbmNpbGlhdGlvbl9yZXF1ZXN0XCIpO1xuICAgICAgfVxuICAgICAgY29uc3QgcmV2aWV3SWQgPSB1dWlkKHBheWxvYWQucmV2aWV3X2lkLCBcImludmFsaWRfcmV2aWV3X2lkXCIpO1xuICAgICAgaWYgKGNoZWNrZWQoYXdhaXQgZGVwcy5hdXRob3JpemUoYXV0aG9yaXphdGlvbiwgcmV2aWV3SWQpKSAhPT0gdHJ1ZSkge1xuICAgICAgICB0aHJvdyBuZXcgUHVibGljRXJyb3IoXCJyZWNvbmNpbGlhdGlvbl9wZXJtaXNzaW9uX3JlcXVpcmVkXCIsIDQwMyk7XG4gICAgICB9XG4gICAgICBjb25zdCBkYXRhID0gY2hlY2tlZChhd2FpdCBkZXBzLmZpbmFsaXplKHJldmlld0lkKSk7XG4gICAgICBsZXQgcmVzdWx0OiBSZWNvcmQ8c3RyaW5nLCB1bmtub3duPjtcbiAgICAgIHRyeSB7XG4gICAgICAgIHJlc3VsdCA9IG9iamVjdFZhbHVlKGRhdGEpO1xuICAgICAgfSBjYXRjaCB7XG4gICAgICAgIHRocm93IG5ldyBQdWJsaWNFcnJvcihcInJlY29uY2lsaWF0aW9uX3VuYXZhaWxhYmxlXCIsIDUwMyk7XG4gICAgICB9XG4gICAgICBpZiAoXG4gICAgICAgIHJlc3VsdC5yZXZpZXdfaWQgIT09IHJldmlld0lkIHx8IHR5cGVvZiByZXN1bHQucmVwbGF5ZWQgIT09IFwiYm9vbGVhblwiIHx8XG4gICAgICAgIHJlc3VsdC5ldmlkZW5jZV9sZXZlbCAhPT0gXCJpbmRlcGVuZGVudGx5X3JlY29uY2lsZWRcIiB8fFxuICAgICAgICAhW1wicG9zdGVkXCIsIFwicmV2ZXJzZWRcIl0uaW5jbHVkZXMoU3RyaW5nKHJlc3VsdC5wYXltZW50X3N0YXR1cykpIHx8XG4gICAgICAgIChyZXN1bHQucmVwbGF5ZWQgPT09IGZhbHNlICYmIHJlc3VsdC5wYXltZW50X3N0YXR1cyAhPT0gXCJwb3N0ZWRcIilcbiAgICAgICkge1xuICAgICAgICB0aHJvdyBuZXcgUHVibGljRXJyb3IoXCJyZWNvbmNpbGlhdGlvbl91bmF2YWlsYWJsZVwiLCA1MDMpO1xuICAgICAgfVxuICAgICAgbGV0IHBheW1lbnRJZDogc3RyaW5nO1xuICAgICAgdHJ5IHtcbiAgICAgICAgcGF5bWVudElkID0gdXVpZChyZXN1bHQucGF5bWVudF9pZCwgXCJpbnZhbGlkX3BheW1lbnRfaWRcIik7XG4gICAgICB9IGNhdGNoIHtcbiAgICAgICAgdGhyb3cgbmV3IFB1YmxpY0Vycm9yKFwicmVjb25jaWxpYXRpb25fdW5hdmFpbGFibGVcIiwgNTAzKTtcbiAgICAgIH1cbiAgICAgIHJldHVybiBqc29uUmVzcG9uc2Uoe1xuICAgICAgICByZXZpZXdfaWQ6IHJldmlld0lkLFxuICAgICAgICBwYXltZW50X2lkOiBwYXltZW50SWQsXG4gICAgICAgIHBheW1lbnRfc3RhdHVzOiByZXN1bHQucGF5bWVudF9zdGF0dXMsXG4gICAgICAgIHJlcGxheWVkOiByZXN1bHQucmVwbGF5ZWQsXG4gICAgICAgIGV2aWRlbmNlX2xldmVsOiByZXN1bHQuZXZpZGVuY2VfbGV2ZWwsXG4gICAgICB9KTtcbiAgICB9IGNhdGNoIChlcnJvcikge1xuICAgICAgY29uc3QgZmFpbHVyZSA9IHB1YmxpY0ZhaWx1cmUoZXJyb3IpO1xuICAgICAgcmV0dXJuIGpzb25SZXNwb25zZSh7IGVycm9yOiBmYWlsdXJlLmVycm9yIH0sIGZhaWx1cmUuc3RhdHVzKTtcbiAgICB9XG4gIH07XG59XG4iXSwibmFtZXMiOltdLCJtYXBwaW5ncyI6IkFBQUEsU0FBUyxXQUFXLEVBQUUsWUFBWSxRQUFRLHFCQUFxQjtBQUMvRCxTQUNFLFdBQVcsRUFDWCxXQUFXLEVBQ1gsV0FBVyxFQUNYLGFBQWEsRUFDYixJQUFJLFFBQ0Msb0NBQW9DO0FBVzNDLFNBQVMsUUFBUSxNQUFpQjtFQUNoQyxJQUFJLENBQUMsT0FBTyxLQUFLLEVBQUUsT0FBTyxPQUFPLElBQUk7RUFDckMsSUFBSTtJQUFDO0lBQVk7SUFBWTtHQUFXLENBQUMsUUFBUSxDQUFDLE9BQU8sS0FBSyxDQUFDLElBQUksSUFBSSxLQUFLO0lBQzFFLE1BQU0sSUFBSSxZQUFZLDJCQUEyQjtFQUNuRDtFQUNBLElBQUksT0FBTyxLQUFLLENBQUMsSUFBSSxLQUFLLFNBQVM7SUFDakMsSUFDRTtNQUNFO01B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
// denoCacheMetadata=13392718952919915010,8105689268620871133