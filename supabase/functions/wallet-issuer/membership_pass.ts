/**
 * membership_pass.ts — Rayon Sports membership wallet pass issuance.
 *
 * Handles loading membership data, ensuring Wallet class/object exist,
 * and returning a save URL for the user's Google Wallet.
 */

import { createAdminClient } from "../_shared/supabase.ts";
import {
  type AuthenticatedCaller,
  createSaveUrl,
  HttpError,
  loadWalletConfig,
  localizedString,
  normalizeNullableString,
  persistWalletPass,
  unwrapSingleRecord,
  walletApiGet,
  walletApiRequest,
} from "./wallet_api.ts";

// ── Types ──────────────────────────────────────────────────────
export type RayonMembershipRecord = {
  id: string;
  userId: string;
  tier: string;
  points: number;
  status: string;
  holderName: string;
  joinedAt: string;
};

// ── Main entry point ───────────────────────────────────────────
export async function issueRayonMembershipWalletPass(options: {
  caller: AuthenticatedCaller;
  membershipId?: string;
}) {
  const { caller, membershipId } = options;
  if (!membershipId) {
    throw new HttpError(400, "membershipId is required.");
  }

  const config = loadWalletConfig();
  const admin = createAdminClient();

  const membership = await loadRayonMembership(admin, membershipId);
  if (membership.userId !== caller.userId) {
    throw new HttpError(403, "Membership does not belong to this user.");
  }

  const classId = `${config.issuerId}.RS_MEMBERSHIP_GENERIC`;
  const objectId = `${config.issuerId}.RS_MEMB_${membership.id.replace(
    /-/g,
    "_",
  )}`;

  await ensureGenericClass(config, classId);
  await ensureGenericObject(config, objectId, classId, membership);

  const saveUrl = await createSaveUrl(config, objectId);

  const walletPassId = await persistWalletPass(admin, {
    userId: options.caller.userId,
    partnerId: null, // Global RS context
    entityType: "rs_membership",
    entityId: membership.id,
    passType: "generic_membership",
    classId,
    objectId,
    saveUrl,
    payload: membership,
  });

  return {
    walletPassId,
    classId,
    objectId,
    saveUrl,
  };
}

// ── Data loading ───────────────────────────────────────────────
async function loadRayonMembership(
  admin: ReturnType<typeof createAdminClient>,
  membershipId: string,
): Promise<RayonMembershipRecord> {
  const { data, error } = await admin
    .from("rs_fan_memberships")
    .select("*, users!inner(full_name)")
    .eq("id", membershipId)
    .maybeSingle();

  if (error) {
    throw new HttpError(500, "Failed to load membership.", {
      membershipId,
      details: error.message,
    });
  }

  if (!data) {
    throw new HttpError(404, "Membership not found.");
  }

  const user = unwrapSingleRecord(data.users);

  return {
    id: `${data.id ?? ""}`.trim(),
    userId: `${data.user_id ?? ""}`.trim(),
    tier: `${data.tier ?? "Blue"}`.trim(),
    points: Number(data.points ?? 0),
    status: `${data.status ?? "active"}`.trim().toLowerCase(),
    holderName: normalizeNullableString(user?.full_name) ?? "Cool Fan",
    joinedAt: `${data.created_at ?? ""}`.trim(),
  };
}

// ── Wallet class/object management ─────────────────────────────
async function ensureGenericClass(
  config: ReturnType<typeof loadWalletConfig>,
  classId: string,
) {
  const existing = await walletApiGet(
    config,
    `/genericClass/${encodeURIComponent(classId)}`,
  );
  if (existing) {
    return;
  }

  await walletApiRequest(config, "/genericClass", {
    method: "POST",
    body: JSON.stringify({
      id: classId,
      issuerName: config.issuerName,
      reviewStatus: "UNDER_REVIEW",
    }),
  });
}

async function ensureGenericObject(
  config: ReturnType<typeof loadWalletConfig>,
  objectId: string,
  classId: string,
  membership: RayonMembershipRecord,
) {
  const existing = await walletApiGet(
    config,
    `/genericObject/${encodeURIComponent(objectId)}`,
  );
  if (existing) {
    return;
  }

  await walletApiRequest(config, "/genericObject", {
    method: "POST",
    body: JSON.stringify({
      id: objectId,
      classId,
      state: "ACTIVE",
      barcode: {
        type: "QR_CODE",
        value: `COOL-MEMB:${membership.id}`,
        alternateText: membership.id,
      },
      cardTitle: localizedString("Rayon Sports Membership", "en"),
      header: localizedString(membership.tier, "en"),
      subheader: localizedString(`${membership.points} Points`, "en"),
      heroImage: {
        sourceUri: {
          uri: "https://cool.ikanisa.com/assets/images/partners/rayon_sports_logo.png",
        },
      },
      textModulesData: [
        {
          id: "tier",
          header: "Tier",
          body: membership.tier,
        },
        {
          id: "points",
          header: "Points",
          body: `${membership.points}`,
        },
        {
          id: "holder",
          header: "Fan",
          body: membership.holderName,
        },
      ],
      linksModuleData: {
        uris: [
          {
            id: "open_profile",
            description: "View in Cool",
            uri: `${config.appBaseUrl.replace(/\/$/, "")}/profile`,
          },
        ],
      },
    }),
  });
}
