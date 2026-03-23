import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import {
  countRecentOtpRateEvents,
  extractClientIp,
  hashOtpRateActorKey,
  recordOtpRateEvent,
} from "../_shared/otp_abuse.ts";
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

type AdminClient = ReturnType<typeof createAdminClient>;

type SendOtpRequest = {
  phone?: string;
  language?: string;
};

export type SendOtpHandlerDependencies = {
  createAdminClient: () => AdminClient;
  recordEdgeFunctionFailure: typeof recordEdgeFunctionFailure;
  sendOtpTemplate: typeof sendOtpTemplate;
};

const otpResendCooldownSeconds = 60;
const otpRateLimitWindowMs = 10 * 60 * 1000;
const maxOtpsPerPhonePerWindow = 3;
const maxOtpsPerIpPerWindow = 10;
const sendOtpFailureMessage = "Failed to send OTP";

const defaultSendOtpHandlerDependencies: SendOtpHandlerDependencies = {
  createAdminClient,
  recordEdgeFunctionFailure,
  sendOtpTemplate,
};

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

export function createSendOtpHandler(
  deps: SendOtpHandlerDependencies = defaultSendOtpHandlerDependencies,
) {
  return async (request: Request): Promise<Response> => {
    const corsResponse = handleCors(request);
    if (corsResponse) {
      return corsResponse;
    }

    if (request.method != "POST") {
      return methodNotAllowed("POST");
    }

    let supabase: AdminClient | null = null;

    try {
      const body = await request.json() as SendOtpRequest;
      const requestedLanguage = body.language?.trim().toLowerCase() ?? "en";
      if (requestedLanguage != "en") {
        console.warn(
          `send-otp received unsupported language "${requestedLanguage}", defaulting to English.`,
        );
      }
      const language = "en";

      const normalizedPhone = normalizePhone(body.phone ?? "");
      const reviewCode = resolveReviewOtp(normalizedPhone);
      const code = reviewCode ?? generateOtpCode();
      const hashedCode = await hashOtpCode(normalizedPhone, code);
      const expiresAt = new Date(Date.now() + 10 * 60 * 1000).toISOString();
      supabase = deps.createAdminClient();
      const clientIp = extractClientIp(request);
      const windowStart = new Date(Date.now() - otpRateLimitWindowMs)
        .toISOString();
      const ipActorKey = clientIp == null
        ? null
        : await hashOtpRateActorKey(`send_ip:${clientIp}`);
      const phoneActorKey = await hashOtpRateActorKey(
        `send_phone:${normalizedPhone}`,
      );

      if (ipActorKey != null) {
        const recentIpEvents = await countRecentOtpRateEvents(supabase, {
          action: "send_ip",
          actorKey: ipActorKey,
          windowStartIso: windowStart,
        });
        if (recentIpEvents >= maxOtpsPerIpPerWindow) {
          await recordSendRateEvents(supabase, {
            ipActorKey,
            phoneActorKey,
            outcome: "blocked_ip_limit",
            phone: normalizedPhone,
            metadata: { limit: maxOtpsPerIpPerWindow },
          });
          return errorResponse(
            "Too many OTP requests from this network. Please try again later.",
            429,
            { retryAfterSeconds: 600 },
          );
        }
      }

      const recentPhoneEvents = await countRecentOtpRateEvents(supabase, {
        action: "send_phone",
        actorKey: phoneActorKey,
        windowStartIso: windowStart,
      });
      if (recentPhoneEvents >= maxOtpsPerPhonePerWindow) {
        await recordSendRateEvents(supabase, {
          ipActorKey,
          phoneActorKey,
          outcome: "blocked_phone_limit",
          phone: normalizedPhone,
          metadata: { limit: maxOtpsPerPhonePerWindow },
        });
        return errorResponse(
          "Too many OTP requests for this phone number. Please try again later.",
          429,
          { retryAfterSeconds: 600 },
        );
      }

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

        await recordSendRateEvents(supabase, {
          ipActorKey,
          phoneActorKey,
          outcome: "blocked_cooldown",
          phone: normalizedPhone,
          metadata: {
            retryAfterSeconds: otpResendCooldownSeconds - elapsedSeconds,
          },
        });

        return errorResponse(
          "Please wait before requesting another code.",
          429,
          {
            retryAfterSeconds: otpResendCooldownSeconds - elapsedSeconds,
          },
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
          await deps.sendOtpTemplate({
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

      await recordSendRateEvents(supabase, {
        ipActorKey,
        phoneActorKey,
        outcome: reviewCode == null ? "sent" : "review_code",
        phone: normalizedPhone,
      });

      return jsonResponse({ success: true });
    } catch (error) {
      if (error instanceof SyntaxError) {
        return errorResponse("Invalid JSON body", 400);
      }
      if (error instanceof PhoneValidationError) {
        return errorResponse(error.message, 400);
      }
      console.error("send-otp failed", error);
      await reportSendOtpFailure(deps, supabase, error);
      return errorResponse(sendOtpFailureMessage, 500);
    }
  };
}

if (import.meta.main) {
  Deno.serve(createSendOtpHandler());
}

async function reportSendOtpFailure(
  deps: SendOtpHandlerDependencies,
  adminClient: AdminClient | null,
  error: unknown,
) {
  try {
    await deps.recordEdgeFunctionFailure(
      adminClient ?? deps.createAdminClient(),
      {
        functionName: "send-otp",
        error,
        subjectType: "otp_phone",
      },
    );
  } catch (reportError) {
    console.error("send-otp telemetry failed", reportError);
  }
}

async function recordSendRateEvents(
  adminClient: AdminClient,
  options: {
    ipActorKey: string | null;
    phoneActorKey: string;
    outcome: string;
    phone: string;
    metadata?: Record<string, unknown>;
  },
) {
  const writes = [
    recordOtpRateEvent(adminClient, {
      action: "send_phone",
      actorKey: options.phoneActorKey,
      outcome: options.outcome,
      phone: options.phone,
      metadata: options.metadata,
    }),
  ];

  if (options.ipActorKey != null) {
    writes.push(
      recordOtpRateEvent(adminClient, {
        action: "send_ip",
        actorKey: options.ipActorKey,
        outcome: options.outcome,
        phone: options.phone,
        metadata: options.metadata,
      }),
    );
  }

  await Promise.all(writes);
}
