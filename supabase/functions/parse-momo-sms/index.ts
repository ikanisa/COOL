/**
 * parse-momo-sms/index.ts — Thin HTTP handler for the MoMo SMS parse pipeline.
 *
 * Responsibilities:
 * 1. CORS / method checks
 * 2. Authentication
 * 3. Input validation + fetch raw SMS
 * 4. Delegate to parse_orchestrator.parseSms()
 * 5. Return JSON response
 *
 * All business logic lives in parse_orchestrator.ts and its sub-modules.
 */

import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import {
  errorResponse,
  handleCors,
  jsonResponse,
  methodNotAllowed,
} from "../_shared/http.ts";
import { HttpError } from "../_shared/auth.ts";
import { enforceRateLimit } from "../_shared/rate_limit.ts";
import { createAdminClient, createUserClient } from "../_shared/supabase.ts";
import type { RawSmsRecord } from "./ai_parser.ts";
import { parseSms } from "./parse_orchestrator.ts";

type ParseRequest = {
  rawSmsId?: string;
  forceReparse?: boolean;
  provider?: "openai" | "gemini";
};

Deno.serve(async (request: Request) => {
  // ── CORS ────────────────────────────────────────────────────
  const corsResponse = handleCors(request);
  if (corsResponse) {
    return corsResponse;
  }

  if (request.method !== "POST") {
    return methodNotAllowed("POST", request);
  }

  // ── Auth ────────────────────────────────────────────────────
  const authorization = request.headers.get("authorization");
  if (!authorization) {
    return errorResponse("Authentication required", 401, undefined, request);
  }

  try {
    const adminClient = createAdminClient();
    const userClient = createUserClient(authorization);
    const {
      data: { user },
      error: userError,
    } = await userClient.auth.getUser();
    if (userError || !user) {
      return errorResponse("Authentication required", 401, undefined, request);
    }

    await enforceRateLimit(adminClient, user.id, "parse-momo-sms", {
      maxRequests: 600,
      windowSeconds: 60 * 60,
    });

    // ── Input validation ──────────────────────────────────────
    const body = await request.json() as ParseRequest;
    const rawSmsId = body.rawSmsId?.trim();
    if (!rawSmsId) {
      return errorResponse("rawSmsId is required", 400, undefined, request);
    }

    // ── Fetch raw SMS ─────────────────────────────────────────
    const rawSmsResult = await adminClient
      .from("momo_sms_raw")
      .select("*")
      .eq("id", rawSmsId)
      .eq("user_id", user.id)
      .maybeSingle();

    if (rawSmsResult.error) {
      throw rawSmsResult.error;
    }

    const rawSms = rawSmsResult.data as RawSmsRecord | null;
    if (!rawSms) {
      return errorResponse("Raw SMS record not found", 404, undefined, request);
    }

    // ── Already-parsed guard ──────────────────────────────────
    if (rawSmsResult.data?.parse_status === "parsed" && !body.forceReparse) {
      return jsonResponse({
        success: true,
        skipped: true,
        reason: "already_parsed",
        rawSmsId,
      }, 200, {}, request);
    }

    // ── Delegate to orchestrator ──────────────────────────────
    const result = await parseSms(adminClient, {
      rawSmsId,
      rawSms,
      preferredProvider: body.provider,
    });

    return jsonResponse({ success: true, ...result }, 200, {}, request);
  } catch (error) {
    if (error instanceof SyntaxError) {
      return errorResponse("Invalid JSON body", 400, undefined, request);
    }
    if (error instanceof HttpError) {
      return errorResponse(error.message, error.status, undefined, request);
    }
    console.error("parse-momo-sms failed", error);
    return errorResponse(
      error instanceof Error ? error.message : "Failed to parse MoMo SMS",
      500,
      undefined,
      request,
    );
  }
});
