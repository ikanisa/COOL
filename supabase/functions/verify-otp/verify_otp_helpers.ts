/**
 * verify-otp helper functions.
 *
 * Auth strategy: WhatsApp OTP → deterministic email/password identity → session.
 *
 * GoTrue does not natively support "external OTP verified, give me a session",
 * so we maintain a synthetic `wa-<hash>@auth.cool.local` email identity per
 * phone number. The password is derived deterministically from a server secret
 * so it never needs to be stored or communicated.
 *
 * Key resilience rules:
 *  - If the RPC `find_auth_user_by_phone_or_email` is missing, fall back to
 *    paginated admin list.
 *  - If GoTrue cannot find a user that postgres says exists (orphaned/seeded
 *    row), treat it as "no user" and create a fresh one.
 *  - If `signInWithPassword` fails after user creation, fall back to an
 *    admin-generated magic link to mint a session server-side.
 */

import { recordOtpRateEvent } from "../_shared/otp_abuse.ts";
import { recordEdgeFunctionFailure } from "../_shared/observability.ts";
import { derivePhonePassword } from "../_shared/security.ts";
import { createAdminClient, createAnonClient } from "../_shared/supabase.ts";
import { isMissingRelationError } from "../_shared/http.ts";

// ─── Types ───────────────────────────────────────────────────────────────────

export type AdminClient = ReturnType<typeof createAdminClient>;

export type VerifyOtpFailureDependencies = {
  createAdminClient: () => AdminClient;
  recordEdgeFunctionFailure: typeof recordEdgeFunctionFailure;
};

type AuthUserLike = {
  id: string;
  email?: string | null;
  phone?: string | null;
  created_at?: string | null;
  phone_change?: string | null;
  user_metadata?: Record<string, unknown> | null;
};

const AUTH_USER_METADATA = {
  auth_strategy: "custom_whatsapp_otp",
  country: "RW",
  language_code: "en",
  market: "RW",
  ui_language: "en",
} as const;

// ─── Predicates ──────────────────────────────────────────────────────────────

/** Returns true if the sign-in error can be recovered by creating/updating the user. */
export function isRecoverableSignInError(error: unknown): boolean {
  if (!error) return false;
  const msg = (error instanceof Error ? error.message : JSON.stringify(error))
    .toLowerCase();
  return (
    msg.includes("invalid login credentials") ||
    msg.includes("user not found") ||
    msg.includes("email not confirmed") ||
    msg.includes("invalid grant")
  );
}

// ─── Auth user lookup ────────────────────────────────────────────────────────

/**
 * Find a GoTrue auth user by phone or derived email.
 *
 * Strategy:
 *  1. Try the `find_auth_user_by_phone_or_email` RPC (fast, indexed).
 *  2. If the RPC doesn't exist, fall back to paginated admin list.
 *  3. If the user ID exists in postgres but GoTrue can't find it (orphaned
 *     seed row), return null so the caller creates a fresh user.
 */
async function findAuthUserViaGoTrue(
  adminClient: AdminClient,
  phone: string,
  email: string,
): Promise<AuthUserLike | null> {
  // Step 1 — try RPC
  const rpcResult = await adminClient.rpc(
    "find_auth_user_by_phone_or_email",
    { p_phone: phone, p_email: email },
  );

  if (rpcResult.error) {
    if (isMissingRpcError(rpcResult.error)) {
      return findAuthUserByAdminList(adminClient, phone, email);
    }
    throw rpcResult.error;
  }

  const userId = (rpcResult.data as Array<{ user_id: string }> | null)
    ?.[0]?.user_id?.toString().trim();
  if (!userId) return null;

  // Step 2 — verify GoTrue can actually see this user
  const goTrueResult = await adminClient.auth.admin.getUserById(userId);
  if (goTrueResult.error || !goTrueResult.data.user) {
    const msg = goTrueResult.error?.message?.toLowerCase() ?? "";
    if (msg.includes("not found")) {
      console.warn(`findAuthUserViaGoTrue: orphaned row ${userId}, returning null`);
      return null;
    }
    throw goTrueResult.error ?? new Error("Could not load auth user");
  }

  return goTrueResult.data.user;
}

