import { ApiError, first, id, now, uuid } from "./core.js";
import { mutation } from "./mutations.js";
import { canonicalRwandaPhone } from "./native_integrity.js";

export async function getMemberProfile(env, actor) {
  const row = await first(
    env,
    `SELECT id,public_id,phone AS whatsapp_phone,country_code,currency_code,momo_provider,momo_number,momo_pay_code FROM users WHERE id=? AND access_status='active'`,
    actor.userId,
  );
  return { handled: true, value: row };
}

export async function ensureMemberProfile(body, env, actor) {
  const row = await first(
    env,
    "SELECT * FROM users WHERE id=? AND access_status='active'",
    actor.userId,
  );
  if (!row || body.p_whatsapp_phone && body.p_whatsapp_phone !== row.phone) {
    throw new ApiError(403, "42501", "Profile verification does not match this sign-in.");
  }
  return {
    handled: true,
    value: {
      id: row.id,
      public_id: row.public_id,
      whatsapp_phone: row.phone ?? "",
      country_code: row.country_code,
      currency_code: row.currency_code,
      momo_provider: row.momo_provider,
      momo_number: row.momo_number,
      momo_pay_code: row.momo_pay_code,
    },
  };
}

export async function updateMemberProfile(operation, body, env, actor) {
  const requestId = uuid(body.p_request_id ?? body.request_id ?? id(), "request_id");
  // A linked account may have a provider phone which has not been confirmed.
  // Do not treat that value, or another supplied number, as ownership proof.
  const phone = actor.user?.phone;
  if (typeof actor.user?.phone_confirmed_at !== "string" || !actor.user.phone_confirmed_at.trim()) {
    throw new ApiError(403, "42501", "Verify the MoMo number before changing it.");
  }
  let verified;
  try {
    verified = canonicalRwandaPhone(phone);
  } catch {
    throw new ApiError(403, "42501", "Verify the MoMo number before changing it.");
  }
  const raw = body.p_momo_number ?? body.momo_number ?? phone;
  // Accept the same local and international forms as the member editor, but
  // reject unrelated punctuation and non-leading plus signs before canonicalizing.
  if (typeof raw !== "string" || raw.length > 40 || !/^[+0-9 ()-]+$/.test(raw.trim())) {
    throw new ApiError(400, "22023", "Enter a Rwanda MoMo number.");
  }
  let compact = raw.trim().replace(/[ ()-]/g, "");
  if (!/^\+?[0-9]+$/.test(compact) || compact.startsWith("+") && !compact.startsWith("+250")) {
    throw new ApiError(400, "22023", "Enter a Rwanda MoMo number.");
  }
  if (compact.startsWith("00")) compact = compact.slice(2);
  let canonical;
  try {
    canonical = canonicalRwandaPhone(compact);
  } catch {
    throw new ApiError(400, "22023", "Enter a Rwanda MoMo number.");
  }
  if (canonical !== verified) {
    throw new ApiError(403, "42501", "Verify the MoMo number before changing it.");
  }
  const number = "0" + canonical.slice(4);
  const provider = body.p_momo_provider ?? body.momo_provider ?? "mtn_momo";
  const providerMatches = provider === "mtn_momo" && /^07[89]\d{7}$/.test(number) ||
    provider === "airtel_money" && /^07[23]\d{7}$/.test(number);
  if (!providerMatches) throw new ApiError(400, "22023", "Invalid MoMo network.");
  const suppliedCode = body.p_momo_pay_code ?? body.momo_pay_code;
  if (
    suppliedCode !== undefined && suppliedCode !== null &&
    (typeof suppliedCode !== "string" ||
      suppliedCode.trim() !== "" && !/^[0-9]{4,9}$/.test(suppliedCode.trim()))
  ) throw new ApiError(400, "22023", "Enter a MoMo code with 4 to 9 digits.");
  const code = suppliedCode == null ? null : suppliedCode.trim();
  // Missing means preserve the prior code; an explicit empty string clears it.
  await mutation(env, actor, operation, requestId, body, null, [
    env.DB.prepare(
      `UPDATE users SET momo_provider=?,momo_number=?,momo_pay_code=coalesce(?,momo_pay_code),updated_at=? WHERE id=?`,
    ).bind(provider, number, code, now(), actor.userId),
  ]);
  return { handled: true, value: null };
}
