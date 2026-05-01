import {
  FunctionsFetchError,
  FunctionsHttpError,
  FunctionsRelayError,
} from "@supabase/supabase-js";
import { supabase } from "@/lib/supabase";

const RWANDA_DIAL_CODE = "250";

type FunctionErrorDetails = {
  message: string;
  retryAfterSeconds?: number;
  attemptsRemaining?: number;
};

type VerifyOtpPayload = {
  success?: boolean;
  access_token?: string;
  refresh_token?: string;
  userId?: string;
  isNewUser?: boolean;
  session?: {
    access_token?: string;
    refresh_token?: string;
    user?: {
      id?: string;
    };
  };
};

export function normalizeAdminWhatsAppPhone(raw: string): string {
  const trimmed = raw.trim();
  if (!trimmed) {
    throw new Error("Please enter your WhatsApp number.");
  }

  let candidate = trimmed.replace(/[^\d+]/g, "");
  if (candidate.startsWith("00")) {
    candidate = `+${candidate.slice(2)}`;
  }

  candidate = candidate.replace(/(?!^)\+/g, "");
  if (candidate.startsWith("+")) {
    if (!/^\+[1-9]\d{7,14}$/.test(candidate)) {
      throw new Error("Use a valid WhatsApp number in international format.");
    }
    return candidate;
  }

  const digits = candidate.replace(/\D/g, "");
  if (digits.length === 12 && digits.startsWith(RWANDA_DIAL_CODE)) {
    return `+${digits}`;
  }
  if (digits.length === 10 && digits.startsWith("0")) {
    return `+${RWANDA_DIAL_CODE}${digits.slice(1)}`;
  }
  if (digits.length === 9) {
    return `+${RWANDA_DIAL_CODE}${digits}`;
  }

  throw new Error("Enter a valid Rwanda WhatsApp number.");
}

export async function sendAdminWhatsAppOtp(rawPhone: string): Promise<string> {
  const phone = normalizeAdminWhatsAppPhone(rawPhone);
  const { data, error } = await supabase.functions.invoke("send-otp", {
    body: { phone, language: "en" },
  });

  if (error) {
    const details = await resolveFunctionError(error);
    throw new Error(details.message);
  }

  const payload = asRecord(data);
  if (payload.success !== true) {
    throw new Error(resolvePayloadMessage(payload, "Failed to send OTP."));
  }

  return phone;
}

export async function verifyAdminWhatsAppOtp(
  rawPhone: string,
  rawCode: string,
): Promise<{ userId: string; isNewUser: boolean }> {
  const phone = normalizeAdminWhatsAppPhone(rawPhone);
  const code = rawCode.replace(/\D/g, "");
  if (code.length !== 6) {
    throw new Error("Enter the full 6-digit code.");
  }

  const { data, error } = await supabase.functions.invoke("verify-otp", {
    body: { phone, code },
  });

  if (error) {
    const details = await resolveFunctionError(error);
    throw new Error(details.message);
  }

  const payload = asVerifyPayload(data);
  if (payload.success !== true) {
    throw new Error(resolvePayloadMessage(payload, "Verification failed."));
  }

  const accessToken = payload.access_token ?? payload.session?.access_token ?? "";
  const refreshToken =
    payload.refresh_token ?? payload.session?.refresh_token ?? "";
  const userId = payload.userId ?? payload.session?.user?.id ?? "";

  if (!accessToken || !refreshToken || !userId) {
    throw new Error(
      "Verification succeeded but the admin session could not be opened.",
    );
  }

  const { error: sessionError } = await supabase.auth.setSession({
    access_token: accessToken,
    refresh_token: refreshToken,
  });
  if (sessionError) {
    throw new Error(sessionError.message);
  }

  return { userId, isNewUser: payload.isNewUser === true };
}

async function resolveFunctionError(error: unknown): Promise<FunctionErrorDetails> {
  if (error instanceof FunctionsHttpError) {
    try {
      const payload = asRecord(await error.context.json());
      return {
        message: resolvePayloadMessage(
          payload,
          `Request failed (${error.context.status}).`,
        ),
        retryAfterSeconds: asOptionalNumber(payload.retryAfterSeconds),
        attemptsRemaining: asOptionalNumber(payload.attemptsRemaining),
      };
    } catch (_) {
      return { message: `Request failed (${error.context.status}).` };
    }
  }

  if (error instanceof FunctionsRelayError || error instanceof FunctionsFetchError) {
    return { message: error.message };
  }

  if (error instanceof Error) {
    return { message: error.message };
  }

  return { message: "Request failed." };
}

function asVerifyPayload(value: unknown): VerifyOtpPayload {
  return asRecord(value) as VerifyOtpPayload;
}

function asRecord(value: unknown): Record<string, unknown> {
  if (value && typeof value === "object" && !Array.isArray(value)) {
    return value as Record<string, unknown>;
  }
  return {};
}

function resolvePayloadMessage(
  payload: Record<string, unknown>,
  fallback: string,
): string {
  const details = asRecord(payload.details);
  const candidates = [
    payload.error,
    payload.message,
    details.error,
    details.message,
  ];

  for (const candidate of candidates) {
    if (typeof candidate === "string" && candidate.trim()) {
      return candidate.trim();
    }
  }

  return fallback;
}

function asOptionalNumber(value: unknown): number | undefined {
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }
  if (typeof value === "string") {
    const parsed = Number.parseInt(value, 10);
    if (Number.isFinite(parsed)) {
      return parsed;
    }
  }
  return undefined;
}
