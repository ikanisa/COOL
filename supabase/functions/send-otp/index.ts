import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import {
  errorResponse,
  handleCors,
  jsonResponse,
  methodNotAllowed,
} from "../_shared/http.ts";
import { recordEdgeFunctionFailure } from "../_shared/observability.ts";
import { normalizePhone, PhoneValidationError } from "../_shared/phone.ts";
import { generateOtpCode, hashOtpCode } from "../_shared/security.ts";
import { createAdminClient } from "../_shared/supabase.ts";
import { sendOtpTemplate } from "../_shared/whatsapp.ts";

type SendOtpRequest = {
  phone?: string;
  language?: "en" | "fr";
};

const otpResendCooldownSeconds = 60;

function resolveReviewOtp(normalizedPhone: string): string | null {
  const configuredPhone = Deno.env.get("OTP_TEST_PHONE")?.trim();
  const configuredCode = Deno.env.get("OTP_TEST_CODE")?.trim();
  if (!configuredPhone || !configuredCode) {
    return null;
  }

  if (!/^\d{6}$/.test(configuredCode)) {
    console.error("OTP_TEST_CODE must be exactly 6 digits.");
    return null;
  }

  try {
    return normalizePhone(configuredPhone) == normalizedPhone
      ? configuredCode
      : null;
  } catch (error) {
    console.error("OTP_TEST_PHONE is invalid.", error);
    return null;
  }
}

Deno.serve(async (request: Request) => {
  const corsResponse = handleCors(request);
  if (corsResponse) {
    return corsResponse;
  }

  if (request.method != "POST") {
    return methodNotAllowed("POST");
  }

  try {
    const body = await request.json() as SendOtpRequest;
    const language = body.language;
    if (language != "en" && language != "fr") {
      return errorResponse('language must be "en" or "fr"', 400);
    }

    const normalizedPhone = normalizePhone(body.phone ?? "");
    const reviewCode = resolveReviewOtp(normalizedPhone);
    const code = reviewCode ?? generateOtpCode();
    const hashedCode = await hashOtpCode(normalizedPhone, code);
    const expiresAt = new Date(Date.now() + 10 * 60 * 1000).toISOString();
    const supabase = createAdminClient();

    // ── Cooldown: reject re-sends within 60 seconds ──────────────────
    const existingOtpResult = await supabase
      .from("otp_codes")
      .select("id, created_at")
      .eq("phone", normalizedPhone)
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();

    if (existingOtpResult.error) {
      throw existingOtpResult.error;
    }

    finalCooldownCheck:
    {
      const createdAt = existingOtpResult.data?.created_at?.toString();
      if (!createdAt) {
        break finalCooldownCheck;
      }

      const createdAtMs = Date.parse(createdAt);
      if (!Number.isFinite(createdAtMs)) {
        break finalCooldownCheck;
      }

      const elapsedSeconds = Math.floor((Date.now() - createdAtMs) / 1000);
      if (elapsedSeconds >= otpResendCooldownSeconds) {
        break finalCooldownCheck;
      }

      return errorResponse(
        "Please wait before requesting another code.",
        429,
        {
          retryAfterSeconds: otpResendCooldownSeconds - elapsedSeconds,
        },
      );
    }

    // ── Rate limit: max 3 OTPs per phone per 10-minute window ────────
    const rateLimitWindowMs = 10 * 60 * 1000;
    const maxOtpsPerWindow = 3;
    const windowStart = new Date(Date.now() - rateLimitWindowMs).toISOString();

    const recentOtpsResult = await supabase
      .from("otp_codes")
      .select("id", { count: "exact", head: true })
      .eq("phone", normalizedPhone)
      .gte("created_at", windowStart);

    if (recentOtpsResult.error) {
      throw recentOtpsResult.error;
    }

    if ((recentOtpsResult.count ?? 0) >= maxOtpsPerWindow) {
      console.warn(
        `[OTP-ABUSE] Rate limit hit for phone ${normalizedPhone.slice(-4)}`,
      );
      return errorResponse(
        "Too many OTP requests. Please try again later.",
        429,
        { retryAfterSeconds: 600 },
      );
    }

    const deleteExistingResult = await supabase
      .from("otp_codes")
      .delete()
      .eq("phone", normalizedPhone);

    if (deleteExistingResult.error) {
      throw deleteExistingResult.error;
    }

    const insertResult = await supabase
      .from("otp_codes")
      .insert({
        phone: normalizedPhone,
        code: hashedCode,
        expires_at: expiresAt,
        attempts: 0,
        verified: false,
      })
      .select("id")
      .single();

    if (insertResult.error) {
      throw insertResult.error;
    }

    if (reviewCode == null) {
      try {
        await sendOtpTemplate({
          phone: normalizedPhone,
          code,
          language,
        });
      } catch (error) {
        await supabase
          .from("otp_codes")
          .delete()
          .eq("id", insertResult.data.id);

        throw error;
      }
    }

    return jsonResponse({ success: true });
  } catch (error) {
    if (error instanceof SyntaxError) {
      return errorResponse("Invalid JSON body", 400);
    }
    if (error instanceof PhoneValidationError) {
      return errorResponse(error.message, 400);
    }
    console.error("send-otp failed", error);
    await recordEdgeFunctionFailure(createAdminClient(), {
      functionName: "send-otp",
      error,
      subjectType: "otp_phone",
    });
    return errorResponse(
      error instanceof Error ? error.message : "Failed to send OTP",
      500,
    );
  }
});
