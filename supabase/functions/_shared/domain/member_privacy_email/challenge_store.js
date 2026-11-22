import { ApiError, first } from "../core.js";
import { challengeResult, denied, invalid, unknown } from "./protocol.js";

const helperSql = {
  prepare: "SELECT private.privacy_email_prepare(?::text,?::text,?::text,?::text) AS result",
  send_claim: "SELECT private.privacy_email_send_claim(?::text,?::text,?::uuid) AS result",
  send_finish:
    "SELECT private.privacy_email_send_finish(?::text,?::text,?::uuid,?::text) AS result",
  verify_claim: "SELECT private.privacy_email_verify_claim(?::text,?::text,?::uuid) AS result",
  verify_finish:
    "SELECT private.privacy_email_verify_finish(?::text,?::text,?::uuid,?::text) AS result",
  consume: "SELECT private.privacy_email_consume(?::text,?::text,?::uuid) AS result",
  status: "SELECT private.privacy_email_status(?::text,?::text) AS result",
  cancel: "SELECT private.privacy_email_cancel(?::text,?::text,?::uuid) AS result",
  cleanup_claim:
    "SELECT private.privacy_email_cleanup_claim(?::text,?::text,?::uuid,?::uuid) AS result",
  cleanup_finish:
    "SELECT private.privacy_email_cleanup_finish(?::text,?::text,?::uuid,?::uuid,?::text) AS result",
};
function dbError(error) {
  const message = String(error?.message ?? "");
  if (message.includes("privacy_email_denied")) return denied();
  if (message.includes("privacy_email_invalid")) return invalid();
  if (message.includes("otp_cooldown")) {
    return new ApiError(429, "auth_rate_limited", "Wait before requesting another code.");
  }
  return unknown();
}

export async function helper(env, name, input, ...args) {
  let row;
  try {
    row = await first(env, helperSql[name], ...args);
  } catch (error) {
    throw dbError(error);
  }
  return challengeResult(row?.result, input);
}
