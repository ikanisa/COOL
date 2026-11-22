import { ApiError } from "./core.js";
import { gatewayUploadHeld, hasGatewayBinding } from "../gateway-upload-hold.js";
import { captureMemberReceipt } from "./member_sms_capture.js";

export async function receiptFunction(name, body, env, actor) {
  if (!["ingest-payment-sms", "ingest-client-sms"].includes(name)) return { handled: false };
  // Gateway-bound receiving installations use the independently gated native
  // route. A member capture cannot supply a receiving installation binding.
  if (hasGatewayBinding(body)) throw gatewayUploadHeld();
  return captureMemberReceipt(body, env, actor);
}

export async function receiptRoute(request, env, actor) {
  const match = /^\/v1\/receipts\/([0-9a-f-]{36})$/.exec(new URL(request.url).pathname);
  if (!match || request.method !== "GET") return null;
  // This obsolete bearer route did not establish the current Admin account,
  // require a review reason, or atomically record a reveal audit. Do not release
  // plaintext even if an old or newly added grant names sms.raw.reveal. The
  // current Admin capture-content route provides the governed reveal workflow.
  throw new ApiError(
    410,
    "receipt_access_retired",
    "Open the Admin workspace to review retained receipt evidence.",
  );
}
