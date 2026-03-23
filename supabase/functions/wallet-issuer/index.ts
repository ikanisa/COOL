/**
 * wallet-issuer Edge Function — slim handler.
 *
 * Routes incoming requests to ticket or membership pass issuance.
 * Domain logic lives in ticket_pass.ts and membership_pass.ts.
 * API plumbing lives in wallet_api.ts.
 */
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import {
  errorResponse,
  handleCors,
  jsonResponse,
  methodNotAllowed,
} from "../_shared/http.ts";
import {
  recordEdgeFunctionFailure,
  recordOperationalHealthEvent,
} from "../_shared/observability.ts";
import { createAdminClient, createUserClient } from "../_shared/supabase.ts";
import { HttpError, inspectWalletConfig } from "./wallet_api.ts";
import { issueRayonTicketWalletPass } from "./ticket_pass.ts";
import { issueRayonMembershipWalletPass } from "./membership_pass.ts";

type WalletIssuerRequest = {
  action?: "health" | "rayon_ticket" | "rayon_membership";
  ticketId?: string;
  membershipId?: string;
};

type AuthenticatedCaller = {
  userId: string;
};

Deno.serve(async (request: Request) => {
  const corsResponse = handleCors(request);
  if (corsResponse) {
    return corsResponse;
  }

  if (request.method != "POST") {
    return methodNotAllowed("POST");
  }

  const authorization = request.headers.get("authorization");
  if (!authorization) {
    return errorResponse("Authentication required.", 401);
  }

  let ticketIdForTelemetry: string | null = null;
  let callerUserIdForTelemetry: string | null = null;

  try {
    const caller = await requireCaller(authorization);
    const body = await request.json() as WalletIssuerRequest;
    const startedAt = Date.now();
    ticketIdForTelemetry = body.ticketId?.trim() ?? null;
    callerUserIdForTelemetry = caller.userId;

    switch (body.action) {
      case "health": {
        return jsonResponse({
          success: true,
          ...inspectWalletConfig(),
        });
      }
      case "rayon_ticket": {
        const response = await issueRayonTicketWalletPass({
          caller,
          ticketId: body.ticketId,
        });

        console.info(
          JSON.stringify({
            service: "wallet-issuer",
            action: "rayon_ticket",
            user_id: caller.userId,
            ticket_id: body.ticketId ?? null,
            latency_ms: Date.now() - startedAt,
          }),
        );

        await recordOperationalHealthEvent(createAdminClient(), {
          service: "wallet_sync",
          component: "wallet-issuer",
          status: "ok",
          severity: "info",
          message: "Google Wallet pass prepared successfully.",
          functionName: "wallet-issuer",
          userId: caller.userId,
          subjectType: "rs_ticket",
          subjectId: body.ticketId ?? null,
          metadata: {
            action: "rayon_ticket",
            wallet_pass_id: response.walletPassId,
            class_id: response.classId,
            object_id: response.objectId,
            latency_ms: Date.now() - startedAt,
          },
        });

        return jsonResponse({ success: true, ...response });
      }
      case "rayon_membership": {
        const response = await issueRayonMembershipWalletPass({
          caller,
          membershipId: body.membershipId,
        });

        console.info(
          JSON.stringify({
            service: "wallet-issuer",
            action: "rayon_membership",
            user_id: caller.userId,
            membership_id: body.membershipId ?? null,
            latency_ms: Date.now() - startedAt,
          }),
        );

        await recordOperationalHealthEvent(createAdminClient(), {
          service: "wallet_sync",
          component: "wallet-issuer",
          status: "ok",
          severity: "info",
          message: "Google Wallet membership pass prepared successfully.",
          functionName: "wallet-issuer",
          userId: caller.userId,
          subjectType: "rs_membership",
          subjectId: body.membershipId ?? null,
          metadata: {
            action: "rayon_membership",
            wallet_pass_id: response.walletPassId,
            class_id: response.classId,
            object_id: response.objectId,
            latency_ms: Date.now() - startedAt,
          },
        });

        return jsonResponse({ success: true, ...response });
      }
      default:
        return errorResponse("Unsupported wallet action.", 400, {
          action: body.action ?? null,
        });
    }
  } catch (error) {
    if (error instanceof SyntaxError) {
      return errorResponse("Invalid JSON body.", 400);
    }

    if (error instanceof HttpError) {
      return errorResponse(error.message, error.status, error.details);
    }

    console.error("wallet-issuer failed", error);

    const adminClient = createAdminClient();
    await recordOperationalHealthEvent(adminClient, {
      service: "wallet_sync",
      component: "wallet-issuer",
      status: "error",
      severity: "critical",
      issueCode: "wallet_sync_failed",
      message: error instanceof Error
        ? error.message
        : "Wallet issuance failed.",
      functionName: "wallet-issuer",
      userId: callerUserIdForTelemetry,
      subjectType: "rs_ticket",
      subjectId: ticketIdForTelemetry,
    });
    await recordEdgeFunctionFailure(adminClient, {
      functionName: "wallet-issuer",
      error,
      userId: callerUserIdForTelemetry,
      subjectType: "rs_ticket",
      subjectId: ticketIdForTelemetry,
    });

    return errorResponse(
      error instanceof Error ? error.message : "Wallet issuance failed.",
      500,
    );
  }
});

async function requireCaller(
  authorization: string,
): Promise<AuthenticatedCaller> {
  const client = createUserClient(authorization);
  const {
    data: { user },
    error,
  } = await client.auth.getUser();

  if (error || !user) {
    throw new HttpError(401, "Authentication required.");
  }

  return { userId: user.id };
}
