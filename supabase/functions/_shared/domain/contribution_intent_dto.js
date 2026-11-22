import { stableJson } from "./core.js";

export function contributionIntentJson(row) {
  return {
    id: row.id,
    collection_id: row.collection_id,
    amount_minor: row.amount_minor,
    currency: row.currency,
    rail: row.rail,
    status: row.status,
    receiver_momo_number: row.receiver_momo_number,
    network: row.receiver_network ?? row.network,
    receiver_label: row.receiver_label ?? "",
    receiver_momo_number_hash: row.receiver_momo_number_hash ?? "",
    sender_phone_hash: row.sender_phone_hash ?? "",
    originating_session_id: row.originating_session_id,
    created_at: row.created_at,
    expires_at: row.expires_at,
  };
}
// Match the client PhoneNormalizer exactly; only valid Rwanda mobile numbers
// can bind a protected contribution request. Never return the number in errors.
export function normalizeContributionSender(value) {
  if (typeof value !== "string") return null;
  let digits = value.trim().replace(/[^0-9+]/g, "");
  if (digits.startsWith("+")) digits = digits.slice(1);
  if (digits.startsWith("00")) digits = digits.slice(2);
  let normalized = "";
  if (digits.startsWith("250") && digits.length === 12) normalized = "+" + digits;
  else if (digits.startsWith("0") && digits.length === 10) normalized = "+250" + digits.slice(1);
  else if (digits.length === 9) normalized = "+250" + digits;
  return /^\+2507[2389][0-9]{7}$/.test(normalized) ? normalized : null;
}
export function boundCreationReceipt(row, senderHash) {
  if (
    typeof row?.creation_response_json !== "string" || row.creation_response_json.length > 8192 ||
    new TextEncoder().encode(row.creation_response_json).length > 8192 ||
    typeof senderHash !== "string" || !/^([a-f0-9]{64})$/.test(senderHash)
  ) return false;
  try {
    const saved = JSON.parse(row.creation_response_json);
    return JSON.stringify(saved) === row.creation_response_json &&
      stableJson(saved) ===
        stableJson(
          contributionIntentJson({ ...row, status: "pending", sender_phone_hash: senderHash }),
        );
  } catch {
    return false;
  }
}