function isMissingRpcError(error: unknown): boolean {
  if (!error) return false;
  const msg = (error instanceof Error ? error.message : JSON.stringify(error))
    .toLowerCase();
  return (
    msg.includes("find_auth_user_by_phone_or_email") &&
    (msg.includes("does not exist") ||
      msg.includes("could not find") ||
      msg.includes("schema cache") ||
      msg.includes("pgrst"))
  );
}

/** Paginated fallback: scan all GoTrue users to find a match by phone/email. */
async function findAuthUserByAdminList(
  adminClient: AdminClient,
  phone: string,
  email: string,
): Promise<AuthUserLike | null> {
  const perPage = 200;
  let page = 1;

  while (true) {
    const result = await adminClient.auth.admin.listUsers({ page, perPage });
    if (result.error) throw result.error;

    const users = (result.data?.users ?? []) as AuthUserLike[];
    if (users.length === 0) return null;

    // Sort by match quality then creation date
    users.sort((a, b) => {
      const pDiff = matchPriority(a, phone, email) - matchPriority(b, phone, email);
      if (pDiff !== 0) return pDiff;
      return (Date.parse(a.created_at ?? "") || 0) - (Date.parse(b.created_at ?? "") || 0);
    });

    for (const u of users) {
      if (matchPriority(u, phone, email) < 9) return u;
    }

    if (users.length < perPage) return null;
    page += 1;
  }
}

function matchPriority(user: AuthUserLike, phone: string, email: string): number {
  if ((user.email ?? "").trim() === email) return 0;
  if ((user.phone ?? "").trim() === phone) return 1;
  if ((user.phone_change ?? "").trim() === phone) return 2;
  const metaPhone = (user.user_metadata?.["phone"] as string | undefined)?.trim();
  if (metaPhone === phone) return 3;
  return 9;
}

// ─── Auth user provisioning ──────────────────────────────────────────────────

/**
 * Ensure a GoTrue-managed auth user exists for the given phone.
 *
 * - If the user exists and GoTrue recognizes it → update credentials.
 * - If the user is orphaned (GoTrue can't see it) → create fresh.
 * - If creation collides with a stale row → delete orphan and retry.
 */
export async function ensureAuthUser(
  adminClient: AdminClient,
  phone: string,
  email: string,
): Promise<{ userId: string; password: string; created: boolean }> {
  const password = await derivePhonePassword(phone);
  const metadata = { ...AUTH_USER_METADATA, phone };

  const existing = await findAuthUserViaGoTrue(adminClient, phone, email);

  if (existing) {
    const update = await adminClient.auth.admin.updateUserById(existing.id, {
      email,
      email_confirm: true,
      password,
      user_metadata: { ...(existing.user_metadata ?? {}), ...metadata },
    });

    if (!update.error) {
      return { userId: existing.id, password, created: false };
    }

    // GoTrue can't update this user (e.g. orphaned) → fall through to create
    const msg = update.error.message?.toLowerCase() ?? "";
    if (!msg.includes("not found")) throw update.error;
    console.warn(`ensureAuthUser: update failed for ${existing.id}, creating fresh user`);
  }

  return createFreshAuthUser(adminClient, email, password, phone, metadata);
}

