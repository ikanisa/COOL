export class OperatorInputError extends Error {
  constructor(message){
    super(message);
    this.name = "OperatorInputError";
  }
}
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const hashPattern = /^[0-9a-f]{64}$/;
const workerPattern = /^[A-Za-z0-9._:-]{3,80}$/;
function requiredUuid(payload, key) {
  const value = payload[key];
  if (typeof value !== "string" || !uuidPattern.test(value)) {
    throw new OperatorInputError(`${key} must be a UUID`);
  }
  return value.toLowerCase();
}
function requiredText(payload, key, min, max) {
  const value = payload[key];
  if (typeof value !== "string") throw new OperatorInputError(`${key} is required`);
  const clean = value.trim();
  if (clean.length < min || clean.length > max) {
    throw new OperatorInputError(`${key} must contain ${min} to ${max} characters`);
  }
  return clean;
}
function positiveInteger(payload, key) {
  const value = payload[key];
  if (!Number.isSafeInteger(value) || Number(value) < 1) {
    throw new OperatorInputError(`${key} must be a positive integer`);
  }
  return Number(value);
}
function requiredHash(payload, key) {
  const value = payload[key];
  if (typeof value !== "string" || !hashPattern.test(value.toLowerCase())) {
    throw new OperatorInputError(`${key} must be a SHA-256 digest`);
  }
  return value.toLowerCase();
}
function base(operatorUserId, operatorSessionId) {
  if (!uuidPattern.test(operatorUserId)) {
    throw new Error("Authenticated operator ID is invalid");
  }
  if (!uuidPattern.test(operatorSessionId)) {
    throw new Error("Authentication required");
  }
  return {
    p_operator_user_id: operatorUserId.toLowerCase(),
    p_operator_session_id: operatorSessionId.toLowerCase()
  };
}
export function notificationOperatorCommand(action, payload, operatorUserId, operatorSessionId) {
  const common = base(operatorUserId, operatorSessionId);
  switch(action){
    case "health":
      return {
        rpc: "collect_notification_health_v2",
        permission: "notifications.read",
        sensitive: false,
        params: common
      };
    case "list_pending":
      {
        const limit = payload.limit == null ? 20 : positiveInteger(payload, "limit");
        if (limit > 50) throw new OperatorInputError("limit must be 50 or fewer");
        const cursor = payload.after_created_at;
        if (cursor != null && (typeof cursor !== "string" || Number.isNaN(Date.parse(cursor)))) {
          throw new OperatorInputError("after_created_at must be an ISO timestamp");
        }
        return {
          rpc: "collect_list_pending_receipts_v2",
          permission: "notifications.read",
          sensitive: false,
          params: {
            ...common,
            p_limit: limit,
            p_after_created_at: cursor ?? null
          }
        };
      }
    case "claim":
      {
        const worker = requiredText(payload, "worker_id", 3, 80);
        if (!workerPattern.test(worker)) throw new OperatorInputError("worker_id is invalid");
        return {
          rpc: "collect_claim_receipt_v2",
          permission: "notifications.manage",
          sensitive: false,
          params: {
            ...common,
            p_job_id: requiredUuid(payload, "job_id"),
            p_worker_id: worker,
            p_request_id: requiredUuid(payload, "request_id")
          }
        };
      }
    case "get_claimed":
      return {
        rpc: "collect_get_claimed_receipt_v2",
        permission: "notifications.manage",
        sensitive: true,
        params: {
          ...common,
          p_job_id: requiredUuid(payload, "job_id"),
          p_claim_token: requiredUuid(payload, "claim_token"),
          p_fence_version: positiveInteger(payload, "fence_version")
        }
      };
    case "confirm":
      if (payload.user_confirmation !== true) {
        throw new OperatorInputError("A current exact-recipient and exact-content confirmation is required");
      }
      return {
        rpc: "collect_confirm_receipt_v2",
        permission: "notifications.manage",
        sensitive: true,
        params: {
          ...common,
          p_job_id: requiredUuid(payload, "job_id"),
          p_claim_token: requiredUuid(payload, "claim_token"),
          p_fence_version: positiveInteger(payload, "fence_version"),
          p_destination_revision: positiveInteger(payload, "destination_revision"),
          p_body_sha256: requiredHash(payload, "body_sha256"),
          p_confirmation_id: requiredUuid(payload, "confirmation_id")
        }
      };
    case "record_send_start":
      return {
        rpc: "collect_record_send_start_v2",
        permission: "notifications.manage",
        sensitive: true,
        params: {
          ...common,
          p_job_id: requiredUuid(payload, "job_id"),
          p_claim_token: requiredUuid(payload, "claim_token"),
          p_fence_version: positiveInteger(payload, "fence_version"),
          p_confirmation_id: requiredUuid(payload, "confirmation_id")
        }
      };
    case "record_outcome":
      {
        const outcome = requiredText(payload, "outcome", 8, 32);
        if (![
          "observed_sent",
          "failed_no_send",
          "uncertain"
        ].includes(outcome)) {
          throw new OperatorInputError("outcome is invalid");
        }
        const note = payload.outcome_note;
        if (note != null && (typeof note !== "string" || note.trim().length > 500)) {
          throw new OperatorInputError("outcome_note must be 500 characters or fewer");
        }
        return {
          rpc: "collect_record_observed_outcome_v2",
          permission: "notifications.manage",
          sensitive: false,
          params: {
            ...common,
            p_attempt_id: requiredUuid(payload, "attempt_id"),
            p_outcome: outcome,
            p_evidence_reference: requiredText(payload, "evidence_reference", 8, 500),
            p_outcome_note: typeof note === "string" ? note.trim() || null : null
          }
        };
      }
    case "release_claim":
      return {
        rpc: "collect_release_unsent_claim_v2",
        permission: "notifications.manage",
        sensitive: false,
        params: {
          ...common,
          p_job_id: requiredUuid(payload, "job_id"),
          p_claim_token: requiredUuid(payload, "claim_token"),
          p_fence_version: positiveInteger(payload, "fence_version"),
          p_reason: requiredText(payload, "reason", 8, 500)
        }
      };
    case "heartbeat":
      {
        const worker = requiredText(payload, "worker_id", 3, 80);
        if (!workerPattern.test(worker)) throw new OperatorInputError("worker_id is invalid");
        const mode = requiredText(payload, "mode", 7, 20);
        if (![
          "no_send",
          "assisted_send"
        ].includes(mode)) {
          throw new OperatorInputError("mode is invalid");
        }
        return {
          rpc: "collect_worker_heartbeat_v2",
          permission: "notifications.read",
          sensitive: false,
          params: {
            ...common,
            p_worker_id: worker,
            p_run_id: requiredUuid(payload, "run_id"),
            p_mode: mode,
            p_safe_status: {
              queue_checked: payload.queue_checked === true
            }
          }
        };
      }
    default:
      throw new OperatorInputError("Unsupported notification operator action");
  }
}
//# sourceMappingURL=data:application/json;base64,eyJ2ZXJzaW9uIjozLCJzb3VyY2VzIjpbImZpbGU6Ly8vVm9sdW1lcy9QUk8tRzQwL1Byb2plY3RzL1JlY292ZXJlZC1HLVBSTy9DT09ML2RvY3MvcmVsZWFzZS9jcml0aWNhbC1pbXBsZW1lbnRhdGlvbi0yMDI2LTEwLTAxL3N1Y2Nlc3Nvci1vYnNlcnZlZC1maXh0dXJlLWltcG9ydC1wcm9wb3NhbDEvY2FuZGlkYXRlLXN0YWdlMS9zb3VyY2Uvc3VwYWJhc2UvZnVuY3Rpb25zL19zaGFyZWQvbm90aWZpY2F0aW9uX29wZXJhdG9yLnRzIl0sInNvdXJjZXNDb250ZW50IjpbImV4cG9ydCB0eXBlIE5vdGlmaWNhdGlvbk9wZXJhdG9yQWN0aW9uID1cbiAgfCBcImhlYWx0aFwiXG4gIHwgXCJsaXN0X3BlbmRpbmdcIlxuICB8IFwiY2xhaW1cIlxuICB8IFwiZ2V0X2NsYWltZWRcIlxuICB8IFwiY29uZmlybVwiXG4gIHwgXCJyZWNvcmRfc2VuZF9zdGFydFwiXG4gIHwgXCJyZWNvcmRfb3V0Y29tZVwiXG4gIHwgXCJyZWxlYXNlX2NsYWltXCJcbiAgfCBcImhlYXJ0YmVhdFwiO1xuXG5leHBvcnQgY2xhc3MgT3BlcmF0b3JJbnB1dEVycm9yIGV4dGVuZHMgRXJyb3Ige1xuICBjb25zdHJ1Y3RvcihtZXNzYWdlOiBzdHJpbmcpIHtcbiAgICBzdXBlcihtZXNzYWdlKTtcbiAgICB0aGlzLm5hbWUgPSBcIk9wZXJhdG9ySW5wdXRFcnJvclwiO1xuICB9XG59XG5cbmV4cG9ydCB0eXBlIE5vdGlmaWNhdGlvbk9wZXJhdG9yQ29tbWFuZCA9IHtcbiAgcnBjOiBzdHJpbmc7XG4gIHBlcm1pc3Npb246IFwibm90aWZpY2F0aW9ucy5yZWFkXCIgfCBcIm5vdGlmaWNhdGlvbnMubWFuYWdlXCI7XG4gIHNlbnNpdGl2ZTogYm9vbGVhbjtcbiAgcGFyYW1zOiBSZWNvcmQ8c3RyaW5nLCB1bmtub3duPjtcbn07XG5cbmNvbnN0IHV1aWRQYXR0ZXJuID1cbiAgL15bMC05YS1mXXs4fS1bMC05YS1mXXs0fS1bMS01XVswLTlhLWZdezN9LVs4OWFiXVswLTlhLWZdezN9LVswLTlhLWZdezEyfSQvaTtcbmNvbnN0IGhhc2hQYXR0ZXJuID0gL15bMC05YS1mXXs2NH0kLztcbmNvbnN0IHdvcmtlclBhdHRlcm4gPSAvXltBLVphLXowLTkuXzotXXszLDgwfSQvO1xuXG5mdW5jdGlvbiByZXF1aXJlZFV1aWQocGF5bG9hZDogUmVjb3JkPHN0cmluZywgdW5rbm93bj4sIGtleTogc3RyaW5nKTogc3RyaW5nIHtcbiAgY29uc3QgdmFsdWUgPSBwYXlsb2FkW2tleV07XG4gIGlmICh0eXBlb2YgdmFsdWUgIT09IFwic3RyaW5nXCIgfHwgIXV1aWRQYXR0ZXJuLnRlc3QodmFsdWUpKSB7XG4gICAgdGhyb3cgbmV3IE9wZXJhdG9ySW5wdXRFcnJvcihgJHtrZXl9IG11c3QgYmUgYSBVVUlEYCk7XG4gIH1cbiAgcmV0dXJuIHZhbHVlLnRvTG93ZXJDYXNlKCk7XG59XG5cbmZ1bmN0aW9uIHJlcXVpcmVkVGV4dChcbiAgcGF5bG9hZDogUmVjb3JkPHN0cmluZywgdW5rbm93bj4sXG4gIGtleTogc3RyaW5nLFxuICBtaW46IG51bWJlcixcbiAgbWF4OiBudW1iZXIsXG4pOiBzdHJpbmcge1xuICBjb25zdCB2YWx1ZSA9IHBheWxvYWRba2V5XTtcbiAgaWYgKHR5cGVvZiB2YWx1ZSAhPT0gXCJzdHJpbmdcIikgdGhyb3cgbmV3IE9wZXJhdG9ySW5wdXRFcnJvcihgJHtrZXl9IGlzIHJlcXVpcmVkYCk7XG4gIGNvbnN0IGNsZWFuID0gdmFsdWUudHJpbSgpO1xuICBpZiAoY2xlYW4ubGVuZ3RoIDwgbWluIHx8IGNsZWFuLmxlbmd0aCA+IG1heCkge1xuICAgIHRocm93IG5ldyBPcGVyYXRvcklucHV0RXJyb3IoYCR7a2V5fSBtdXN0IGNvbnRhaW4gJHttaW59IHRvICR7bWF4fSBjaGFyYWN0ZXJzYCk7XG4gIH1cbiAgcmV0dXJuIGNsZWFuO1xufVxuXG5mdW5jdGlvbiBwb3NpdGl2ZUludGVnZXIoXG4gIHBheWxvYWQ6IFJlY29yZDxzdHJpbmcsIHVua25vd24+LFxuICBrZXk6IHN0cmluZyxcbik6IG51bWJlciB7XG4gIGNvbnN0IHZhbHVlID0gcGF5bG9hZFtrZXldO1xuICBpZiAoIU51bWJlci5pc1NhZmVJbnRlZ2VyKHZhbHVlKSB8fCBOdW1iZXIodmFsdWUpIDwgMSkge1xuICAgIHRocm93IG5ldyBPcGVyYXRvcklucHV0RXJyb3IoYCR7a2V5fSBtdXN0IGJlIGEgcG9zaXRpdmUgaW50ZWdlcmApO1xuICB9XG4gIHJldHVybiBOdW1iZXIodmFsdWUpO1xufVxuXG5mdW5jdGlvbiByZXF1aXJlZEhhc2gocGF5bG9hZDogUmVjb3JkPHN0cmluZywgdW5rbm93bj4sIGtleTogc3RyaW5nKTogc3RyaW5nIHtcbiAgY29uc3QgdmFsdWUgPSBwYXlsb2FkW2tleV07XG4gIGlmICh0eXBlb2YgdmFsdWUgIT09IFwic3RyaW5nXCIgfHwgIWhhc2hQYXR0ZXJuLnRlc3QodmFsdWUudG9Mb3dlckNhc2UoKSkpIHtcbiAgICB0aHJvdyBuZXcgT3BlcmF0b3JJbnB1dEVycm9yKGAke2tleX0gbXVzdCBiZSBhIFNIQS0yNTYgZGlnZXN0YCk7XG4gIH1cbiAgcmV0dXJuIHZhbHVlLnRvTG93ZXJDYXNlKCk7XG59XG5cbmZ1bmN0aW9uIGJhc2Uob3BlcmF0b3JVc2VySWQ6IHN0cmluZywgb3BlcmF0b3JTZXNzaW9uSWQ6IHN0cmluZykge1xuICBpZiAoIXV1aWRQYXR0ZXJuLnRlc3Qob3BlcmF0b3JVc2VySWQpKSB7XG4gICAgdGhyb3cgbmV3IEVycm9yKFwiQXV0aGVudGljYXRlZCBvcGVyYXRvciBJRCBpcyBpbnZhbGlkXCIpO1xuICB9XG4gIGlmICghdXVpZFBhdHRlcm4udGVzdChvcGVyYXRvclNlc3Npb25JZCkpIHtcbiAgICB0aHJvdyBuZXcgRXJyb3IoXCJBdXRoZW50aWNhdGlvbiByZXF1aXJlZFwiKTtcbiAgfVxuICByZXR1cm4ge1xuICAgIHBfb3BlcmF0b3JfdXNlcl9pZDogb3BlcmF0b3JVc2VySWQudG9Mb3dlckNhc2UoKSxcbiAgICBwX29wZXJhdG9yX3Nlc3Npb25faWQ6IG9wZXJhdG9yU2Vzc2lvbklkLnRvTG93ZXJDYXNlKCksXG4gIH07XG59XG5cbmV4cG9ydCBmdW5jdGlvbiBub3RpZmljYXRpb25PcGVyYXRvckNvbW1hbmQoXG4gIGFjdGlvbjogdW5rbm93bixcbiAgcGF5bG9hZDogUmVjb3JkPHN0cmluZywgdW5rbm93bj4sXG4gIG9wZXJhdG9yVXNlcklkOiBzdHJpbmcsXG4gIG9wZXJhdG9yU2Vzc2lvbklkOiBzdHJpbmcsXG4pOiBOb3RpZmljYXRpb25PcGVyYXRvckNvbW1hbmQge1xuICBjb25zdCBjb21tb24gPSBiYXNlKG9wZXJhdG9yVXNlcklkLCBvcGVyYXRvclNlc3Npb25JZCk7XG4gIHN3aXRjaCAoYWN0aW9uIGFzIE5vdGlmaWNhdGlvbk9wZXJhdG9yQWN0aW9uKSB7XG4gICAgY2FzZSBcImhlYWx0aFwiOlxuICAgICAgcmV0dXJuIHtcbiAgICAgICAgcnBjOiBcImNvbGxlY3Rfbm90aWZpY2F0aW9uX2hlYWx0aF92MlwiLFxuICAgICAgICBwZXJtaXNzaW9uOiBcIm5vdGlmaWNhdGlvbnMucmVhZFwiLFxuICAgICAgICBzZW5zaXRpdmU6IGZhbHNlLFxuICAgICAgICBwYXJhbXM6IGNvbW1vbixcbiAgICAgIH07XG4gICAgY2FzZSBcImxpc3RfcGVuZGluZ1wiOiB7XG4gICAgICBjb25zdCBsaW1pdCA9IHBheWxvYWQubGltaXQgPT0gbnVsbFxuICAgICAgICA/IDIwXG4gICAgICAgIDogcG9zaXRpdmVJbnRlZ2VyKHBheWxvYWQsIFwibGltaXRcIik7XG4gICAgICBpZiAobGltaXQgPiA1MCkgdGhyb3cgbmV3IE9wZXJhdG9ySW5wdXRFcnJvcihcImxpbWl0IG11c3QgYmUgNTAgb3IgZmV3ZXJcIik7XG4gICAgICBjb25zdCBjdXJzb3IgPSBwYXlsb2FkLmFmdGVyX2NyZWF0ZWRfYXQ7XG4gICAgICBpZiAoXG4gICAgICAgIGN1cnNvciAhPSBudWxsICYmXG4gICAgICAgICh0eXBlb2YgY3Vyc29yICE9PSBcInN0cmluZ1wiIHx8IE51bWJlci5pc05hTihEYXRlLnBhcnNlKGN1cnNvcikpKVxuICAgICAgKSB7XG4gICAgICAgIHRocm93IG5ldyBPcGVyYXRvcklucHV0RXJyb3IoXCJhZnRlcl9jcmVhdGVkX2F0IG11c3QgYmUgYW4gSVNPIHRpbWVzdGFtcFwiKTtcbiAgICAgIH1cbiAgICAgIHJldHVybiB7XG4gICAgICAgIHJwYzogXCJjb2xsZWN0X2xpc3RfcGVuZGluZ19yZWNlaXB0c192MlwiLFxuICAgICAgICBwZXJtaXNzaW9uOiBcIm5vdGlmaWNhdGlvbnMucmVhZFwiLFxuICAgICAgICBzZW5zaXRpdmU6IGZhbHNlLFxuICAgICAgICBwYXJhbXM6IHtcbiAgICAgICAgICAuLi5jb21tb24sXG4gICAgICAgICAgcF9saW1pdDogbGltaXQsXG4gICAgICAgICAgcF9hZnRlcl9jcmVhdGVkX2F0OiBjdXJzb3IgPz8gbnVsbCxcbiAgICAgICAgfSxcbiAgICAgIH07XG4gICAgfVxuICAgIGNhc2UgXCJjbGFpbVwiOiB7XG4gICAgICBjb25zdCB3b3JrZXIgPSByZXF1aXJlZFRleHQocGF5bG9hZCwgXCJ3b3JrZXJfaWRcIiwgMywgODApO1xuICAgICAgaWYgKCF3b3JrZXJQYXR0ZXJuLnRlc3Qod29ya2VyKSkgdGhyb3cgbmV3IE9wZXJhdG9ySW5wdXRFcnJvcihcIndvcmtlcl9pZCBpcyBpbnZhbGlkXCIpO1xuICAgICAgcmV0dXJuIHtcbiAgICAgICAgcnBjOiBcImNvbGxlY3RfY2xhaW1fcmVjZWlwdF92MlwiLFxuICAgICAgICBwZXJtaXNzaW9uOiBcIm5vdGlmaWNhdGlvbnMubWFuYWdlXCIsXG4gICAgICAgIHNlbnNpdGl2ZTogZmFsc2UsXG4gICAgICAgIHBhcmFtczoge1xuICAgICAgICAgIC4uLmNvbW1vbixcbiAgICAgICAgICBwX2pvYl9pZDogcmVxdWlyZWRVdWlkKHBheWxvYWQsIFwiam9iX2lkXCIpLFxuICAgICAgICAgIHBfd29ya2VyX2lkOiB3b3JrZXIsXG4gICAgICAgICAgcF9yZXF1ZXN0X2lkOiByZXF1aXJlZFV1aWQocGF5bG9hZCwgXCJyZXF1ZXN0X2lkXCIpLFxuICAgICAgICB9LFxuICAgICAgfTtcbiAgICB9XG4gICAgY2FzZSBcImdldF9jbGFpbWVkXCI6XG4gICAgICByZXR1cm4ge1xuICAgICAgICBycGM6IFwiY29sbGVjdF9nZXRfY2xhaW1lZF9yZWNlaXB0X3YyXCIsXG4gICAgICAgIHBlcm1pc3Npb246IFwibm90aWZpY2F0aW9ucy5tYW5hZ2VcIixcbiAgICAgICAgc2Vuc2l0aXZlOiB0cnVlLFxuICAgICAgICBwYXJhbXM6IHtcbiAgICAgICAgICAuLi5jb21tb24sXG4gICAgICAgICAgcF9qb2JfaWQ6IHJlcXVpcmVkVXVpZChwYXlsb2FkLCBcImpvYl9pZFwiKSxcbiAgICAgICAgICBwX2NsYWltX3Rva2VuOiByZXF1aXJlZFV1aWQocGF5bG9hZCwgXCJjbGFpbV90b2tlblwiKSxcbiAgICAgICAgICBwX2ZlbmNlX3ZlcnNpb246IHBvc2l0aXZlSW50ZWdlcihwYXlsb2FkLCBcImZlbmNlX3ZlcnNpb25cIiksXG4gICAgICAgIH0sXG4gICAgICB9O1xuICAgIGNhc2UgXCJjb25maXJtXCI6XG4gICAgICBpZiAocGF5bG9hZC51c2VyX2NvbmZpcm1hdGlvbiAhPT0gdHJ1ZSkge1xuICAgICAgICB0aHJvdyBuZXcgT3BlcmF0b3JJbnB1dEVycm9yKFxuICAgICAgICAgIFwiQSBjdXJyZW50IGV4YWN0LXJlY2lwaWVudCBhbmQgZXhhY3QtY29udGVudCBjb25maXJtYXRpb24gaXMgcmVxdWlyZWRcIixcbiAgICAgICAgKTtcbiAgICAgIH1cbiAgICAgIHJldHVybiB7XG4gICAgICAgIHJwYzogXCJjb2xsZWN0X2NvbmZpcm1fcmVjZWlwdF92MlwiLFxuICAgICAgICBwZXJtaXNzaW9uOiBcIm5vdGlmaWNhdGlvbnMubWFuYWdlXCIsXG4gICAgICAgIHNlbnNpdGl2ZTogdHJ1ZSxcbiAgICAgICAgcGFyYW1zOiB7XG4gICAgICAgICAgLi4uY29tbW9uLFxuICAgICAgICAgIHBfam9iX2lkOiByZXF1aXJlZFV1aWQocGF5bG9hZCwgXCJqb2JfaWRcIiksXG4gICAgICAgICAgcF9jbGFpbV90b2tlbjogcmVxdWlyZWRVdWlkKHBheWxvYWQsIFwiY2xhaW1fdG9rZW5cIiksXG4gICAgICAgICAgcF9mZW5jZV92ZXJzaW9uOiBwb3NpdGl2ZUludGVnZXIocGF5bG9hZCwgXCJmZW5jZV92ZXJzaW9uXCIpLFxuICAgICAgICAgIHBfZGVzdGluYXRpb25fcmV2aXNpb246IHBvc2l0aXZlSW50ZWdlcihcbiAgICAgICAgICAgIHBheWxvYWQsXG4gICAgICAgICAgICBcImRlc3RpbmF0aW9uX3JldmlzaW9uXCIsXG4gICAgICAgICAgKSxcbiAgICAgICAgICBwX2JvZHlfc2hhMjU2OiByZXF1aXJlZEhhc2gocGF5bG9hZCwgXCJib2R5X3NoYTI1NlwiKSxcbiAgICAgICAgICBwX2NvbmZpcm1hdGlvbl9pZDogcmVxdWlyZWRVdWlkKHBheWxvYWQsIFwiY29uZmlybWF0aW9uX2lkXCIpLFxuICAgICAgICB9LFxuICAgICAgfTtcbiAgICBjYXNlIFwicmVjb3JkX3NlbmRfc3RhcnRcIjpcbiAgICAgIHJldHVybiB7XG4gICAgICAgIHJwYzogXCJjb2xsZWN0X3JlY29yZF9zZW5kX3N0YXJ0X3YyXCIsXG4gICAgICAgIHBlcm1pc3Npb246IFwibm90aWZpY2F0aW9ucy5tYW5hZ2VcIixcbiAgICAgICAgc2Vuc2l0aXZlOiB0cnVlLFxuICAgICAgICBwYXJhbXM6IHtcbiAgICAgICAgICAuLi5jb21tb24sXG4gICAgICAgICAgcF9qb2JfaWQ6IHJlcXVpcmVkVXVpZChwYXlsb2FkLCBcImpvYl9pZFwiKSxcbiAgICAgICAgICBwX2NsYWltX3Rva2VuOiByZXF1aXJlZFV1aWQocGF5bG9hZCwgXCJjbGFpbV90b2tlblwiKSxcbiAgICAgICAgICBwX2ZlbmNlX3ZlcnNpb246IHBvc2l0aXZlSW50ZWdlcihwYXlsb2FkLCBcImZlbmNlX3ZlcnNpb25cIiksXG4gICAgICAgICAgcF9jb25maXJtYXRpb25faWQ6IHJlcXVpcmVkVXVpZChwYXlsb2FkLCBcImNvbmZpcm1hdGlvbl9pZFwiKSxcbiAgICAgICAgfSxcbiAgICAgIH07XG4gICAgY2FzZSBcInJlY29yZF9vdXRjb21lXCI6IHtcbiAgICAgIGNvbnN0IG91dGNvbWUgPSByZXF1aXJlZFRleHQocGF5bG9hZCwgXCJvdXRjb21lXCIsIDgsIDMyKTtcbiAgICAgIGlmICghW1wib2JzZXJ2ZWRfc2VudFwiLCBcImZhaWxlZF9ub19zZW5kXCIsIFwidW5jZXJ0YWluXCJdLmluY2x1ZGVzKG91dGNvbWUpKSB7XG4gICAgICAgIHRocm93IG5ldyBPcGVyYXRvcklucHV0RXJyb3IoXCJvdXRjb21lIGlzIGludmFsaWRcIik7XG4gICAgICB9XG4gICAgICBjb25zdCBub3RlID0gcGF5bG9hZC5vdXRjb21lX25vdGU7XG4gICAgICBpZiAoXG4gICAgICAgIG5vdGUgIT0gbnVsbCAmJiAodHlwZW9mIG5vdGUgIT09IFwic3RyaW5nXCIgfHwgbm90ZS50cmltKCkubGVuZ3RoID4gNTAwKVxuICAgICAgKSB7XG4gICAgICAgIHRocm93IG5ldyBPcGVyYXRvcklucHV0RXJyb3IoXCJvdXRjb21lX25vdGUgbXVzdCBiZSA1MDAgY2hhcmFjdGVycyBvciBmZXdlclwiKTtcbiAgICAgIH1cbiAgICAgIHJldHVybiB7XG4gICAgICAgIHJwYzogXCJjb2xsZWN0X3JlY29yZF9vYnNlcnZlZF9vdXRjb21lX3YyXCIsXG4gICAgICAgIHBlcm1pc3Npb246IFwibm90aWZpY2F0aW9ucy5tYW5hZ2VcIixcbiAgICAgICAgc2Vuc2l0aXZlOiBmYWxzZSxcbiAgICAgICAgcGFyYW1zOiB7XG4gICAgICAgICAgLi4uY29tbW9uLFxuICAgICAgICAgIHBfYXR0ZW1wdF9pZDogcmVxdWlyZWRVdWlkKHBheWxvYWQsIFwiYXR0ZW1wdF9pZFwiKSxcbiAgICAgICAgICBwX291dGNvbWU6IG91dGNvbWUsXG4gICAgICAgICAgcF9ldmlkZW5jZV9yZWZlcmVuY2U6IHJlcXVpcmVkVGV4dChcbiAgICAgICAgICAgIHBheWxvYWQsXG4gICAgICAgICAgICBcImV2aWRlbmNlX3JlZmVyZW5jZVwiLFxuICAgICAgICAgICAgOCxcbiAgICAgICAgICAgIDUwMCxcbiAgICAgICAgICApLFxuICAgICAgICAgIHBfb3V0Y29tZV9ub3RlOiB0eXBlb2Ygbm90ZSA9PT0gXCJzdHJpbmdcIiA/IG5vdGUudHJpbSgpIHx8IG51bGwgOiBudWxsLFxuICAgICAgICB9LFxuICAgICAgfTtcbiAgICB9XG4gICAgY2FzZSBcInJlbGVhc2VfY2xhaW1cIjpcbiAgICAgIHJldHVybiB7XG4gICAgICAgIHJwYzogXCJjb2xsZWN0X3JlbGVhc2VfdW5zZW50X2NsYWltX3YyXCIsXG4gICAgICAgIHBlcm1pc3Npb246IFwibm90aWZpY2F0aW9ucy5tYW5hZ2VcIixcbiAgICAgICAgc2Vuc2l0aXZlOiBmYWxzZSxcbiAgICAgICAgcGFyYW1zOiB7XG4gICAgICAgICAgLi4uY29tbW9uLFxuICAgICAgICAgIHBfam9iX2lkOiByZXF1aXJlZFV1aWQocGF5bG9hZCwgXCJqb2JfaWRcIiksXG4gICAgICAgICAgcF9jbGFpbV90b2tlbjogcmVxdWlyZWRVdWlkKHBheWxvYWQsIFwiY2xhaW1fdG9rZW5cIiksXG4gICAgICAgICAgcF9mZW5jZV92ZXJzaW9uOiBwb3NpdGl2ZUludGVnZXIocGF5bG9hZCwgXCJmZW5jZV92ZXJzaW9uXCIpLFxuICAgICAgICAgIHBfcmVhc29uOiByZXF1aXJlZFRleHQocGF5bG9hZCwgXCJyZWFzb25cIiwgOCwgNTAwKSxcbiAgICAgICAgfSxcbiAgICAgIH07XG4gICAgY2FzZSBcImhlYXJ0YmVhdFwiOiB7XG4gICAgICBjb25zdCB3b3JrZXIgPSByZXF1aXJlZFRleHQocGF5bG9hZCwgXCJ3b3JrZXJfaWRcIiwgMywgODApO1xuICAgICAgaWYgKCF3b3JrZXJQYXR0ZXJuLnRlc3Qod29ya2VyKSkgdGhyb3cgbmV3IE9wZXJhdG9ySW5wdXRFcnJvcihcIndvcmtlcl9pZCBpcyBpbnZhbGlkXCIpO1xuICAgICAgY29uc3QgbW9kZSA9IHJlcXVpcmVkVGV4dChwYXlsb2FkLCBcIm1vZGVcIiwgNywgMjApO1xuICAgICAgaWYgKCFbXCJub19zZW5kXCIsIFwiYXNzaXN0ZWRfc2VuZFwiXS5pbmNsdWRlcyhtb2RlKSkge1xuICAgICAgICB0aHJvdyBuZXcgT3BlcmF0b3JJbnB1dEVycm9yKFwibW9kZSBpcyBpbnZhbGlkXCIpO1xuICAgICAgfVxuICAgICAgcmV0dXJuIHtcbiAgICAgICAgcnBjOiBcImNvbGxlY3Rfd29ya2VyX2hlYXJ0YmVhdF92MlwiLFxuICAgICAgICBwZXJtaXNzaW9uOiBcIm5vdGlmaWNhdGlvbnMucmVhZFwiLFxuICAgICAgICBzZW5zaXRpdmU6IGZhbHNlLFxuICAgICAgICBwYXJhbXM6IHtcbiAgICAgICAgICAuLi5jb21tb24sXG4gICAgICAgICAgcF93b3JrZXJfaWQ6IHdvcmtlcixcbiAgICAgICAgICBwX3J1bl9pZDogcmVxdWlyZWRVdWlkKHBheWxvYWQsIFwicnVuX2lkXCIpLFxuICAgICAgICAgIHBfbW9kZTogbW9kZSxcbiAgICAgICAgICBwX3NhZmVfc3RhdHVzOiB7IHF1ZXVlX2NoZWNrZWQ6IHBheWxvYWQucXVldWVfY2hlY2tlZCA9PT0gdHJ1ZSB9LFxuICAgICAgICB9LFxuICAgICAgfTtcbiAgICB9XG4gICAgZGVmYXVsdDpcbiAgICAgIHRocm93IG5ldyBPcGVyYXRvcklucHV0RXJyb3IoXCJVbnN1cHBvcnRlZCBub3RpZmljYXRpb24gb3BlcmF0b3IgYWN0aW9uXCIpO1xuICB9XG59XG4iXSwibmFtZXMiOltdLCJtYXBwaW5ncyI6IkFBV0EsT0FBTyxNQUFNLDJCQUEyQjtFQUN0QyxZQUFZLE9BQWUsQ0FBRTtJQUMzQixLQUFLLENBQUM7SUFDTixJQUFJLENBQUMsSUFBSSxHQUFHO0VBQ2Q7QUFDRjtBQVNBLE1BQU0sY0FDSjtBQUNGLE1BQU0sY0FBYztBQUNwQixNQUFNLGdCQUFnQjtBQUV0QixTQUFTLGFBQWEsT0FBZ0MsRUFB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
// denoCacheMetadata=15454472934780277056,10468342628928211845