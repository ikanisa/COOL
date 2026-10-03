import { authErrorStatus, corsHeaders, safeErrorMessage } from "../_shared/cors.ts";
import { notificationOperatorCommand, OperatorInputError } from "../_shared/notification_operator.ts";
import { boundedJson, PublicError } from "../_shared/production_contract.ts";
import { requireUser, serviceClient } from "../_shared/supabase.ts";
import { rosterSession } from "../_shared/roster_provenance.ts";
function response(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Cache-Control": "no-store, max-age=0",
      "Content-Type": "application/json",
      "Pragma": "no-cache"
    }
  });
}
function databaseCode(error) {
  if (typeof error !== "object" || error === null || !("code" in error)) {
    return null;
  }
  const code = error.code;
  return typeof code === "string" ? code : null;
}
Deno.serve(async (request)=>{
  if (request.method === "OPTIONS") {
    return new Response("ok", {
      headers: corsHeaders
    });
  }
  if (request.method !== "POST") {
    return response({
      error: "Method not allowed"
    }, 405);
  }
  try {
    const authorization = request.headers.get("authorization");
    const { supabase, user } = await requireUser(authorization);
    // Auth.getUser verifies this exact bearer before claims are decoded. The
    // caller's session is never taken from the action payload or service JWT.
    const caller = rosterSession(authorization, user.id);
    const payload = await boundedJson(request);
    const command = notificationOperatorCommand(payload.action, payload, caller.actorId, caller.sessionId);
    const { data: identity, error: identityError } = await supabase.rpc("admin_current_user");
    if (identityError) throw identityError;
    const permissions = typeof identity === "object" && identity != null && Array.isArray(identity.permissions) ? identity.permissions : [];
    if (!permissions.includes(command.permission)) {
      return response({
        error: "forbidden"
      }, 403);
    }
    const { data, error } = await serviceClient().rpc(command.rpc, command.params);
    if (error) {
      const code = databaseCode(error);
      if (code === "42501") return response({
        error: "forbidden"
      }, 403);
      if (code !== null && [
        "P0001",
        "23505",
        "23514",
        "40001"
      ].includes(code)) {
        return response({
          error: "conflict"
        }, 409);
      }
      throw error;
    }
    return response({
      ok: true,
      action: payload.action,
      result: data
    });
  } catch (error) {
    if (error instanceof PublicError) {
      return response({
        error: error.code
      }, error.status);
    }
    if (error instanceof OperatorInputError) {
      return response({
        error: "invalid_request"
      }, 400);
    }
    return response({
      error: safeErrorMessage(error)
    }, authErrorStatus(error) ?? 503);
  }
});
//# sourceMappingURL=data:application/json;base64,eyJ2ZXJzaW9uIjozLCJzb3VyY2VzIjpbImZpbGU6Ly8vVm9sdW1lcy9QUk8tRzQwL1Byb2plY3RzL1JlY292ZXJlZC1HLVBSTy9DT09ML2RvY3MvcmVsZWFzZS9jcml0aWNhbC1pbXBsZW1lbnRhdGlvbi0yMDI2LTEwLTAxL3N1Y2Nlc3Nvci1vYnNlcnZlZC1maXh0dXJlLWltcG9ydC1wcm9wb3NhbDEvY2FuZGlkYXRlLXN0YWdlMS9zb3VyY2Uvc3VwYWJhc2UvZnVuY3Rpb25zL2NvbGxlY3Qtbm90aWZpY2F0aW9uLW9wZXJhdG9yL2luZGV4LnRzIl0sInNvdXJjZXNDb250ZW50IjpbImltcG9ydCB7XG4gIGF1dGhFcnJvclN0YXR1cyxcbiAgY29yc0hlYWRlcnMsXG4gIHNhZmVFcnJvck1lc3NhZ2UsXG59IGZyb20gXCIuLi9fc2hhcmVkL2NvcnMudHNcIjtcbmltcG9ydCB7IG5vdGlmaWNhdGlvbk9wZXJhdG9yQ29tbWFuZCwgT3BlcmF0b3JJbnB1dEVycm9yIH0gZnJvbSBcIi4uL19zaGFyZWQvbm90aWZpY2F0aW9uX29wZXJhdG9yLnRzXCI7XG5pbXBvcnQgeyBib3VuZGVkSnNvbiwgUHVibGljRXJyb3IgfSBmcm9tIFwiLi4vX3NoYXJlZC9wcm9kdWN0aW9uX2NvbnRyYWN0LnRzXCI7XG5pbXBvcnQgeyByZXF1aXJlVXNlciwgc2VydmljZUNsaWVudCB9IGZyb20gXCIuLi9fc2hhcmVkL3N1cGFiYXNlLnRzXCI7XG5pbXBvcnQgeyByb3N0ZXJTZXNzaW9uIH0gZnJvbSBcIi4uL19zaGFyZWQvcm9zdGVyX3Byb3ZlbmFuY2UudHNcIjtcblxuZnVuY3Rpb24gcmVzcG9uc2UoYm9keTogdW5rbm93biwgc3RhdHVzID0gMjAwKTogUmVzcG9uc2Uge1xuICByZXR1cm4gbmV3IFJlc3BvbnNlKEpTT04uc3RyaW5naWZ5KGJvZHkpLCB7XG4gICAgc3RhdHVzLFxuICAgIGhlYWRlcnM6IHtcbiAgICAgIC4uLmNvcnNIZWFkZXJzLFxuICAgICAgXCJDYWNoZS1Db250cm9sXCI6IFwibm8tc3RvcmUsIG1heC1hZ2U9MFwiLFxuICAgICAgXCJDb250ZW50LVR5cGVcIjogXCJhcHBsaWNhdGlvbi9qc29uXCIsXG4gICAgICBcIlByYWdtYVwiOiBcIm5vLWNhY2hlXCIsXG4gICAgfSxcbiAgfSk7XG59XG5cbmZ1bmN0aW9uIGRhdGFiYXNlQ29kZShlcnJvcjogdW5rbm93bik6IHN0cmluZyB8IG51bGwge1xuICBpZiAodHlwZW9mIGVycm9yICE9PSBcIm9iamVjdFwiIHx8IGVycm9yID09PSBudWxsIHx8ICEoXCJjb2RlXCIgaW4gZXJyb3IpKSB7XG4gICAgcmV0dXJuIG51bGw7XG4gIH1cbiAgY29uc3QgY29kZSA9IChlcnJvciBhcyB7IGNvZGU/OiB1bmtub3duIH0pLmNvZGU7XG4gIHJldHVybiB0eXBlb2YgY29kZSA9PT0gXCJzdHJpbmdcIiA/IGNvZGUgOiBudWxsO1xufVxuXG5EZW5vLnNlcnZlKGFzeW5jIChyZXF1ZXN0KSA9PiB7XG4gIGlmIChyZXF1ZXN0Lm1ldGhvZCA9PT0gXCJPUFRJT05TXCIpIHtcbiAgICByZXR1cm4gbmV3IFJlc3BvbnNlKFwib2tcIiwgeyBoZWFkZXJzOiBjb3JzSGVhZGVycyB9KTtcbiAgfVxuICBpZiAocmVxdWVzdC5tZXRob2QgIT09IFwiUE9TVFwiKSB7XG4gICAgcmV0dXJuIHJlc3BvbnNlKHsgZXJyb3I6IFwiTWV0aG9kIG5vdCBhbGxvd2VkXCIgfSwgNDA1KTtcbiAgfVxuICB0cnkge1xuICAgIGNvbnN0IGF1dGhvcml6YXRpb24gPSByZXF1ZXN0LmhlYWRlcnMuZ2V0KFwiYXV0aG9yaXphdGlvblwiKTtcbiAgICBjb25zdCB7IHN1cGFiYXNlLCB1c2VyIH0gPSBhd2FpdCByZXF1aXJlVXNlcihcbiAgICAgIGF1dGhvcml6YXRpb24sXG4gICAgKTtcbiAgICAvLyBBdXRoLmdldFVzZXIgdmVyaWZpZXMgdGhpcyBleGFjdCBiZWFyZXIgYmVmb3JlIGNsYWltcyBhcmUgZGVjb2RlZC4gVGhlXG4gICAgLy8gY2FsbGVyJ3Mgc2Vzc2lvbiBpcyBuZXZlciB0YWtlbiBmcm9tIHRoZSBhY3Rpb24gcGF5bG9hZCBvciBzZXJ2aWNlIEpXVC5cbiAgICBjb25zdCBjYWxsZXIgPSByb3N0ZXJTZXNzaW9uKGF1dGhvcml6YXRpb24sIHVzZXIuaWQpO1xuICAgIGNvbnN0IHBheWxvYWQgPSBhd2FpdCBib3VuZGVkSnNvbihyZXF1ZXN0KTtcbiAgICBjb25zdCBjb21tYW5kID0gbm90aWZpY2F0aW9uT3BlcmF0b3JDb21tYW5kKFxuICAgICAgcGF5bG9hZC5hY3Rpb24sXG4gICAgICBwYXlsb2FkLFxuICAgICAgY2FsbGVyLmFjdG9ySWQsXG4gICAgICBjYWxsZXIuc2Vzc2lvbklkLFxuICAgICk7XG4gICAgY29uc3QgeyBkYXRhOiBpZGVudGl0eSwgZXJyb3I6IGlkZW50aXR5RXJyb3IgfSA9IGF3YWl0IHN1cGFiYXNlLnJwYyhcbiAgICAgIFwiYWRtaW5fY3VycmVudF91c2VyXCIsXG4gICAgKTtcbiAgICBpZiAoaWRlbnRpdHlFcnJvcikgdGhyb3cgaWRlbnRpdHlFcnJvcjtcbiAgICBjb25zdCBwZXJtaXNzaW9ucyA9IHR5cGVvZiBpZGVudGl0eSA9PT0gXCJvYmplY3RcIiAmJiBpZGVudGl0eSAhPSBudWxsICYmXG4gICAgICAgIEFycmF5LmlzQXJyYXkoKGlkZW50aXR5IGFzIFJlY29yZDxzdHJpbmcsIHVua25vd24+KS5wZXJtaXNzaW9ucylcbiAgICAgID8gKGlkZW50aXR5IGFzIFJlY29yZDxzdHJpbmcsIHVua25vd24+KS5wZXJtaXNzaW9ucyBhcyB1bmtub3duW11cbiAgICAgIDogW107XG4gICAgaWYgKCFwZXJtaXNzaW9ucy5pbmNsdWRlcyhjb21tYW5kLnBlcm1pc3Npb24pKSB7XG4gICAgICByZXR1cm4gcmVzcG9uc2UoeyBlcnJvcjogXCJmb3JiaWRkZW5cIiB9LCA0MDMpO1xuICAgIH1cbiAgICBjb25zdCB7IGRhdGEsIGVycm9yIH0gPSBhd2FpdCBzZXJ2aWNlQ2xpZW50KCkucnBjKFxuICAgICAgY29tbWFuZC5ycGMsXG4gICAgICBjb21tYW5kLnBhcmFtcyxcbiAgICApO1xuICAgIGlmIChlcnJvcikge1xuICAgICAgY29uc3QgY29kZSA9IGRhdGFiYXNlQ29kZShlcnJvcik7XG4gICAgICBpZiAoY29kZSA9PT0gXCI0MjUwMVwiKSByZXR1cm4gcmVzcG9uc2UoeyBlcnJvcjogXCJmb3JiaWRkZW5cIiB9LCA0MDMpO1xuICAgICAgaWYgKGNvZGUgIT09IG51bGwgJiYgW1wiUDAwMDFcIiwgXCIyMzUwNVwiLCBcIjIzNTE0XCIsIFwiNDAwMDFcIl0uaW5jbHVkZXMoY29kZSkpIHtcbiAgICAgICAgcmV0dXJuIHJlc3BvbnNlKHsgZXJyb3I6IFwiY29uZmxpY3RcIiB9LCA0MDkpO1xuICAgICAgfVxuICAgICAgdGhyb3cgZXJyb3I7XG4gICAgfVxuICAgIHJldHVybiByZXNwb25zZSh7IG9rOiB0cnVlLCBhY3Rpb246IHBheWxvYWQuYWN0aW9uLCByZXN1bHQ6IGRhdGEgfSk7XG4gIH0gY2F0Y2ggKGVycm9yKSB7XG4gICAgaWYgKGVycm9yIGluc3RhbmNlb2YgUHVibGljRXJyb3IpIHtcbiAgICAgIHJldHVybiByZXNwb25zZSh7IGVycm9yOiBlcnJvci5jb2RlIH0sIGVycm9yLnN0YXR1cyk7XG4gICAgfVxuICAgIGlmIChlcnJvciBpbnN0YW5jZW9mIE9wZXJhdG9ySW5wdXRFcnJvcikge1xuICAgICAgcmV0dXJuIHJlc3BvbnNlKHsgZXJyb3I6IFwiaW52YWxpZF9yZXF1ZXN0XCIgfSwgNDAwKTtcbiAgICB9XG4gICAgcmV0dXJuIHJlc3BvbnNlKFxuICAgICAgeyBlcnJvcjogc2FmZUVycm9yTWVzc2FnZShlcnJvcikgfSxcbiAgICAgIGF1dGhFcnJvclN0YXR1cyhlcnJvcikgPz8gNTAzLFxuICAgICk7XG4gIH1cbn0pO1xuIl0sIm5hbWVzIjpbXSwibWFwcGluZ3MiOiJBQUFBLFNBQ0UsZUFBZSxFQUNmLFdBQVcsRUFDWCxnQkFBZ0IsUUFDWCxxQkFBcUI7QUFDNUIsU0FBUywyQkFBMkIsRUFBRSxrQkFBa0IsUUFBUSxzQ0FBc0M7QUFDdEcsU0FB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
// denoCacheMetadata=7788218092318069074,4583791274001247065