async function createFreshAuthUser(
  adminClient: AdminClient,
  email: string,
  password: string,
  phone: string,
  metadata: Record<string, string>,
): Promise<{ userId: string; password: string; created: boolean }> {
  const result = await adminClient.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    phone,
    phone_confirm: true,
    user_metadata: metadata,
  });

  if (!result.error && result.data.user) {
    return { userId: result.data.user.id, password, created: true };
  }

  // If creation fails due to a collision with an orphaned row, clean up and retry
  const errMsg = result.error?.message?.toLowerCase() ?? "";
  if (
    errMsg.includes("already been registered") ||
    errMsg.includes("already exists") ||
    errMsg.includes("unique")
  ) {
    console.warn("ensureAuthUser: collision with stale row, cleaning up");
    // Try to find and delete the conflicting row via direct DB cleanup
    // (GoTrue deleteUser may also fail for orphans, but worth trying)
    const rpcResult = await adminClient.rpc(
      "find_auth_user_by_phone_or_email",
      { p_phone: phone, p_email: email },
    );
    const orphanId = (rpcResult.data as Array<{ user_id: string }> | null)
      ?.[0]?.user_id?.toString().trim();

    if (orphanId) {
      await adminClient.auth.admin.deleteUser(orphanId).catch(() => {
        // If GoTrue can't delete it either, the DB row will need manual cleanup
        console.error(`Failed to delete orphaned user ${orphanId}`);
      });
    }

    const retry = await adminClient.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      phone,
      phone_confirm: true,
      user_metadata: metadata,
    });

    if (!retry.error && retry.data.user) {
      return { userId: retry.data.user.id, password, created: true };
    }
    throw retry.error ?? new Error("Could not create auth user after cleanup");
  }

  throw result.error ?? new Error("Could not create auth user");
}

// ─── Session creation ────────────────────────────────────────────────────────

/**
 * Sign in via the anon client with derived email + password.
 * This is the primary way to obtain a session after OTP verification.
 */
export async function signInWithDerivedPassword(
  email: string,
  password: string,
) {
  return await createAnonClient().auth.signInWithPassword({ email, password });
}

/**
 * Fallback: mint a session via admin-generated magic link when
 * signInWithPassword fails (e.g. GoTrue propagation delay).
 */
export async function mintSessionViaMagicLink(
  adminClient: AdminClient,
  email: string,
) {
  const magicResult = await adminClient.auth.admin.generateLink({
    type: "magiclink",
    email,
  });
  if (magicResult.error || !magicResult.data) {
    throw magicResult.error ?? new Error("Could not generate magic link");
  }

  const verifyResult = await createAnonClient().auth.verifyOtp({
    token_hash: magicResult.data.properties.hashed_token,
    type: "magiclink",
  });
  if (verifyResult.error || !verifyResult.data.session) {
    throw verifyResult.error ?? new Error("Could not create session via magic link");
  }

  return verifyResult.data;
}

// ─── App user lookup ─────────────────────────────────────────────────────────

/** Check if there's already a row in public.users for this phone. */
export async function findExistingAppUser(
  adminClient: AdminClient,
  phone: string,
): Promise<string | null> {
  try {
    const result = await adminClient
      .from("users")
      .select("id")
      .eq("phone", phone)
      .limit(1)
      .maybeSingle();

    if (!result.error && result.data) {
      return result.data.id?.toString() ?? null;
    }
    if (result.error && !isMissingRelationError(result.error)) {
      throw result.error;
    }
  } catch (error) {
    if (!isMissingRelationError(error)) throw error;
  }
  return null;
}

// ─── Telemetry ───────────────────────────────────────────────────────────────

export async function reportVerifyOtpFailure(
  deps: VerifyOtpFailureDependencies,
  adminClient: AdminClient | null,
  phone: string | null,
  error: unknown,
) {
  try {
    await deps.recordEdgeFunctionFailure(
      adminClient ?? deps.createAdminClient(),
      {
        functionName: "verify-otp",
        error,
        subjectType: "otp_phone",
        subjectId: phone,
        metadata: {
          phone_suffix: phone?.slice(-4) ?? null,
        },
      },
    );
  } catch (reportError) {
    console.error("verify-otp telemetry failed", reportError);
  }
}

export async function recordVerifyRateEvents(
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
      action: "verify_phone",
      actorKey: options.phoneActorKey,
      outcome: options.outcome,
      phone: options.phone,
      metadata: options.metadata,
    }),
  ];

  if (options.ipActorKey != null) {
    writes.push(
      recordOtpRateEvent(adminClient, {
        action: "verify_ip",
        actorKey: options.ipActorKey,
        outcome: options.outcome,
        phone: options.phone,
        metadata: options.metadata,
      }),
    );
  }

  await Promise.all(writes);
}
